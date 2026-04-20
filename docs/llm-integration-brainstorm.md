# LLM Integration + Deeper Pro+ — Brainstorm Record

*Session date: 2026-04-20*

This document captures a brainstorming session on integrating a frontier
LLM (OpenAI / Anthropic class) into FishLogger, adding weather data, and
integrating the Deeper Pro+ 2 castable sonar. It records not just the
direction we chose, but also the alternatives we considered and rejected,
so that future sessions have the full reasoning.

No implementation plan lives here — this is the *why*, not the *how*.

---

## Starting premise

FishLogger is a single-user, local-only iOS fishing diary for a property
pond in the Hudson Valley. Current features: manual catch entry (photos,
videos, GPS, weight, bait, rod, species, angler), 4-tab shell
(Diary / Spots / Species / Leaderboard), auto-clustering of catches into
spots within 100 m, dictation scaffold in place but not wired to any
parser.

The user wanted to explore where a frontier LLM adds real value, with
two specific threads:

1. A new **Conditions tab** powered by a weather API, with an LLM
   synthesizing a fishing report.
2. Integration of a **Deeper Pro+ 2** castable sonar (arriving the day
   of this session).

Ground rule for the session: research online, don't guess, don't build
yet.

---

## Weather API research

### What signals actually correlate with fishing success

Grounded in fisheries-biology sources, not folklore:

- **Water temperature** — strongest, species-specific thermal windows
  drive metabolism. Largemouth bass peak feeding 60–75°F.
- **Barometric pressure *trend*** (`.rising / .steady / .falling`), not
  absolute pressure. Falling pressure / pre-frontal windows correlate
  with feeding. Effect is likely indirect (fronts bring wind, cloud,
  rain, oxygen mixing) rather than fish sensing mbar directly.
- **Cloud cover / low light** — reduces predator disadvantage for prey,
  extends feeding windows into midday.
- **Wind** — surface chop oxygenates, disorients baitfish on windward
  shores.
- **Frontal passage timing** — pre-front hot, post-front 24–48h slow.
- **Sunrise/sunset (crepuscular periods)** — low-light feeding across
  most freshwater gamefish.
- **Moon phase / solunar** — folklore-adjacent. Weak freshwater
  evidence. Stoner 2004 called the evidence "inconsistent." Keep as a
  soft input, not a law.
- **Water clarity / turbidity after rain** — real, affects lure choice.
- **Dissolved oxygen** — critical in summer stratification, not in any
  weather API.

### APIs considered

| API | Free tier | Signals | Historical | iOS fit |
|---|---|---|---|---|
| **Apple WeatherKit** | 500k calls/mo free with Apple Dev membership | pressure + `pressureTrend`, hourly temp/wind/cloud/precip, UV, sunrise/sunset, `MoonPhase` enum. No solunar majors/minors. No water temp. | Back to **Aug 1 2021 only** | Best — native Swift `WeatherService` |
| Open-Meteo | Free non-commercial | Pressure, hourly forecast, UV, sunrise/sunset, moon phase via separate endpoint | **Back to 1940** | Plain HTTPS/JSON |
| Visual Crossing Timeline | 1,000 records/day free | Full hourly + moonphase (0–1) + moonrise/moonset | 50 years | JSON REST |
| Tomorrow.io | 500 calls/day free | 80 fields incl. pressure, UV | Limited on free tier | JSON REST |
| NOAA NWS (api.weather.gov) | Truly free | Hourly forecast, pressure in observations. No moon phase, no historical here (NCEI separate). | No via this API | US-only |
| OpenWeather One Call 3.0 | 1,000 calls/day free | Pressure, UV, moon phase daily | Paid tier only | JSON REST |

### Solunar tables

- **solunar.org** has a free JSON API but it's self-described as a
  "hobby" service with no uptime guarantee. Not production-safe.
- **Decision: compute client-side.** Majors/minors are deterministic
  from moonrise/moonset/lunar transit + sunrise/sunset. Use the
  `Timac/SunCalc` Swift package (MIT port of mourner/suncalc) and add
  the ~20 lines of majors/minors formula on top. No network, no rate
  limit, offline-capable.

