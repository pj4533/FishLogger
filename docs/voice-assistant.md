# Voice Assistant & Negative‑Signal Capture

> Branch: `voice-assistant`. This document is the full design + decision record for
> the work done in this cycle, written so a future change can be made with all the
> context that went into it. If you only read one section, read **Key decisions &
> why** — that's where the non‑obvious choices live.

---

## 1. Why this exists (the problem)

Before this work, FishLogger only recorded **catches** — i.e. only the *positive*
signal. The angler wanted the *negative and contextual* data too, because that's
what actually makes a fishing log useful for pattern‑finding:

- **What setup was in the water when nothing bit.** ("I threw a frog for 40 min
  and got nothing" is as informative as a catch.)
- **Bites / blowups / follows that did NOT hook up.** Topwater explosions you
  missed are real data.
- **Sub‑spot** — *where on the spot* you were ("over by the dam", "the lily pads
  on the north bank"), finer than the GPS spot cluster.
- **Who caught it** (`caughtBy`) — already existed on the manual form; needed to
  flow through the new capture path too.

Typing all of that into a form while actively fishing is too slow. So the capture
mechanism is a **hands‑free voice "fishing buddy"**: tap a mic, talk naturally
("switching to a frog", "big blowup, missed him", "landed a three‑pound
largemouth"), and an OpenAI Realtime model uses **tool calling** to mutate the
session in real time and speak a short, in‑character confirmation back.

### The load‑bearing design decision

**The angler only narrates state‑changes and discrete events.** He will *not* say
"I fished 20 minutes and caught nothing." Instead the app **derives** the no‑catch
/ coverage information from the event timeline when the session ends. Everything is
then exportable as JSON for offline analysis.

This is why the data model is an **event log** (`SessionEvent`) plus a **pure
derivation** (`CoverageDerivation`) rather than the angler manually bracketing
"barren" stretches.

---

## 2. Data model

All additions are **additive** (new model + optional/defaulted fields) so SwiftData
lightweight migration handles an existing store without wiping it. See
[§8 Migration safety](#8-migration-safety) — this was explicitly verified.

### `Setup` — `Models/Setup.swift` (new)

A plain value type describing what you're fishing with right now:
`rod, reel, line, lure, color, technique` — **all optional** so the assistant can
update incrementally ("switch to a black frog" only sets `lure` + `color`).

- `Codable, Equatable, Hashable, Sendable`.
- `isEmpty`, and `merging(_ partial:)` (non‑nil fields of `partial` win).
- **Stored as a JSON string, not as a SwiftData composite attribute.** This is a
  deliberate workaround: declaring `var currentSetup: Setup` directly on a `@Model`
  breaks SwiftData's macro‑synthesized conformances (it cannot persist a composite
  struct attribute cleanly). So `Session`/`Catch` store `…JSON: String?` columns and
  expose a typed computed accessor (`Setup(jsonString:)` / `.jsonString`).

### `SessionEvent` — `Models/SessionEvent.swift` (new `@Model`)

One row per narrated state‑change or event. Flat fields, enums stored as `…Raw`
strings (matches the existing `pressureTrendRaw` convention):

- `id, timestamp, kindRaw, session: Session?`
- payloads (all optional): `setupSnapshotJSON`, `subSpot`, `outcomeRaw`, `detail`,
  `lat/lon`.
- `enum SessionEventKind { setupChange, subSpotChange, bite, note }`
- `enum BiteOutcome { bite, missed, blowup, follow }`

**Each `.setupChange` stores the FULL resolved setup**, not a delta. That makes
coverage derivation a trivial state walk — at any timestamp the "current setup" is
just the most recent `.setupChange` snapshot. Catches are **not** duplicated as
events; they remain the authoritative `Catch` rows and are merged into the timeline
by timestamp at derivation/export time.

### `Session` additions — `Models/Session.swift`

```
@Relationship(deleteRule: .cascade, inverse: \SessionEvent.session)
var events: [SessionEvent] = []          // cascade-delete with the session
var currentSetupJSON: String?            // live setup (typed via `currentSetup`)
var currentSubSpot: String = ""          // live micro-location
var currentAngler: String = ""           // default caughtBy for this session
var currentSetup: Setup { get/set }      // computed over currentSetupJSON
```

### `Catch` additions — `Models/Catch.swift`

```
var setupSnapshotJSON: String?           // setup at the moment of the catch
var subSpotSnapshot: String?             // sub-spot at the moment of the catch
var setupSnapshot: Setup? { get/set }    // computed
```

`rodUsed` / `baitUsed` were **kept** (AutocompleteService and existing DTOs depend
on them). When a catch is created, `SessionEventLogger.stampSetup` mirrors
`setup.rod → rodUsed` and `setup.lure → baitUsed` if those are empty, so the legacy
fields stay populated.

### `SessionEventLogger` — `Services/SessionEventLogger.swift` (new)

`@MainActor enum` that is the **single mutation point** for session state, so the
manual UI and the assistant can't drift. Each method mutates live state *and*
appends the matching `SessionEvent`:

- `changeSetup`, `changeSubSpot`, `logBite`, `logNote`, `changeAngler`
- `stampSetup(on:from:)` — stamps a new `Catch` with the session's setup/sub‑spot,
  mirrors rod/lure, and **defaults `caughtBy` to `session.currentAngler`** when the
  catch doesn't name someone.

### `CoverageDerivation` — `Services/CoverageDerivation.swift` (new)

Pure, SwiftData‑free static function (unit‑testable, mirrors `SpotClusteringService`
style). **Computed on demand at export time; never persisted** — same
"derive, don't store" precedent as the solunar intervals.

- `CoverageSegment { start, end, durationSeconds, setup, subSpot, catchIds,
  catchCount, biteCount, outcome }`, `enum SegmentOutcome { caught, bites, barren }`.
- Algorithm: half‑open `[start, end)` walk over the boundary timestamps of
  `.setupChange` / `.subSpotChange` events; attribute catches and `.bite` events to
  the segment they fall in; `outcome = caught>0 ? .caught : bites>0 ? .bites :
  .barren`. Ongoing sessions terminate the final segment at an injected `now`.
- Tested edge cases (11 of them, see `CoverageDerivationTests`): zero events,
  setup change with no action → barren, coincident setup+sub‑spot change collapses
  to one boundary, change exactly at `startedAt`, catch/bite exactly on a boundary
  (attributed to the *new* segment, since the change is narrated before the cast).

### `ExportService` v2 — `Services/ExportService.swift`

- `exportSchemaVersion = 2`.
- `SessionDTO` gains `currentSetup`, `currentSubSpot`, `currentAngler`, `events[]`
  (time‑sorted, all kinds), `coverageSegments[]`.
- `CatchDTO` gains `setup` and `subSpot`.
- New `SessionEventDTO`, `CoverageSegmentDTO`. `eventCount` / `segmentCount` summary
  ints on the envelope.
- `buildSnapshot(now:)` threads `now` so ongoing‑session derivation is reproducible.

---

## 3. The assistant

```
Services/Assistant/
  RealtimeClient.swift        native WebSocket transport (OpenAI Realtime, GA schema)
  RealtimeAudioEngine.swift   AVAudioEngine mic capture + playback
  AssistantService.swift      @Observable orchestrator (phases, event routing)
  AssistantTools.swift        tool schemas + dispatch → SessionEventLogger
  AssistantInstructions.swift system prompt: context block + personality + rules
  KeychainManager.swift       stores the OpenAI key
Views/Assistant/AssistantPanel.swift   the in-session UI (talk button, HEARD feed)
Views/Settings/SettingsView.swift      API key entry
```

### `RealtimeClient` — native WebSocket, no dependencies

`URLSessionWebSocketTask` straight to `wss://api.openai.com/v1/realtime?model=…`
with `Authorization: Bearer <key>`. **No `OpenAI-Beta` header** (the GA endpoint
rejects it with `beta_api_shape_disabled`).

`configure()` sends one `session.update` with the **GA `session.type = "realtime"`**
shape (nested `audio.input` / `audio.output`, not the old flat beta fields):

- input: `audio/pcm` @ 24 kHz, `turn_detection: semantic_vad`,
  `transcription: gpt-4o-mini-transcribe`
- output: `audio/pcm` @ 24 kHz, `voice: marin`, `output_modalities: ["audio"]`
- `tools` (plain JSON dicts), `tool_choice: auto`

Tool round‑trip: model emits `response.function_call_arguments.done` →
`AssistantService` dispatches → `sendFunctionResult(callId:output:)` posts a
`function_call_output` **and** a `response.create`, which is what makes the model
*speak the confirmation* (the snark). The spoken reply comes back as
`response.output_audio_transcript.done` → surfaced in the UI as `lastAssistantReply`.

Model constant: `RealtimeClient.model = "gpt-realtime-mini"` (see decisions §4).

### `RealtimeAudioEngine`

AVAudioEngine: input tap → `AVAudioConverter` → PCM16 24 kHz mono → sink; playback
via a player node (manual int16→float32). Audio session is
`.playAndRecord` / `.voiceChat` with `[.defaultToSpeaker, .allowBluetooth]` —
`.voiceChat` gives **hardware echo cancellation** so the model doesn't hear itself.
Capture‑thread fields are `nonisolated(unsafe)` (the standard real‑time‑audio escape
hatch).

**Critical fix:** `enqueue()` guards `engine.isRunning, player.engine != nil`.
The model streams audio back even in the text‑only debug path (where capture is never
started); without the guard, scheduling a buffer on an unstarted player node crashes.

### `AssistantService`

`@MainActor @Observable`. `Phase { idle, connecting, listening, error }`. Routes
realtime events to dispatch + persistence + the HEARD feed, and refreshes the
instructions after every state‑changing tool (so the model always has fresh
context). Exposes `lastTranscript` (what you said) and `lastAssistantReply` (what
it said). `#if DEBUG` it has `debugConnectTextOnly` (connect with **no mic**) and
canned/text‑turn hooks — see "text‑only debug path" below.

### `AssistantTools` — 7 tools

| Tool | Required | Action (via `SessionEventLogger`) |
|---|---|---|
| `update_setup` | — | merge into current setup → `.setupChange` |
| `set_sub_spot` | `location` | set sub‑spot → `.subSpotChange` |
| `set_angler` | `name` | set `session.currentAngler` (default credit) |
| `log_bite` | `kind` enum | `.bite` stamped with current setup + sub‑spot |
| `log_catch` | — | create `Catch` (setup snapshot, species match, `caughtBy`) |
| `add_note` | `text` | `.note` |
| `end_session` | — | set `endedAt` (idempotent) |

**Dispatch is lenient on purpose.** It parses arguments with `JSONSerialization`
+ `str()/num()/bool()` coercion helpers rather than strict `Codable`. The live model
sends odd arg shapes (extra keys, numbers as strings, the whole blob as one field);
strict decoding threw "Bad arguments". `add_note` in particular accepts
`text`/`note`/`content` or a raw‑blob fallback.

### `AssistantInstructions`

Builds the prompt fresh each refresh: role + personality, a **current‑context
block** (spot, sub‑spot, angler, current setup, recent events), the **known‑species
list** (so spoken names map to canonical `Species`), and the behavior rules. The two
behavior rules worth knowing about (§4): setup‑before‑catch, and `set_angler` vs
`caughtBy` disambiguation.

### UI — `AssistantPanel`, `SettingsView`

- The panel shows only on **ongoing** sessions. Talk button, status, the assistant's
  reply (italic, `Color.sunset`), and a **HEARD** feed of tool‑result summaries
  (visual confirmation that something was recorded).
- `#if DEBUG` the panel has a **"send live phrase"** button per tool and a
  **"Connect text‑only (no mic)"** entry — this is the workhorse for testing in the
  simulator (see §7 and the mobile‑mcp guide).
- `SettingsView` (reached via a gear in the session list toolbar — **not** a 6th
  tab) stores the `sk-` key in the keychain with a "Verified" badge.

---

## 4. Key decisions & why

These are the non‑obvious calls. Change them only knowing what they cost.

### Removed the `swift-realtime-openai` dependency
Originally the assistant used the third‑party `swift-realtime-openai` package. It
pulled in a **WebRTC binary xcframework** and **MetaCodable**, the latter a macro
that forced `-skipMacroValidation` / a Trust‑&‑Enable prompt on every clean build.
The user wanted minimal third‑party deps and no macro‑trust friction, so it was
ripped out and replaced with `RealtimeClient` (~215 lines, zero deps). Wire format
was verified byte‑for‑byte against the official `openai` npm SDK
(`openai/realtime/ws.mjs`): `?model=` in the URL, `Bearer` auth, **no beta header**.

### GA Realtime schema, not the beta shape
The docs/examples online are split between the old beta event schema and the GA
schema. We use **GA**: `session.type = "realtime"`, nested `audio.{input,output}`,
and **no `OpenAI-Beta: realtime=v1` header** (sending it returns
`beta_api_shape_disabled`). If you ever see that error, a beta header has crept back
in.

### Model: `gpt-realtime-mini`
The user asked specifically for `gpt-realtime-2` ("the latest"). It is **in the
account's model catalog but not granted runtime access** — the WebSocket returns
`model_not_found`, and OpenAI's *own* SDK fails identically with the same key, so
this is an account gate, not our bug. `gpt-realtime-mini` is enabled and tool‑calls
correctly, so we ship that and left a comment to swap to `gpt-realtime-2` once
runtime access is granted. (Note: the `/v1/realtime/client_secrets` mint endpoint
does **not** validate the model — it happily mints for a fake model — so a mint
success proves nothing; the WebSocket `model_not_found` is the authoritative check.)

### Standing key, no backend (accepted tradeoff)
Realtime normally wants an **ephemeral** key minted server‑side so the standing key
never ships to the client. FishLogger has no backend; for single‑user personal use
we connect directly with the standing `sk-` key from the device keychain. This is
documented in code and the Settings footer. **Before any public distribution**, add
a tiny proxy that mints `POST /v1/realtime/client_secrets` and pass that token to
`connect(apiKey:)` — *only the token source changes.*

### Billing reality
The OpenAI Realtime/audio API is **pay‑as‑you‑go Platform billing**. A
ChatGPT Plus/Pro or Codex subscription **cannot** pay for it (the "Sign in with
ChatGPT" OAuth token is scoped to the Codex agent only). The key must be a standard
`sk-` Platform key.

### `SWIFT_COMPILATION_MODE = wholemodule` for Debug
There is a **SwiftData `@Model` batch‑mode compiler bug**: adding *any* new file to
the module broke `Session`'s macro‑synthesized `Hashable` conformance, surfacing as
`NavigationLink(value: session)` "Session does not conform to Hashable". Diagnosed in
an isolated worktree (even a dummy struct file reproduced it). Fixed by forcing
`wholemodule` on the app's **Debug** config (`project.pbxproj`, line ~422). Release
was already wholemodule. If a future file addition resurrects a phantom
"doesn't conform to Hashable", this is why.

### `Setup` stored as JSON
See §2 — a composite struct attribute breaks `@Model` synthesis, so setups live as
`…JSON: String?` columns with typed computed accessors.

### `caughtBy`: session angler + per‑catch override, and the disambiguation
- The session has a `currentAngler` (default credit), settable via `set_angler`.
- `log_catch` takes an optional `caughtBy`; `stampSetup` defaults it to the session
  angler when blank.
- **The model confused "who's fishing" with "who caught this fish."** Saying
  *"Dave just landed a four‑pounder"* first triggered `set_angler(Dave)` instead of
  `log_catch(caughtBy: Dave)`. Fixed in instructions: `set_angler` is **only** for
  self‑identification ("I'm PJ", "me and Dave today"); reporting that a named person
  landed a fish is a `log_catch` with `caughtBy`. Verified live afterward.

### Setup‑before‑catch is a *prompt gate*, not a hard block
Setup is required context for a catch to be useful. If `currentSetup` is empty and
the angler reports a catch/bite, the model is instructed to **ask what they're
throwing**, call `update_setup`, then log. It does **not** hard‑block at the data
layer (a catch with no setup is still allowed). The **angler** is nudged early but
does **not** gate a catch — that asymmetry is intentional (setup matters more for
analysis than attribution). Manual catches already capture rod/bait in the form, so
that path was already covered.

### Personality: modeled on CARROT Weather
The first personality pass was cheesy (puns, exclamation‑hype, pep talk —
"reel in the fun!", "ready to croak!"). The user rejected it and pointed at
**CARROT Weather**'s voice. Rewrote the instructions to be **dry, deadpan, cutting,
a little dark, on the angler's side but unimpressed**, with on‑tone examples and an
explicit **banned list** (exclamation‑point hype, puns, pep‑talk, "hotshot", emoji,
rhyming). Verified live, e.g. a missed blowup →
*"A blowup and you still whiffed. The fish is telling its friends. Logged."* If you
retune the voice, edit the `PERSONALITY` block in `AssistantInstructions.swift`;
keep the banned list or the model drifts back to cheese.

---

## 5. The text‑only debug path (how this was made testable)

The simulator can't take real mic input, and a live mic in the sim **picks up the
Mac's ambient room audio**, which makes the model react to noise (phantom notes).
So `AssistantService.debugConnectTextOnly` connects with **`captureAudio: false`** —
full live model + tool calling, no microphone. The panel's per‑tool "send live
phrase" buttons inject canned user turns over that connection. This is how every
tool was verified end‑to‑end in the sim. (The audio still streams *back* from the
model in this mode, which is why the `enqueue()` engine‑running guard exists.)

There are also **offline** Node scripts (kept in the session scratchpad, not
committed) that drove the live Realtime API directly to confirm wire format,
tool‑calling, the personality, and the `caughtBy` disambiguation before touching the
app. The pattern: connect via the `openai` SDK's `OpenAIRealtimeWS`, send a text
turn, assert on the `function_call_arguments.done` name/args, and for the snark do
the full round‑trip (return a `function_call_output` + `response.create` and read
the text reply).

---

## 6. Testing — unit

`FishLoggerTests/`:

- `CoverageDerivationTests` — 11 edge cases; durations sum to session duration.
- `AssistantToolDispatchTests` — all 7 tools against an in‑memory `ModelContainer`
  with canned JSON; species matching; `set_angler`/`caughtBy` defaults; tool‑schema
  validity (count == 7, each a `function` with object params).
- `AssistantServiceTests` — the no‑key error path with `MockKeychain`.

**Test gotcha (cost a crash):** a test must **retain the `ModelContainer`**. Writing
`let context = try TestContainer.make().mainContext` deallocates the container and
crashes; use `let (container, context) = try makeContext()` and keep `container`
alive.

Run:
```bash
xcodebuild -project FishLogger.xcodeproj -scheme FishLogger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FishLoggerTests test
```
(Per the global build rule: always pass `-destination`; never bare `xcodebuild` for
this iOS‑only app. CLI builds historically also needed `-skipMacroValidation` for the
old package — no longer required now that the package is gone.)

---

## 7. Testing — in‑app (mobile‑mcp)

The whole feature was driven end‑to‑end in the iOS Simulator with **mobile‑mcp**.
That tooling has its own sharp edges (simulator state, keyboard focus, tab‑bar
overlap, GPS), all written up separately so future testing doesn't rediscover them:

➡️ **[mobile-mcp-testing.md](./mobile-mcp-testing.md)**

Verified in‑app: all 7 tools (HEARD feed + persisted catches with correct
`caughtBy`), the snarky reply surfaced in the UI, and every other tab
(Sessions/Spots/Conditions/Species/Leaderboard, manual add‑catch, catch edit/save,
session edit, delete‑with‑confirmation, export share sheet).

---

## 8. Migration safety (old data must not be wiped)

`FishLoggerApp.swift` has a **wipe‑on‑failure fallback**: if the `ModelContainer`
fails to open the existing store, it deletes `default.store*` and starts fresh.
That's catastrophic for a user with months of real catches, so the additive‑schema
claim was **empirically verified**, not assumed:

1. Built **main** (old schema) in an isolated git worktree, installed it fresh,
   created real old‑schema data (2 sessions across 2 spots, 3 catches, a `caughtBy`).
2. Snapshotted "before" two ways: the v1 JSON export and a raw copy of
   `default.store*`.
3. Installed the **voice‑assistant** build **over** main *without uninstalling*
   (a true upgrade that preserves the data container).
4. Verified:
   - **No wipe** — no "resetting store" in the unified log; data present.
   - **Lossless** — machine‑diffed the v1 vs v2 exports: every session ID, catch ID,
     weight, species, `caughtBy`, timestamp, lat/lon **identical**.
   - Old data renders across all tabs in the new build.
   - **Forward writes work** — wrote a new `SessionEvent` + `currentSetup` into the
     migrated store (the riskiest path: a brand‑new entity into an old store) with no
     crash; it coexists with the old catches.

Conclusion: installing this version over an existing install migrates in place and
keeps working. The changes compose additively, so an even‑older store opens too.

---

## 9. Known issues / future work

- **`gpt-realtime-2`** — swap the model constant once the account is granted runtime
  access (currently `model_not_found`).
- **Public distribution** — add the ephemeral‑key proxy (§4) before shipping to
  anyone but the owner; never ship the standing key in a public build.
- **Simulator mic** — picks up Mac ambient audio; always test with
  `debugConnectTextOnly`, not the real mic, in the sim.
- **README is stale** — still says "manual‑entry only / nothing wired to a network"
  and lists four tabs. It predates both the Conditions/Sessions rework and this voice
  work. Update it when this branch merges.
- **Weight "stray digit"** seen during testing (e.g. "3.8" saving as "3.83") was a
  **mobile‑mcp decimal‑keyboard quirk**, not an app bug — the app stored exactly what
  the field held. See the mobile‑mcp guide.

---

## 10. File map (this cycle)

New:
```
Models/Setup.swift, Models/SessionEvent.swift
Services/SessionEventLogger.swift, Services/CoverageDerivation.swift
Services/Assistant/{RealtimeClient,RealtimeAudioEngine,AssistantService,
                    AssistantTools,AssistantInstructions,KeychainManager}.swift
Views/Assistant/AssistantPanel.swift
Views/Settings/SettingsView.swift
FishLoggerTests/{CoverageDerivationTests,AssistantToolDispatchTests,
                 AssistantServiceTests,MockKeychain}.swift
```
Modified:
```
Models/Session.swift, Models/Catch.swift     (additive fields)
Services/ExportService.swift                 (schema v2)
FishLoggerApp.swift                          (register SessionEvent.self)
Views/Sessions/{SessionListView,SessionDetailView,AddCatchSheet}.swift
FishLoggerTests/TestContainer.swift          (register SessionEvent.self)
FishLogger.xcodeproj/project.pbxproj         (wholemodule Debug; removed package)
.gitignore                                   (.env.local with the test key)
```
