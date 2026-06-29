# mobile-mcp Testing Guide (FishLogger)

Hard‑won notes for driving the iOS Simulator with **mobile-mcp**
([mobile-next/mobile-mcp](https://github.com/mobile-next/mobile-mcp)) to test
FishLogger end‑to‑end. This exists so a future session doesn't rediscover the same
sharp edges. **Read the "Reliable startup recipe" and "Gotchas" before you start —
they will save you an hour.**

mobile-mcp drives the sim through **WebDriverAgent (WDA)** + a DeviceKit UITest
runner. The companion CLI is **`mobilecli`**; on this machine it lives at:

```
/Users/pj4533/.npm/_npx/3d55143a3497ce4a/node_modules/mobilecli/bin/mobilecli-darwin-arm64
```

(That path is from an `npx` cache and can change — `find ~/.npm -name 'mobilecli-darwin-arm64'`
if it moves.)

---

## TL;DR facts

- **Test device:** iPhone 17 Pro, UDID `5C0CEF64-769D-4E7C-A04B-0E6F3F85E4D9`, **iOS 26.2**.
  FishLogger needs iOS 26.2 — a device on an older runtime (an iPhone 16 Plus auto‑booted
  on an older OS at one point) **cannot install the app**. Always target the 26.2 device by UDID.
- **Bundle id:** `com.saygoodnight.FishLogger`.
- The MCP tools (`mobile_list_elements_on_screen`, `mobile_click_on_screen_at_coordinates`,
  `mobile_type_keys`, `mobile_swipe_on_screen`, `mobile_take_screenshot`) all take a
  `device` = the UDID.
- `mobile_list_elements_on_screen` is your primary sense — it returns labels,
  **accessibility identifiers**, and **coordinates**. Identifiers (e.g. `dbg_log_catch`,
  `debugConnectTextOnly`) are stable handles; coordinates are not (see Gotcha #3).

---

## Reliable startup recipe

The single most common failure: after a sim boot/erase the app **installs but
launches to the background with a blank icon**, and WDA times out. The fix that
consistently works is **restart SpringBoard, then foreground via WDA (not simctl)**.
Use this every time you bring the app up:

```bash
DEV=5C0CEF64-769D-4E7C-A04B-0E6F3F85E4D9
MCLI=/Users/pj4533/.npm/_npx/3d55143a3497ce4a/node_modules/mobilecli/bin/mobilecli-darwin-arm64
APP=/path/to/Build/Products/Debug-iphonesimulator/FishLogger.app

xcrun simctl bootstatus $DEV -b                       # boot + wait (sims idle-shutdown between turns)
xcrun simctl location $DEV set 41.5012,-73.9826       # seed GPS (see Gotcha #5)
xcrun simctl install $DEV "$APP"                       # upgrade-installs; preserves data (see Migration)
xcrun simctl spawn $DEV launchctl stop com.apple.SpringBoard ; sleep 4   # fixes blank icon / bg launch
until "$MCLI" apps foreground --device $DEV >/dev/null 2>&1; do sleep 2; done   # wait for WDA
for i in 1 2 3; do "$MCLI" apps launch --device $DEV com.saygoodnight.FishLogger \
  2>&1 | grep -q '"status": "ok"' && break; sleep 2; done                       # WDA launch (NOT simctl)
sleep 3; "$MCLI" apps foreground --device $DEV | grep -o '"packageName": *"[^"]*"'  # confirm foreground
```

A `packageName` of `com.saygoodnight.FishLogger` means you're good. If it shows
`com.apple.springboard`, the app is on the home screen / background — re‑run the
SpringBoard restart + WDA launch.

If WDA itself is wedged (timeouts on every call), reinstall the runner:
```bash
"$MCLI" agent install --device $DEV
```

**Last resort:** ask the user to restart the Simulator app. A corrupted
CoreSimulator state fixed nothing‑else‑worked situations more than once; SpringBoard
restart + agent reinstall handles the rest.

---

## Gotchas (the time‑sinks)

### 1. Text‑field focus is unreliable — verify every typed value
This caused the most lost time. Tapping a `TextField` does **not** reliably move
keyboard focus to it. Symptoms seen:
- Typed a weight `2.7`; it landed in the **WHO** field → `"Sarahe2.7"`.
- After a species picker closed, focus stayed on WHO; typing leaked there → `"Samms0.5"`.

Rules that work:
- **Dismiss the keyboard before switching fields** (tap **Done** / **return**, or a
  non‑editable element), **then** tap the target field, **then** type.
- After clearing a field with its **✕ (`xmark.circle.fill`)** button, focus may not
  remain — **tap the field again** before typing.
- **Always re‑list and check the field's `value`** after typing. Never assume it
  landed where you aimed.
- **Decimal‑pad stray digit:** typing `3.8` repeatedly saved as `3.83` (and `2.7`→
  `2.73`, `0.6`→`0.61`). This is a mobile‑mcp/decimal‑keyboard artifact, **not an app
  bug** — the app stores exactly what the field holds. If exact numbers matter, read
  back the field `value` or the JSON export; don't trust the keystrokes.
- A multiline `TextEditor` (the NOTES field) can **trap the keyboard** and cover the
  primary button (it blocked "Start fishing" once). Tap the map / a non‑editable
  element to dismiss; outside‑taps on the scroll area were unreliable.

### 2. The tab bar overlaps bottom content
The bottom tab bar sits at ~`y:795`. Any scroll‑content button that renders below
~`y:790` (lower debug "send live phrase" buttons, `Add catch`, `Log this catch`) is
either off‑screen or **behind the tab bar** — a tap there hits the **tab bar** and
navigates to another tab instead. Once I tapped "log_catch" and landed on the Spots
tab. **Scroll the content up first** so the target clears the tab‑bar zone:
```
mobile_swipe_on_screen  direction:up  x:200 y:400 distance:300
```
then re‑list for fresh coordinates.

### 3. Coordinates go stale as the screen mutates
The HEARD feed grows ~20px per tool call; adding a catch inserts a row; keyboards
shift the layout. Coordinates from an earlier `list_elements` call become wrong.
**Re‑list immediately before each tap** on any dynamic screen. Don't batch taps off
one listing.

### 4. Swipe‑to‑delete is NOT a thing here
Swiping left on a session row **opened the session** (treated as a tap), it did not
reveal a delete affordance. Deletion is: open the item → **More** (top‑right) →
**Delete session** → confirm in the alert. Don't assume standard iOS list gestures.

### 5. GPS / "Couldn't get location"
The New Session / New Catch sheets often show "Waiting for GPS…" / "Couldn't get
location." Fix:
```bash
xcrun simctl location $DEV set 41.5012,-73.9826    # set BEFORE / while the sheet is open
```
then tap **Use GPS**; a map marker (`fish.fill`) appears and the primary button works.
Use **distinct** lat/lng for different sessions to create distinct auto‑clustered
spots (e.g. `41.5012,-73.9826` and `41.7658,-72.6734`). A stale "Couldn't get
location" label can linger even after the marker renders — **the marker is the real
signal**, not the text.

### 6. Permission dialogs are real elements
Fresh installs prompt for location ("Allow While Using App"). They appear in the
element list — tap the button like anything else.

### 7. Live‑model timing
After tapping a "send live phrase" debug button, the Realtime round‑trip
(model → tool call → result → spoken reply) takes a few seconds. **`sleep ~5`** in
Bash, then re‑list to read the HEARD feed entry and the assistant reply. Don't read
immediately.

---

## Verification recipes (better than eyeballing)

Reading what the app actually wrote beats trusting the UI.

**Read an export / the store from the app's data container:**
```bash
DATA=$(xcrun simctl get_app_container $DEV com.saygoodnight.FishLogger data)
ls -t "$DATA/tmp"/FishLogger-Export-*.json | head -1     # latest export (trigger via + → Export)
ls "$DATA/Library/Application Support"/default.store*     # the SwiftData store
```
Triggering **+ → Export data** in‑app writes a JSON to `tmp/` and opens a share
sheet; read the file directly and assert on it (this is how migration losslessness
was proven — machine‑diffing v1 vs v2 exports rather than reading the UI).

**Paste a secret instead of typing it** (e.g. the OpenAI key into the SecureField):
```bash
printf '%s' "$KEY" | xcrun simctl pbcopy $DEV    # then long-press → Paste in-app
```

**Check the unified log** (e.g. to confirm a SwiftData store did NOT get wiped):
```bash
xcrun simctl spawn $DEV log show --last 5m \
  --predicate 'subsystem == "com.saygoodnight.FishLogger"' | grep -iE "resetting|migrat|error"
```

**Stream stdout on launch:**
```bash
timeout 12 xcrun simctl launch --console-pty $DEV com.saygoodnight.FishLogger
```

---

## Install semantics (matters for migration tests)

- `xcrun simctl install` **over** an existing app = **upgrade**; **preserves** the
  data container (the store survives). Use this to test old‑data → new‑build
  migration. `terminate` first for a clean handoff.
- `xcrun simctl uninstall` **removes** the data container (clean slate). Use this to
  start a test from zero.
- To test a true migration: build the OLD branch in an **isolated git worktree** with
  its own `-derivedDataPath`, install it, create data, then `simctl install` the NEW
  build over it (no uninstall) and verify.

---

## What FishLogger gives you for testing

> **The in‑app assistant debug harness was REMOVED** (it was shipping in Debug
> builds onto the physical device). There are no longer `debugConnectTextOnly`,
> `dbg_*` "send live phrase", or "Simulate tool calls" buttons in `AssistantPanel`.
> If you need that harness again to drive the live model from the sim, re‑add it
> **gated on `#if targetEnvironment(simulator)`** (not `#if DEBUG`) so it can never
> reach a device build, and wire it back to `AssistantService` / `RealtimeClient`.
> See git history (the assistant single‑round / required‑data work) for the exact
> removed code.

How to test the assistant **now**:
- **Tool dispatch + required‑data enforcement:** covered by `AssistantToolDispatchTests`
  (unit tests) — the authoritative check that catches/bites are rejected without a
  complete setup + species + angler. Run those, don't eyeball the UI.
- **Live model behavior (asks follow‑ups, snark, tool calls):** needs a real spoken
  turn on a **device** (the sim mic hears the Mac's room), or a temporarily re‑added
  simulator‑only harness as above.

- Many controls have **accessibility identifiers** — prefer matching on `identifier`
  in the element list over guessing coordinates.

> Tip: when adding new UI you'll want to test, give it an `accessibilityIdentifier`.
> It turns a fragile coordinate tap into a stable lookup.