### Weather API decision

**Apple WeatherKit alone.** Reasoning:

- Catches in the app only go back a week, so the Aug-2021 historical
  floor is irrelevant. Back-filling all existing catches on first
  launch works within WeatherKit's window.
- WeatherKit natively exposes `pressureTrend` — no derivation needed.
- 500k calls/month is effectively unlimited at single-user scale.
- Native Swift, no key management, standard Apple attribution UI.
- `DayWeather.sun` gives civil/nautical twilight, `DayWeather.moon`
  gives phase + moonrise/moonset — all the astronomical inputs needed
  for the local SunCalc solunar computation.

### Weather APIs rejected

- **Open-Meteo / Visual Crossing as historical fallback** — would only
  have mattered for pre-Aug-2021 catches. User confirmed they don't
  have any. Removed from plan.
- **OpenWeather** — historical paywalled, no advantage over WeatherKit.
- **Tomorrow.io** — free tier too restrictive, no compelling advantage.
- **NOAA NWS** — no historical from the forecast API, and needs custom
  observation-station lookup for surface pressure. More work, less data.
- **solunar.org** — unreliable hobby service; local compute is cleaner.

---

## LLM use-case research

### Tiered assessment

**Tier 1 — actually worth building (ranked):**

1. **Dictation → structured catch entry.** Highest leverage; anglers
   have wet hands. Whisper transcript + structured-output prompt nails
   this. Scaffold already in place (`DictationParseResult`,
   `CatchParser`, `CatchFormState.apply(_:)`).
2. **Natural-language diary search.** *"Show me every bass over 3 lb
   caught in the rain."* Translate query to a SwiftData `#Predicate`.
   Data is small, local, structured — perfect fit.
3. **Pattern-finding across catch history.** Once 100+ catches exist,
   ask the LLM to surface correlations (pressure × species × time of
   day × spot). Becomes the payoff that justifies the logging.
4. **Per-spot Conditions tab synthesis.** Grounded in the user's own
   pond and catch history — not generic solunar content-farm prose.
   Structured output (`window`, `why`, `baits`, `spots`, `confidence`),
   evidence-linked to past catches.

**Tier 2 — build later:**

5. **Pre-trip brief push notification.** Same engine as #4, scheduled.
6. **Sonar screenshot interpretation (vision LLM).** Ad-hoc "what am I
   looking at" button on a sonar screenshot attached to a catch or
   structure marker. Start narrow; don't build a pipeline.
7. **Photo species ID via CoreML** (not LLM). 11 freshwater species
   fine-tunable on a few hundred labeled photos to 95%+. Reserve the
   vision LLM only for edge cases (sunfish hybrids).

**Tier 3 — skip:**

8. AI-written trip debriefs / seasonal summaries — cute once, ignored
   forever. At most, a share-sheet export.
9. AI photo captions — gimmick.
10. Weight estimation from photo — unreliable without reference object.
    Species-specific length-to-weight formulas beat it.
11. Species-lore Q&A — the user already has Claude/ChatGPT on their
    phone. Don't rebuild it in-app.

### The slop pattern to avoid

Features that generate prose from public weather data read like
content-farm output. Features grounded in the user's own catch history
feel magical. Build the latter. This is the key differentiator from
every "AI fishing report" website.

---

## Deeper Pro+ 2 research

### What the device captures and exports

- **Bathymetry.csv** (boat/bait-boat/shore modes only):
  `lat, lon, depth (m), timestamp (Unix ms), temperature (°C)` at
  ~15 pings/sec. WGS84.
- **Sonar.csv**: timestamp + echo intensity per depth bin (0–4096 for
  PRO+ 2 / CHIRP). The raw echogram.
- **Standard mode and Ice Fishing mode produce no exportable data.**
- **Not in any export:** bottom hardness, vegetation flags, fish arches
  / fish icons — these are Fish Deeper UI interpretations, not data.
- **No exportable bathymetry map tiles / overlay format** (no GeoTIFF,
  MBTiles, XYZ, KML). Raw points only — you rebuild the surface.
