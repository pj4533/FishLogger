# FishLogger — working notes for Claude

A cozy iOS fishing diary (SwiftUI + SwiftData, iOS 26.2, local‑only). Tabs:
Sessions, Spots, Conditions, Species, Leaderboard. The `voice-assistant` branch adds
a hands‑free voice "fishing buddy" + negative‑signal/coverage capture.

## Documentation — read these before changing related code

- **[docs/voice-assistant.md](docs/voice-assistant.md)** — full design + decision
  record for the voice assistant, `SessionEvent`/`Setup`/coverage model, the OpenAI
  Realtime client, the personality, and the migration‑safety verification. The
  **"Key decisions & why"** section is the non‑obvious stuff.
- **[docs/mobile-mcp-testing.md](docs/mobile-mcp-testing.md)** — **how to drive the
  iOS Simulator with mobile-mcp for testing.** Read this *first* before any in‑app
  testing; it documents the startup recipe and the keyboard/tab‑bar/GPS gotchas that
  otherwise eat an hour.

## Build & test

- **Always pass `-destination`.** Never run bare `xcodebuild` for this iOS‑only app —
  it defaults to macOS and fails on provisioning. Use the iPhone 17 Pro / iOS 26.2 sim.
  Prefer running tests (they pick a destination cleanly).
  ```bash
  xcodebuild -project FishLogger.xcodeproj -scheme FishLogger \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:FishLoggerTests test
  ```
- **Always build after changes** to catch errors.
- New files under `FishLogger/` are auto‑added to the target
  (`PBXFileSystemSynchronizedRootGroup`) — no pbxproj edits needed to add a file.

## Gotchas that will bite you

- **`SWIFT_COMPILATION_MODE = wholemodule` is set on Debug on purpose.** There's a
  SwiftData `@Model` batch‑mode compiler bug where adding *any* file breaks
  `Session`'s synthesized `Hashable` (surfaces as `NavigationLink(value:)` "does not
  conform to Hashable"). Don't remove the wholemodule setting. (Details in
  docs/voice-assistant.md §4.)
- **Composite struct attributes break `@Model`.** `Setup` is stored as a JSON `String?`
  column with a typed computed accessor, not as a direct SwiftData attribute. Follow
  that pattern for any new value‑type field on a model.
- **Schema changes must stay additive** (optional or defaulted fields, new entities)
  so SwiftData lightweight‑migrates an existing store. `FishLoggerApp.swift` *wipes
  the store* if the container fails to open — verify migrations against real old data
  (see docs/voice-assistant.md §8).
- **Tests must retain the `ModelContainer`** — `let (container, context) = …` and keep
  `container` alive, or it deallocates mid‑test and crashes.
- **OpenAI Realtime:** native `URLSessionWebSocketTask` client, GA schema
  (`session.type:"realtime"`, **no** `OpenAI-Beta` header), model `gpt-realtime-mini`
  (in `RealtimeClient.swift`). Test the live model with the panel's **text‑only debug
  connect** — never the sim mic (it hears the Mac's room).
- The OpenAI key is a **pay‑as‑you‑go `sk-` Platform key** (a ChatGPT/Codex sub can't
  pay for the audio API). Test keys live in gitignored `.env.local`.

## Apple docs

Use **sosumi.ai** instead of developer.apple.com (replace the host) — Apple's docs
are JS‑locked and unreadable to tools otherwise.
