import Foundation
import CoreLocation
import SwiftData

@Model
final class Catch {
    var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var weight: Double
    var isMeasured: Bool
    var baitUsed: String
    var rodUsed: String
    var caughtBy: String = ""
    var notes: String

    var species: Species?
    var spot: Spot?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.owner)
    var media: [MediaAsset] = []

    // MARK: Conditions (optional — populated by ConditionsBackfillService / save-time hook)

    // Weather core
    var airTempC: Double?
    var humidity: Double?            // 0–1
    var cloudCoverage: Double?       // 0–1
    var conditionSymbol: String?     // SF Symbol from WeatherCondition.symbolName
    var conditionCode: String?       // Raw stable key for future LLM grounding

    // Wind
    var windSpeedKmh: Double?
    var windGustKmh: Double?
    var windDirectionDegrees: Double?

    // Pressure — the top fishing signal
    var pressureMb: Double?
    var pressureTrendRaw: String?    // PressureTrend raw value
    var pressureTrend6hMb: Double?   // pressure(t) − pressure(t−6h); pre-frontal indicator

    // Precipitation
    var precipIntensityMmh: Double?
    var precipProbability: Double?

    // Sun / Moon
    var sunriseAt: Date?
    var sunsetAt: Date?
    var moonPhase: Double?           // 0–1; 0=new, 0.5=full
    var moonIllumination: Double?

    // Solunar majors/minors — discrete slots (≤2 each per day)
    var solunarMajor1Start: Date?
    var solunarMajor1End: Date?
    var solunarMajor2Start: Date?
    var solunarMajor2End: Date?
    var solunarMinor1Start: Date?
    var solunarMinor1End: Date?
    var solunarMinor2Start: Date?
    var solunarMinor2End: Date?

    // Backfill bookkeeping
    var conditionsFetchedAt: Date?         // non-nil ⇒ successful backfill
    var conditionsFetchAttemptAt: Date?
    var conditionsFetchFailureCount: Int = 0
    var conditionsSchemaVersion: Int = 0

    init(
        timestamp: Date = .now,
        latitude: Double,
        longitude: Double,
        weight: Double = 0,
        isMeasured: Bool = false,
        baitUsed: String = "",
        rodUsed: String = "",
        caughtBy: String = "",
        notes: String = "",
        species: Species? = nil,
        spot: Spot? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.weight = weight
        self.isMeasured = isMeasured
        self.baitUsed = baitUsed
        self.rodUsed = rodUsed
        self.caughtBy = caughtBy
        self.notes = notes
        self.species = species
        self.spot = spot
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

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

enum PressureTrend: String, CaseIterable {
    case rising
    case falling
    case steady

    var display: String {
        switch self {
        case .rising:  return "Rising"
        case .falling: return "Falling"
        case .steady:  return "Steady"
        }
    }

    var symbolName: String {
        switch self {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .steady:  return "arrow.right"
        }
    }
}