- **No public developer API / SDK / OAuth / Lakebook endpoints.** The
  only "developer" page Deeper publishes is an Android engineer job
  posting.

### The PRO+ 2 / CHIRP+ documented live protocol (key finding)

Deeper ships three near-identically-named models with very different
protocol stories:

| Model | Live protocol access |
|---|---|
| Original PRO+ (2016) | None. No docs, no public RE, zero prior work. |
| **PRO+ 2 / CHIRP+ / CHIRP+ 2** | **Official UDP NMEA0183 on port 10110.** |

For the PRO+ 2 (what the user is getting), Deeper publishes:

- Wi-Fi AP gateway: `192.168.10.1`
- UDP port: `10110`
- Enable: send `$DEEP230,1*38\r\n` from client → sonar
- Emit rate: 1 Hz
- Sentences: `$GPGSA`, `$GLGSA`, `$GAGSA`, `$GNRMC`, `$GNVTG`,
  `$GNGGA`, `$SDDBT` (depth), `$YXMTW` (water temp)
- Requires "Onshore" mode in Fish Deeper app + GPS fix
- No authentication

The echogram itself is NOT in the NMEA stream — that's 1 Hz
depth/temp/GPS only. Whether an undocumented UDP port carries the
echogram is an open question with zero public RE work in the entire
community (verified across GitHub, Hackaday, DEF CON, CCC, academic,
forums).

### Live stream vs CSV export — what each uniquely gives you

| Data | Live UDP (port 10110) | Post-session CSV |
|---|---|---|
| Depth | 1 Hz | ~15 Hz |
| Water temp | 1 Hz | ~15 Hz |
| GPS | 1 Hz, full NMEA | ~15 Hz |
| **Echogram (echo intensity arrays)** | ❌ | ✅ Sonar.csv |
| Fish arches / icons | ❌ | ❌ |
| Bottom hardness / vegetation | ❌ | ❌ |

**Live stream uniquely enables:** zero-friction catch enrichment at the
moment of logging (current depth/temp auto-filled), independence from
Fish Deeper's cloud, ambient/always-on capture, per-spot water-temp
history over time, real-time triggers, independence from the Fish
Deeper app's lifecycle.

**CSV uniquely provides:** the echogram itself, 15× higher sample
density on depth/temp/GPS, post-facto imports of pre-hub sessions.

### Host architectures considered

One avenue we explored in depth: standing up a continuous ingestion
hub on the user's Mac Studio with a Raspberry Pi at the pond.

**Proposed architecture (considered and rejected):**

- Edge: Python daemon on a Raspberry Pi 4/5 in a weatherproof case at
  the pond, joins Deeper AP on boot, sends enable packet, binds
  `UDP/10110`, buffers to local SQLite + raw `.pcap`, forwards deltas
  via MQTT over LTE/long-range Wi-Fi uplink.
- Home (Mac Studio): Mosquitto broker, Swift-NIO ingester service
  sharing types with the iOS app, SQLite (WAL) + DuckDB for analytics.
- Consumers: FishLogger iOS via MQTT/WebSocket, optional public web
  dashboard, LLM pipelines pulling CSV batches.
- Reference: SignalK server (Node) speaks NMEA0183-over-UDP and has
  mature plugins for marine telemetry.

**Hard constraints discovered:**

- **macOS removed USB Wi-Fi adapter support in Monterey.** Cannot
  dual-home the Mac Studio to home Wi-Fi + Deeper AP. Linux handles
  two wlans fine; Mac doesn't.
- **Deeper Wi-Fi range is ~100 m line-of-sight** (range extender to
  ~200 m). Pond is effectively not in Wi-Fi range of a house-bound
  Mac. Any hub approach requires an edge device at the pond.

**Edge options ranked (if we went this route):**

1. Raspberry Pi at the pond, LTE or long-range Wi-Fi back-haul — best.
2. iPhone as courier via a companion app — iOS background Wi-Fi
   switching is heavily restricted; realistically requires foregrounded.
3. Ubiquiti NanoBeam point-to-point — overkill for this data volume.

