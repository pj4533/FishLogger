# FishLogger

A cozy fishing diary for iOS. Log every outing at your pond — sessions, catches,
the *setup* in the water, bites that didn't hook up, photos, videos, GPS, weather,
who reeled it in — and browse it back as a personal field notebook.

Built for a specific property pond in the Hudson Valley, but the shape of
the app works anywhere with fish. The aesthetic is pastel-paper / wooden-stake
map pin / naturalist-journal — think *Stardew Valley* fish menu married to a
leather-bound nature guide, not a sports tracker.

| Platform | iOS 26.2+ |
|---|---|
| Language | Swift (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| UI | SwiftUI + MapKit + AVKit |
| Storage | SwiftData (local-only; no iCloud) |
| Weather | Apple WeatherKit + a local solunar calculator |
| Voice | OpenAI Realtime API (native `URLSessionWebSocketTask`, no SDK) |
| Testing | Swift Testing |

## Features

Five tabs: **Sessions · Spots · Conditions · Species · Leaderboard.**

- **Sessions, not just catches.** A session is an outing — start time, end time,
  GPS spot, and a snapshot of the weather/solunar conditions at the time. Catches
  belong to a session. A session with *zero* catches is still a recorded session
  (the conditions are the data).
- **The hands-free "fishing buddy."** On an ongoing session you can talk to a voice
  assistant (OpenAI Realtime + tool calling): "switching to a frog", "big blowup,
  missed him", "landed a three-pound largemouth", "Dave got one". It updates the
  session in real time — setup, sub-spot, bites, catches, who caught it — and answers
  with a short, dry, in-character confirmation. Requires your own OpenAI key (see
  below). Full design in [`docs/voice-assistant.md`](docs/voice-assistant.md).
- **Negative-signal & coverage capture.** Beyond catches, the app records what was in
  the water when *nothing* bit, and the bites/blowups/follows that didn't land. You
  narrate only the state-changes and events; at session end the app **derives** the
  no-catch "coverage segments" (which setup/sub-spot was fished, for how long, with
  what result) from the event timeline. Great for pattern-finding.
- **Current setup model.** A persistent rod/reel/line/lure/color/technique "what I'm
  throwing now" that gets snapshotted onto every catch and bite — so a catch always
  carries the full context, not just the rod.
- **Conditions tab.** Current readings (pressure + trend, wind, air temp, rain),
  solunar "fishing windows" for today, a "best time to fish in the next 7 days"
  recommendation, and a 10-day forecast with moon phase and major/minor solunar
  windows. Powered by Apple WeatherKit; solunar computed locally.
- **Manual entry that still feels fast.** Single-scroll catch form with photo/video
  picker, autocomplete dropdowns (bait / rod / angler), segmented guessed/measured
  toggle, inline map preview. Fields auto-fill from photo/video EXIF (capture time +
  GPS); override any of them. The manual path and the voice path share the same save
  logic.
- **Spot clustering.** New catches within ~100 m of an existing spot attach
  automatically and update the centroid; outside the radius → a new spot. Manual
  spots participate identically.
- **Species checkoff** organised by spot, each with scientific name, description, and
  stats: biggest catch, favourite bait, top angler, most active hour, best month.
- **Leaderboard** with a Species / Anglers toggle. Species mode ranks per-species top
  catches; Anglers mode ranks each angler's best (using the `caughtBy` data).
- **JSON export.** One tap exports the whole store — sessions with their full
  conditions block, events, derived coverage segments, and nested catches (each with
  its setup snapshot) — as analysis-friendly JSON (schema v2).
- **Video support end-to-end** — pick videos, in-app `VideoPlayer` playback, and a
  scrubber-based frame picker for the diary thumbnail.
- **Cozy visual system** — asset-catalogue palette (paper / moss / sunset / bark)
  with dark-mode variants, SF Rounded for UI, New York serif italic for scientific
  names, torn-paper hero edges, wooden-stake map annotations.

## Project layout

```
FishLogger/
  FishLoggerApp.swift     entry point — ModelContainer + species seed + session migrate
  RootView.swift          5-tab shell
  Models/                 @Model: Session, Catch, SessionEvent, Spot, Species,
                          MediaAsset, MediaKind  +  Setup (Codable value type)
  Views/
    Sessions/             session list, detail, new-session sheet, add-catch sheet
    Catches/              catch detail, form state, thumbnail picker
    Conditions/           conditions tab, current/forecast/solunar cards
    Spots/                map + spot detail
    Species/              checkoff list + detail stats
    Leaderboard/          species/angler podiums
    Assistant/            AssistantPanel — the in-session voice UI
    Settings/             OpenAI API key entry
  Services/
    Assistant/            RealtimeClient, RealtimeAudioEngine, AssistantService,
                          AssistantTools, AssistantInstructions, KeychainManager
    SessionEventLogger    single mutation point for session state + event log
    CoverageDerivation    pure no-catch/coverage derivation from the event timeline
    ExportService         JSON export (schema v2)
    WeatherService        Apple WeatherKit wrapper
    ConditionsScorer / ConditionsBackfillService   fishing-window scoring + backfill
    Solunar/              SolunarCalculator, SunCalc
    LocationService, MediaStore, AutocompleteService, PhotoMetadata,
    SpotClusteringService, FishingAreaClusterer, SpeciesSeeder, SessionMigrator
  Components/             CozyCard, WeightBadge, SpeciesTag, FishIcon, AutocompleteField,
                          MediaCarousel, VideoPlayerInline, ShareSheet, WoodenStake, …
  Style/                  Font+Cozy.swift (colors come from the Asset Catalog)
  Resources/              Species.json — seeded species list
  Assets.xcassets/        palette color sets + accent/app icon
```

New files under `FishLogger/` are auto-added to the target
(`PBXFileSystemSynchronizedRootGroup`) — no pbxproj edits required to add a file.

> **Note:** the app's Debug config sets `SWIFT_COMPILATION_MODE = wholemodule` on
> purpose, to work around a SwiftData `@Model` batch-mode compiler bug. Don't remove
> it — see [`docs/voice-assistant.md`](docs/voice-assistant.md) §4.

## Build & run

Requires Xcode with an iOS 26.2 simulator. **Always pass `-destination`** (this is an
iOS-only app; a bare `xcodebuild` defaults to macOS and fails on provisioning).

```bash
xcodebuild \
  -project FishLogger.xcodeproj \
  -scheme FishLogger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -configuration Debug build
```

### Run unit tests

```bash
xcodebuild test \
  -project FishLogger.xcodeproj \
  -scheme FishLogger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:FishLoggerTests
```

Tests cover `SpotClusteringService`, `AutocompleteService`, `SpeciesSeeder`, the
location-string parser, the solunar calculator, `CoverageDerivation`, and the
assistant's tool dispatch + schema.

For UI / end-to-end testing in the Simulator with **mobile-mcp**, see
[`docs/mobile-mcp-testing.md`](docs/mobile-mcp-testing.md) — it documents the reliable
startup recipe and the simulator gotchas.

## Voice assistant setup

The assistant talks to the **OpenAI Realtime API** and needs your own
**pay-as-you-go OpenAI Platform key** (an `sk-…` key). A ChatGPT Plus/Pro or Codex
subscription *cannot* pay for the audio API — it must be a Platform key with billing.

- Add the key in-app: **Settings** (gear in the Sessions toolbar). It's stored in the
  device keychain and sent directly from the device to OpenAI.
- Model: `gpt-realtime-mini` (in `RealtimeClient.swift`). The transport is a native
  `URLSessionWebSocketTask` speaking the GA Realtime schema — no third-party SDK.
- For local testing, a key can live in a gitignored `.env.local` at the repo root.

**Security note:** this single-user personal build connects directly with the standing
key from the keychain. A public build would mint an ephemeral key from a small backend
and pass that instead (only the token source changes). Details in
[`docs/voice-assistant.md`](docs/voice-assistant.md) §4.

## Data & migration

Storage is local SwiftData (no iCloud). Schema changes are kept **additive** so an
existing store lightweight-migrates in place; `FishLoggerApp.swift` falls back to
wiping the store only if the container truly can't open. The old-data → new-build
migration is verified (see [`docs/voice-assistant.md`](docs/voice-assistant.md) §8),
so updating over an existing install keeps your catches.

## Customising

- **Species list:** edit `FishLogger/Resources/Species.json`. The seeder is idempotent
  (entries whose `commonName` already exists are skipped), so append over time.
- **Spot-clustering radius:** `SpotClusteringService.defaultRadiusMeters` (default `100`).
- **Assistant voice/behavior:** the `PERSONALITY` block and tool rules in
  `AssistantInstructions.swift`. Keep the "banned patterns" list or the voice drifts
  back to cheese.
- **Palette:** tweak the color sets under `Assets.xcassets/` — light and dark variants
  included; Xcode auto-generates matching `Color.<name>` symbols.

## Permissions

Declared in the target's `INFOPLIST_KEY_*` build settings:

- `NSLocationWhenInUseUsageDescription` — tags catches with GPS.
- `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription`
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription` — the hands-free voice assistant.

## License

No license yet — all rights reserved. Add one if you want to invite contributions.
