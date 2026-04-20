import Foundation
import CoreLocation
import SwiftData
import Observation
import OSLog
import WeatherKit

/// Populates the conditions fields on `Catch` by querying WeatherKit (historical
/// hourly) and computing solunar locally. Runs once per app launch from
/// `RootView.task`. Failures increment a counter and retry next launch.
@MainActor
@Observable
final class ConditionsBackfillService {
    static let shared = ConditionsBackfillService()

    private let log = Logger(subsystem: "com.saygoodnight.FishLogger", category: "ConditionsBackfill")
    private var didRunThisSession = false

    /// Gap between successive WeatherKit calls. Single-user scale is tiny vs.
    /// the 500k/mo entitlement cap, but keep a breather so a large first-run
    /// backfill isn't a tight loop.
    private let callSpacing: UInt64 = 150_000_000 // 150 ms

    /// Don't retry a failed catch sooner than this after the last attempt.
    private let retryCooldown: TimeInterval = 6 * 3600

    /// Bail out on a catch with this many prior failures — it's probably outside
    /// WeatherKit's historical window or the location is bad.
    private let maxFailures = 5

    /// Flush the SwiftData context every N processed catches so partial progress
    /// survives an app kill during a big first-run backfill.
    private let saveEvery = 5

    func backfillPending(context: ModelContext, weather: WeatherService) async {
        guard !didRunThisSession else { return }
        didRunThisSession = true

        let candidates: [Catch]
        do {
            candidates = try fetchCandidates(context: context)
        } catch {
            log.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard !candidates.isEmpty else {
            log.debug("No catches need conditions backfill.")
            return
        }

        log.info("Backfilling conditions for \(candidates.count, privacy: .public) catches.")

        var processed = 0
        for entry in candidates {
            if Task.isCancelled { break }

            do {
                try await backfillOne(entry, weather: weather)
            } catch {
                entry.conditionsFetchFailureCount += 1
                entry.conditionsFetchAttemptAt = .now
                log.error("Catch \(entry.id.uuidString, privacy: .public) failed (\(entry.conditionsFetchFailureCount, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }

            processed += 1
            if processed.isMultiple(of: saveEvery) {
                try? context.save()
            }

            try? await Task.sleep(nanoseconds: callSpacing)
        }

        try? context.save()
        log.info("Backfill pass complete.")
    }

    /// Populate conditions for a single catch. Also used by the new-catch save
    /// path. Throws on WeatherKit / solunar failure; caller decides whether to
    /// bump the failure counter.
    func backfillOne(_ entry: Catch, weather: WeatherService) async throws {
        let location = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
        let snapshot = try await weather.historical(at: location, date: entry.timestamp)

        apply(hour: snapshot.atHour, window: snapshot.window, to: entry)

        let solunar = SolunarCalculator.compute(
            lat: entry.latitude,
            lon: entry.longitude,
            date: entry.timestamp
        )
        apply(solunar: solunar, to: entry)

        entry.conditionsFetchedAt = .now
        entry.conditionsFetchAttemptAt = .now
        entry.conditionsFetchFailureCount = 0
    }

    // MARK: Private

    private func fetchCandidates(context: ModelContext) throws -> [Catch] {
        let maxFailures = self.maxFailures
        var descriptor = FetchDescriptor<Catch>(
            predicate: #Predicate<Catch> {
                $0.conditionsFetchedAt == nil && $0.conditionsFetchFailureCount < maxFailures
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        let rows = try context.fetch(descriptor)
        // Retry cooldown — filter in Swift; SwiftData #Predicate date math is fiddly.
        let now = Date()
        return rows.filter { entry in
            guard let last = entry.conditionsFetchAttemptAt else { return true }
            return now.timeIntervalSince(last) >= retryCooldown
        }
    }

    private func apply(hour: HourWeather, window: [HourWeather], to entry: Catch) {
        entry.airTempC = hour.temperature.converted(to: .celsius).value
        entry.humidity = hour.humidity
        entry.cloudCoverage = hour.cloudCover
        entry.conditionSymbol = hour.symbolName
        entry.conditionCode = hour.condition.description

        entry.windSpeedKmh = hour.wind.speed.converted(to: .kilometersPerHour).value
        entry.windGustKmh = hour.wind.gust?.converted(to: .kilometersPerHour).value
        entry.windDirectionDegrees = hour.wind.direction.converted(to: .degrees).value

        entry.pressureMb = hour.pressure.converted(to: .millibars).value
        entry.pressureTrendRaw = PressureTrend(hour.pressureTrend).rawValue

        entry.precipIntensityMmh = hour.precipitationAmount.converted(to: .millimeters).value
        entry.precipProbability = hour.precipitationChance

        // 6h trend: pressure(t) − pressure(t−6h). Our window is only ±3h, so we
        // fall back to the earliest hour in the window if nothing at t−6h. UI
        // treats this as "recent" trend either way.
        if let earliest = window.min(by: { $0.date < $1.date }),
           earliest.date < hour.date {
            let later = hour.pressure.converted(to: .millibars).value
            let earlier = earliest.pressure.converted(to: .millibars).value
            entry.pressureTrend6hMb = later - earlier
        } else {
            entry.pressureTrend6hMb = nil
        }
    }

    private func apply(solunar: Solunar, to entry: Catch) {
        entry.sunriseAt = solunar.sunrise
        entry.sunsetAt = solunar.sunset
        entry.moonPhase = solunar.moonPhase
        entry.moonIllumination = solunar.moonIllumination

        let majors = solunar.majors
        entry.solunarMajor1Start = majors.indices.contains(0) ? majors[0].start : nil
        entry.solunarMajor1End   = majors.indices.contains(0) ? majors[0].end   : nil
        entry.solunarMajor2Start = majors.indices.contains(1) ? majors[1].start : nil
        entry.solunarMajor2End   = majors.indices.contains(1) ? majors[1].end   : nil

        let minors = solunar.minors
        entry.solunarMinor1Start = minors.indices.contains(0) ? minors[0].start : nil
        entry.solunarMinor1End   = minors.indices.contains(0) ? minors[0].end   : nil
        entry.solunarMinor2Start = minors.indices.contains(1) ? minors[1].start : nil
        entry.solunarMinor2End   = minors.indices.contains(1) ? minors[1].end   : nil
    }
}