### Why the hub architecture was rejected

User's actual usage pattern:

- **Won't use the Deeper every trip.** It's castable — needs a separate
  rod, adds real overhead. Not the default every time they fish.
- **Water temp doesn't need to be continuous.** A stick thermometer,
  dipped occasionally, is plenty.
- The Deeper's value is two specific jobs, not always-on telemetry:
  1. Mapping the pond's bathymetry once (or once per season).
  2. Ad-hoc scouting for hiding spots, especially in deeper water.

Given that, the always-on hub is ~80% wasted infrastructure. The live
UDP stream's unique advantages (catch enrichment at save time, ambient
capture, water-temp history) require the user to be actively on the
water with the sonar running — which won't happen often enough to
justify the build.

### Reverse-engineering the echogram

**Considered and deferred.** No public RE work exists (verified across
GitHub, Hackaday, conference talks, academic papers, and the relevant
forums — closest adjacent projects like `scherererer/SonarPhony` and
`KennethTM/sonarlight` are different vendors). Budget would be
weeks of Wireshark + JADX-decompiling the Fish Deeper APK before any
ingester code.

For the user's actual need — scouting — the Fish Deeper app's live
echogram UI is already sufficient, and screenshots can be attached to
structure markers via the existing media pipeline. RE'ing the protocol
buys nothing meaningful given the usage pattern. Revisit only if the
project's needs change substantially.

### Legal / sustainability notes (for the record)

- DMCA §1201(f) explicitly permits RE for interoperability of a device
  you own, with no TPM circumvention. Personal-use RE is low-risk in
  the US. TOS violations are a contract matter, not criminal.
- Using the documented UDP NMEA interface is sustainable for years
  (marketed feature).
- Reverse-engineered echogram parsing would be brittle; plan to
  re-diff on firmware updates.

---

## The chosen direction

Scope matches the user's actual usage: **bathymetric map once, ad-hoc
scouting, no always-on telemetry**. No hub, no daemon, no Pi, no
reverse engineering. Just the iOS app, the CSV export flow, and
layered LLM features on top of WeatherKit + solunar + catch history +
bathymetry.

### What to build in FishLogger (Deeper side)

1. **Bathymetry CSV import + MapKit contour overlay.** Share-sheet
   extension accepts `Bathymetry.csv`. Ingests thousands of
   `(lat, lon, depth)` points into SwiftData. Renders depth contours
   on the Spots map as a MapKit overlay (triangulated or IDW grid,
   polylines at 2-ft intervals). Every catch gets a depth-at-location
   annotation via lookup into the ingested grid.
2. **Structure markers.** New SwiftData type separate from catch-
   clustered spots. Fields: location, depth, type (drop-off /
   submerged log / rock pile / weed bed / hole / channel), notes,
   optional sonar-screenshot attachment via the existing media
   pipeline. Distinct pin style on the map (not a wooden stake).
3. **Screenshot attachment for sonar returns.** Already supported by
   the media pipeline. Pure UX / onboarding work to document the
   workflow.

### What the LLM layer does

The bathymetry layer is what makes the Tier-1 LLM features concrete:

