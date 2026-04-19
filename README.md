# FishLogger

A cozy fishing diary for iOS. Log every catch at your pond — photos, videos,
GPS, weight, bait, rod, species, who reeled it in — and browse it back as a
personal field notebook.

Built for a specific property pond in the Hudson Valley, but the shape of
the app works anywhere with fish. The aesthetic is pastel-paper / wooden-stake
map pin / naturalist-journal — think *Stardew Valley* fish menu married to a
leather-bound nature guide, not a sports tracker.

| Platform | iOS 26+ |
|---|---|
| Language | Swift 5 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| UI | SwiftUI + MapKit + AVKit |
| Storage | SwiftData (local-only; no iCloud) |
| Testing | Swift Testing |

## Features

- **Four tabs** — Diary, Spots, Species checkoff, Leaderboard.
- **Voice-free entry that still feels fast.** Single-scroll form with photo
  picker, autocomplete dropdowns, segmented guessed/measured toggle, inline
  map preview. Fields auto-fill from photo/video EXIF (capture time + GPS);
  you can override any of them.
- **Spot clustering** — new catches within 100 m of an existing spot attach
  automatically and update the centroid. Outside the radius → new spot.
  Manual spots participate identically.
- **Species checkoff** organised by spot. Each species has scientific name,
  description, and stats: biggest catch, favourite bait, top angler, most
  active hour, best month.
- **Leaderboard** with a Species / Anglers toggle. Species mode ranks your
  per-species top 5. Anglers mode ranks each angler's top 5 across all
  species. Guessed weights show struck-through next to measured.
- **Video support end-to-end** — pick videos from the library, in-app
  playback via AVKit `VideoPlayer`, and a scrubber-based frame picker for
  choosing the exact still used as the diary thumbnail.
- **Autocomplete dropdowns** for bait, rod, and angler name. Tap to see
  everyone you've already logged, type to narrow with highlighted matches,
  tap a row to fill.
- **Cozy visual system** — asset-catalogue palette (paper / moss / sunset
  / bark) with dark-mode variants, SF Rounded for UI voice, New York serif
  italic for scientific names, torn-paper hero edges, wooden-stake map
  annotations.

## Project layout

```
FishLogger/
  FishLoggerApp.swift         entry point — sets up ModelContainer + seeder
  RootView.swift              4-tab shell
  Models/                     @Model types: Catch, Species, Spot, MediaAsset
  Views/
    Diary/                    catch list, detail, add-sheet, thumbnail picker
    Spots/                    map + spot detail
    Species/                  checkoff list + detail stats
    Leaderboard/              species/angler podiums
  Services/                   LocationService, MediaStore, AutocompleteService,
                              SpotClusteringService, SpeciesSeeder,
                              PhotoMetadata (image + video EXIF)
                              Dictation/ — reserved for future cloud-LLM parsing
  Components/                 CozyCard, WeightBadge, SpeciesTag, FishIcon,
                              AutocompleteField, MediaCarousel, VideoPlayerInline,
                              VideoThumbnailView, WoodenStake, SourceBadge
  Style/                      Font+Cozy.swift (colors come from Asset Catalog)
  Resources/                  Species.json — seeded species list
  Assets.xcassets/            palette color sets + accent/app icon
```

The project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup`, so new files
in `FishLogger/` are auto-added to the target — no pbxproj edits required.

## Build & run

Requires Xcode with an iOS 26.2 simulator.

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

Tests cover `SpotClusteringService`, `AutocompleteService`, `SpeciesSeeder`,
and the ISO 6709 location-string parser used for video EXIF.

## Customising

- **Species list:** edit `FishLogger/Resources/Species.json`. The seeder is
  idempotent — entries whose `commonName` already exists are skipped, so you
  can add species over time by appending to the file.
- **Spot-clustering radius:** `SpotClusteringService.defaultRadiusMeters`
  (default `100`).
- **Palette:** tweak the color sets under `Assets.xcassets/` — both light
  and dark variants are included. Xcode auto-generates matching
  `Color.<name>` symbols.

## Dictation roadmap

The app is manual-entry only today, but the scaffold for voice entry is in
place:

- `DictationParseResult` — the struct any parser fills in.
- `CatchParser` protocol — plug-in point for an OpenAI / Anthropic / on-device
  parser.
- `CatchFormState.apply(_:)` — merges non-nil parsed fields into the form so
  both flows share the same save path.
- A reserved mic slot in the add-catch toolbar (currently disabled).

Nothing is wired to a network.

## Permissions

Declared in the target's `INFOPLIST_KEY_*` build settings:

- `NSLocationWhenInUseUsageDescription`
- `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription`
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription` (reserved for future dictation)

## License

No license yet — all rights reserved. Add one if you want to invite
contributions.
