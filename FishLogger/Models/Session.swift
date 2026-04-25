import Foundation
import CoreLocation
import SwiftData

@Model
final class Session {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var latitude: Double
    var longitude: Double
    var notes: String = ""

    var spot: Spot?

    @Relationship(deleteRule: .cascade, inverse: \Catch.session)
    var catches: [Catch] = []

    // MARK: Conditions (populated by ConditionsBackfillService)

    var airTempC: Double?
    var humidity: Double?
    var cloudCoverage: Double?
    var conditionSymbol: String?
    var conditionCode: String?

    var windSpeedKmh: Double?
    var windGustKmh: Double?
    var windDirectionDegrees: Double?

    var pressureMb: Double?
    var pressureTrendRaw: String?
    var pressureTrend6hMb: Double?

    var precipIntensityMmh: Double?
    var precipProbability: Double?

    var sunriseAt: Date?
    var sunsetAt: Date?
    var moonPhase: Double?
    var moonIllumination: Double?

    var solunarMajor1Start: Date?
    var solunarMajor1End: Date?
    var solunarMajor2Start: Date?
    var solunarMajor2End: Date?
    var solunarMinor1Start: Date?
    var solunarMinor1End: Date?
    var solunarMinor2Start: Date?
    var solunarMinor2End: Date?

    var conditionsFetchedAt: Date?
    var conditionsFetchAttemptAt: Date?
    var conditionsFetchFailureCount: Int = 0
    var conditionsSchemaVersion: Int = 0

    init(
        startedAt: Date = .now,
        endedAt: Date? = nil,
        latitude: Double,
        longitude: Double,
        notes: String = "",
        spot: Spot? = nil
    ) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.spot = spot
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isOngoing: Bool { endedAt == nil }

    /// Effective end — present time while ongoing, persisted end otherwise.
    var effectiveEnd: Date { endedAt ?? .now }

    var duration: TimeInterval { effectiveEnd.timeIntervalSince(startedAt) }

    var pressureTrend: PressureTrend? {
        pressureTrendRaw.flatMap(PressureTrend.init(rawValue:))
    }

    var solunarMajors: [DateInterval] {
        [
            interval(solunarMajor1Start, solunarMajor1End),
            interval(solunarMajor2Start, solunarMajor2End)
        ].compactMap { $0 }
    }

    var solunarMinors: [DateInterval] {
        [
            interval(solunarMinor1Start, solunarMinor1End),
            interval(solunarMinor2Start, solunarMinor2End)
        ].compactMap { $0 }
    }

    private func interval(_ start: Date?, _ end: Date?) -> DateInterval? {
        guard let start, let end, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
