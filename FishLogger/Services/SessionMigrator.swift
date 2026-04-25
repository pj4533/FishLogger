import Foundation
import CoreLocation
import SwiftData
import OSLog

/// One-time migrator that groups legacy orphan catches (catches with no
/// parent Session) into synthetic Sessions. Runs at app launch. A UserDefaults
/// flag guards it so it only executes once per install.
///
/// Grouping: catches sorted by timestamp are split into a new session whenever
/// the gap to the previous catch exceeds `gapSeconds` OR the catch's location
/// is more than `radiusMeters` from the running group centroid. Handles
/// cross-midnight night sessions correctly (gap-based, not day-based).
///
/// Conditions data is NOT carried over — the existing ConditionsBackfillService
/// picks up the new sessions on next pass and re-fetches from WeatherKit.
enum SessionMigrator {
    private static let didRunKey = "FishLogger.SessionMigrator.didRun.v1"
    private static let gapSeconds: TimeInterval = 6 * 3600
    private static let radiusMeters: Double = 100
    private static let log = Logger(subsystem: "com.saygoodnight.FishLogger", category: "SessionMigrator")

    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        if UserDefaults.standard.bool(forKey: didRunKey) { return }

        let descriptor = FetchDescriptor<Catch>(sortBy: [SortDescriptor(\.timestamp)])
        let all: [Catch]
        do {
            all = try context.fetch(descriptor)
        } catch {
            log.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let orphans = all.filter { $0.session == nil }
        guard !orphans.isEmpty else {
            UserDefaults.standard.set(true, forKey: didRunKey)
            return
        }

        log.info("Grouping \(orphans.count, privacy: .public) orphan catches into sessions.")

        let groups = groupByTimeAndProximity(
            orphans,
            gapSeconds: gapSeconds,
            radiusMeters: radiusMeters
        )

        for group in groups {
            let avgLat = group.map(\.latitude).reduce(0, +) / Double(group.count)
            let avgLon = group.map(\.longitude).reduce(0, +) / Double(group.count)
            let start = group.first!.timestamp
            let end = group.last!.timestamp

            let session = Session(
                startedAt: start,
                endedAt: end,
                latitude: avgLat,
                longitude: avgLon
            )
            context.insert(session)
            _ = SpotClusteringService.assignSpot(for: session, in: context)
            for c in group { c.session = session }
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: didRunKey)
            log.info("Created \(groups.count, privacy: .public) sessions from orphan catches.")
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Exposed for tests. Input is assumed sorted by timestamp ascending.
    static func groupByTimeAndProximity(
        _ catches: [Catch],
        gapSeconds: TimeInterval,
        radiusMeters: Double
    ) -> [[Catch]] {
        guard !catches.isEmpty else { return [] }

        var groups: [[Catch]] = []
        var current: [Catch] = []
        var centroid: CLLocation?

        for c in catches {
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)

            let shouldSplit: Bool
            if let last = current.last {
                let timeGap = c.timestamp.timeIntervalSince(last.timestamp)
                let distance = centroid.map { loc.distance(from: $0) } ?? 0
                shouldSplit = timeGap > gapSeconds || distance > radiusMeters
            } else {
                shouldSplit = false
            }

            if shouldSplit {
                groups.append(current)
                current = [c]
                centroid = loc
            } else {
                current.append(c)
                centroid = centroid.map { existing in
                    let n = Double(current.count)
                    let lat = (existing.coordinate.latitude * (n - 1) + c.latitude) / n
                    let lon = (existing.coordinate.longitude * (n - 1) + c.longitude) / n
                    return CLLocation(latitude: lat, longitude: lon)
                } ?? loc
            }
        }

        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
