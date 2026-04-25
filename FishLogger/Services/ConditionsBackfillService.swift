import Foundation
import CoreLocation
import SwiftData
import Observation
import OSLog
import WeatherKit

/// Populates the conditions fields on `Session` by querying WeatherKit
/// (historical hourly) and computing solunar locally. Runs once per app launch
/// from `RootView.task`. Failures increment a counter and retry next launch.
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

    /// Don't retry a failed session sooner than this after the last attempt.
    private let retryCooldown: TimeInterval = 6 * 3600

    /// Bail out on a session with this many prior failures — it's probably
    /// outside WeatherKit's historical window or the location is bad.
    private let maxFailures = 5

    /// Flush the SwiftData context every N processed sessions so partial
    /// progress survives an app kill during a big first-run backfill.
    private let saveEvery = 5

    func backfillPending(context: ModelContext, weather: WeatherService) async {
        guard !didRunThisSession else { return }
        didRunThisSession = true

        let candidates: [Session]
        do {
            candidates = try fetchCandidates(context: context)
        } catch {
            log.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard !candidates.isEmpty else {
            log.debug("No sessions need conditions backfill.")
            return
        }

        log.info("Backfilling conditions for \(candidates.count, privacy: .public) sessions.")

        var processed = 0
        for session in candidates {
            if Task.isCancelled { break }

            do {
                try await backfillOne(session, weather: weather)
            } catch {
                session.conditionsFetchFailureCount += 1
                session.conditionsFetchAttemptAt = .now
                log.error("Session \(session.id.uuidString, privacy: .public) failed (\(session.conditionsFetchFailureCount, privacy: .public)): \(error.localizedDescription, privacy: .public)")
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

    /// Populate conditions for a single session. Also used by the new-session
    /// save path. Throws on WeatherKit / solunar failure; caller decides
    /// whether to bump the failure counter.
    func backfillOne(_ session: Session, weather: WeatherService) async throws {
        let location = CLLocation(latitude: session.latitude, longitude: session.longitude)
        let snapshot = try await weather.historical(at: location, date: session.startedAt)

        apply(hour: snapshot.atHour, window: snapshot.window, to: session)

        let solunar = SolunarCalculator.compute(
            lat: session.latitude,
            lon: session.longitude,
            date: session.startedAt
        )
        apply(solunar: solunar, to: session)

        session.conditionsFetchedAt = .now
        session.conditionsFetchAttemptAt = .now
        session.conditionsFetchFailureCount = 0
    }

    /// Clears the fetched timestamp so the next backfill pass re-fetches.
    /// Used by Session edit UI when startedAt or location changes materially.
    func markStale(_ session: Session) {
        session.conditionsFetchedAt = nil
        session.conditionsFetchFailureCount = 0
    }

    // MARK: Private

    private func fetchCandidates(context: ModelContext) throws -> [Session] {
        let maxFailures = self.maxFailures
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> {
                $0.conditionsFetchedAt == nil && $0.conditionsFetchFailureCount < maxFailures
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        let rows = try context.fetch(descriptor)
        // Retry cooldown — filter in Swift; SwiftData #Predicate date math is fiddly.
        let now = Date()
        return rows.filter { session in
            guard let last = session.conditionsFetchAttemptAt else { return true }
            return now.timeIntervalSince(last) >= retryCooldown
        }
    }

    private func apply(hour: HourWeather, window: [HourWeather], to session: Session) {
        session.airTempC = hour.temperature.converted(to: .celsius).value
        session.humidity = hour.humidity
        session.cloudCoverage = hour.cloudCover
        session.conditionSymbol = hour.symbolName
        session.conditionCode = hour.condition.description

        session.windSpeedKmh = hour.wind.speed.converted(to: .kilometersPerHour).value
        session.windGustKmh = hour.wind.gust?.converted(to: .kilometersPerHour).value
        session.windDirectionDegrees = hour.wind.direction.converted(to: .degrees).value

        session.pressureMb = hour.pressure.converted(to: .millibars).value
        session.pressureTrendRaw = PressureTrend(hour.pressureTrend).rawValue

        session.precipIntensityMmh = hour.precipitationAmount.converted(to: .millimeters).value
        session.precipProbability = hour.precipitationChance

        // 6h trend: pressure(t) − pressure(t−6h). Our window is only ±3h, so we
        // fall back to the earliest hour in the window if nothing at t−6h. UI
        // treats this as "recent" trend either way.
        if let earliest = window.min(by: { $0.date < $1.date }),
           earliest.date < hour.date {
            let later = hour.pressure.converted(to: .millibars).value
            let earlier = earliest.pressure.converted(to: .millibars).value
            session.pressureTrend6hMb = later - earlier
        } else {
            session.pressureTrend6hMb = nil
        }
    }

    private func apply(solunar: Solunar, to session: Session) {
        session.sunriseAt = solunar.sunrise
        session.sunsetAt = solunar.sunset
        session.moonPhase = solunar.moonPhase
        session.moonIllumination = solunar.moonIllumination

        let majors = solunar.majors
        session.solunarMajor1Start = majors.indices.contains(0) ? majors[0].start : nil
        session.solunarMajor1End   = majors.indices.contains(0) ? majors[0].end   : nil
        session.solunarMajor2Start = majors.indices.contains(1) ? majors[1].start : nil
        session.solunarMajor2End   = majors.indices.contains(1) ? majors[1].end   : nil

        let minors = solunar.minors
        session.solunarMinor1Start = minors.indices.contains(0) ? minors[0].start : nil
        session.solunarMinor1End   = minors.indices.contains(0) ? minors[0].end   : nil
        session.solunarMinor2Start = minors.indices.contains(1) ? minors[1].start : nil
        session.solunarMinor2End   = minors.indices.contains(1) ? minors[1].end   : nil
    }
}