- **Conditions tab suggestions** become spatially specific ("with
  pressure falling + overcast, target the 8–12 ft break on the south
  shore — that profile matches your best pre-frontal bass history").
- **Pattern-finding** gets a real geometric axis: species × depth ×
  bottom-slope × time-of-day.
- **Pre-trip brief** can reference specific structure markers.

### Build order

1. **Conditions tab.** WeatherKit + SunCalc, pure data layer first, no
   LLM yet. Ships independently, earns its keep immediately.
2. **Bathymetry CSV import + contour overlay.** Unlocks spatial
   reasoning for everything that follows.
3. **Structure markers.** Small feature, high pond-specific value.
4. **LLM layer.** Conditions synthesis, pattern-finding, pre-trip
   briefs. Grounded in weather + solunar + catch history + depth.
5. **Dictation → structured entry.** Independent track, parallel to
   any of the above.

### Summary of what we're NOT doing

- No live UDP hub on Mac Studio.
- No Mosquitto broker, no Swift-NIO ingester.
- No Raspberry Pi at the pond.
- No reverse-engineering of the echogram protocol.
- No continuous water-temperature history from ambient sonar capture.
- No dual-homed Mac (macOS can't anyway).
- No iPhone-as-courier companion app.
- No historical weather API fallback (WeatherKit's Aug-2021 floor is
  sufficient).
- No external solunar API (compute locally with SunCalc).
- No LLM-powered photo species ID (use CoreML; reserve LLM for edge
  cases).
- No weight-from-photo estimation.
- No AI-written captions / trip summaries / lore Q&A.

---

## Sources

- [Apple WeatherKit docs](https://developer.apple.com/documentation/weatherkit)
- [Apple WeatherKit — PressureTrend](https://developer.apple.com/documentation/weatherkit/pressuretrend/allcases-swift.type.property)
- [Apple WeatherKit — MoonPhase](https://developer.apple.com/documentation/weatherkit/moonphase)
- [WeatherKit historical data limitation (Aug 2021)](https://developer.apple.com/forums/thread/737066)
- [Open-Meteo Historical Weather API](https://open-meteo.com/en/docs/historical-weather-api)
- [Visual Crossing pricing](https://www.visualcrossing.com/weather-data-editions/)
- [Tomorrow.io rate limits](https://support.tomorrow.io/hc/en-us/articles/20273728362644-Free-API-Plan-Rate-Limits)
- [NWS api.weather.gov FAQs](https://weather-gov.github.io/api/general-faqs)
- [Timac/SunCalc Swift package](https://github.com/Timac/SunCalc)
- [Stoner 2004 — Effects of environmental variables on fish feeding ecology](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.0022-1112.2004.00593.x)
- [VanderWeyst 2014 — Barometric pressure and yellow perch feeding](https://www.bemidjistate.edu/directory/wp-content/uploads/sites/16/2023/02/2014-VanderWeyst-D.-The-effect-of-barometric-pressure-on-feeding-activity-of-yellow-perch..pdf)
- [In-Fisherman — Largemouth Bass, Temperature & Thermoclines](https://www.in-fisherman.com/editorial/largemouth-bass-temperature-thermoclines/494247)
- [Active Angling NZ — The Barometric Pressure Myth](https://activeanglingnz.com/2019/10/13/the-barometric-pressure-myth/)
- [Solunar theory — Wikipedia](https://en.wikipedia.org/wiki/Solunar_theory)
- [Deeper support — NMEA0183 over UDP (CHIRP/PRO+ 2 only)](https://support.deeper.eu/284760-Extracting-NMEA0183-data-over-UDP-port-CHIRPCHIRP-20PRO-20-models-only)
- [Deeper support — Exporting raw sonar data](https://support.deeper.eu/899033-Exporting-raw-sonar-data)
- [Deeper support — Downloading raw bathymetric data](https://support.deeper.eu/756931-Downloading-raw-bathymetric-data)
- [Deeper support — Wi-Fi password](https://support.deeper.eu/551774-Deeper-PROPRO-WiFI-Password)
- [Blue Robotics forum — Deeper PRO sonar thread](https://discuss.bluerobotics.com/t/deeper-pro-sonar/725)
- [scherererer/SonarPhony (different vendor)](https://github.com/scherererer/SonarPhony)
- [KennethTM/sonarlight (Lowrance)](https://github.com/KennethTM/sonarlight)
- [SignalK project](https://signalk.org)
- [tkurki/signalk-mqtt-gw](https://github.com/tkurki/signalk-mqtt-gw)
- [Speedify KB — macOS dropped USB Wi-Fi support in Monterey](https://support.speedify.com/article/451-combine-2-wi-fi-mac)
- [Off the Scale — Deeper Pro+ range review](https://www.offthescaleangling.ie/tackle_reviews/deeper-pro-plus-review/)
- [Cornell LII — 17 USC §1201](https://www.law.cornell.edu/uscode/text/17/1201)
- [EFF Coders' Rights FAQ](https://www.eff.org/issues/coders/reverse-engineering-faq)
