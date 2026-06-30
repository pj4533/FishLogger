import Foundation
import SwiftData

/// Serializes the entire local store into a single, analysis-friendly JSON
/// file: spots and species as top-level reference lists, then every session
/// with its full conditions block and nested catches.
///
/// Units are encoded as stored (Celsius, km/h, millibars) and carried in the
/// field names. Dates are ISO-8601. Media is referenced by relative path only —
/// the binary files are not included.
enum ExportService {

    /// Schema version of the export envelope itself. Bump when the JSON shape
    /// changes so downstream analysis can branch on it.
    /// v2: adds per-session `events`, `coverageSegments`, `currentSetup`,
    /// `currentSubSpot`, and per-catch `setup`.
    static let exportSchemaVersion = 2

    static func makeJSONFile(context: ModelContext, now: Date = .now) throws -> URL {
        let snapshot = try buildSnapshot(context: context, now: now)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)

        let stamp = filenameDateFormatter.string(from: now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FishLogger-Export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Snapshot assembly

    static func buildSnapshot(context: ModelContext, now: Date = .now) throws -> ExportSnapshot {
        let sessions = try context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .forward)])
        )
        let spots = try context.fetch(
            FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )
        let species = try context.fetch(
            FetchDescriptor<Species>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        )

        let sessionDTOs = sessions.map { SessionDTO($0, now: now) }
        let catchCount = sessionDTOs.reduce(0) { $0 + $1.catches.count }
        let eventCount = sessionDTOs.reduce(0) { $0 + $1.events.count }
        let segmentCount = sessionDTOs.reduce(0) { $0 + $1.coverageSegments.count }

        return ExportSnapshot(
            exportSchemaVersion: exportSchemaVersion,
            appVersion: appVersionString,
            exportedAt: now,
            sessionCount: sessionDTOs.count,
            catchCount: catchCount,
            eventCount: eventCount,
            segmentCount: segmentCount,
            spotCount: spots.count,
            speciesCount: species.count,
            spots: spots.map { SpotDTO($0) },
            species: species.map { SpeciesDTO($0) },
            sessions: sessionDTOs
        )
    }

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - DTOs

struct ExportSnapshot: Codable {
    let exportSchemaVersion: Int
    let appVersion: String
    let exportedAt: Date
    let sessionCount: Int
    let catchCount: Int
    let eventCount: Int
    let segmentCount: Int
    let spotCount: Int
    let speciesCount: Int
    let spots: [SpotDTO]
    let species: [SpeciesDTO]
    let sessions: [SessionDTO]
}

struct SpotDTO: Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let isManual: Bool
    let createdAt: Date

    init(_ spot: Spot) {
        id = spot.id
        name = spot.name
        latitude = spot.centerLat
        longitude = spot.centerLon
        isManual = spot.isManual
        createdAt = spot.createdAt
    }
}

struct SpeciesDTO: Codable {
    let commonName: String
    let scientificName: String
    let description: String
    let sortOrder: Int

    init(_ species: Species) {
        commonName = species.commonName
        scientificName = species.scientificName
        description = species.speciesDescription
        sortOrder = species.sortOrder
    }
}

struct SessionDTO: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double
    let isOngoing: Bool
    let latitude: Double
    let longitude: Double
    let notes: String

    let spotId: UUID?
    let spotName: String?

    // Conditions (nil until backfilled)
    let airTempC: Double?
    let humidity: Double?
    let cloudCoverage: Double?
    let conditionSymbol: String?
    let conditionCode: String?
    let windSpeedKmh: Double?
    let windGustKmh: Double?
    let windDirectionDegrees: Double?
    let pressureMb: Double?
    let pressureTrend: String?
    let pressureTrend6hMb: Double?
    let precipIntensityMmh: Double?
    let precipProbability: Double?
    let sunriseAt: Date?
    let sunsetAt: Date?
    let moonPhase: Double?
    let moonIllumination: Double?
    let solunarMajors: [IntervalDTO]
    let solunarMinors: [IntervalDTO]
    let conditionsFetchedAt: Date?

    let currentSetup: Setup
    let currentSubSpot: String
    let currentAngler: String
    let events: [SessionEventDTO]
    let coverageSegments: [CoverageSegmentDTO]

    let catches: [CatchDTO]

    init(_ session: Session, now: Date = .now) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationSeconds = session.duration
        isOngoing = session.isOngoing
        latitude = session.latitude
        longitude = session.longitude
        notes = session.notes

        spotId = session.spot?.id
        spotName = session.spot?.name

        airTempC = session.airTempC
        humidity = session.humidity
        cloudCoverage = session.cloudCoverage
        conditionSymbol = session.conditionSymbol
        conditionCode = session.conditionCode
        windSpeedKmh = session.windSpeedKmh
        windGustKmh = session.windGustKmh
        windDirectionDegrees = session.windDirectionDegrees
        pressureMb = session.pressureMb
        pressureTrend = session.pressureTrendRaw
        pressureTrend6hMb = session.pressureTrend6hMb
        precipIntensityMmh = session.precipIntensityMmh
        precipProbability = session.precipProbability
        sunriseAt = session.sunriseAt
        sunsetAt = session.sunsetAt
        moonPhase = session.moonPhase
        moonIllumination = session.moonIllumination
        solunarMajors = session.solunarMajors.map { IntervalDTO($0) }
        solunarMinors = session.solunarMinors.map { IntervalDTO($0) }
        conditionsFetchedAt = session.conditionsFetchedAt

        currentSetup = session.currentSetup
        currentSubSpot = session.currentSubSpot
        currentAngler = session.currentAngler
        events = session.events
            .sorted { $0.timestamp < $1.timestamp }
            .map { SessionEventDTO($0) }
        coverageSegments = CoverageDerivation.segments(for: session, now: now)
            .map { CoverageSegmentDTO($0) }

        catches = session.catches
            .sorted { $0.timestamp < $1.timestamp }
            .map { CatchDTO($0) }
    }
}

struct SessionEventDTO: Codable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let setup: Setup?
    let subSpot: String?
    let outcome: String?
    let detail: String?
    let latitude: Double?
    let longitude: Double?

    init(_ event: SessionEvent) {
        id = event.id
        timestamp = event.timestamp
        kind = event.kindRaw
        setup = event.setupSnapshot
        subSpot = event.subSpot
        outcome = event.outcomeRaw
        detail = event.detail
        latitude = event.latitude
        longitude = event.longitude
    }
}

struct CoverageSegmentDTO: Codable {
    let start: Date
    let end: Date
    let durationSeconds: Double
    let setup: Setup
    let subSpot: String
    let outcome: String
    let catchCount: Int
    let biteCount: Int
    let catchIds: [UUID]

    init(_ segment: CoverageSegment) {
        start = segment.start
        end = segment.end
        durationSeconds = segment.durationSeconds
        setup = segment.setup
        subSpot = segment.subSpot
        outcome = segment.outcome.rawValue
        catchCount = segment.catchCount
        biteCount = segment.biteCount
        catchIds = segment.catchIds
    }
}

struct CatchDTO: Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speciesCommonName: String?
    let speciesScientificName: String?
    let weightLb: Double
    let isMeasured: Bool
    let baitUsed: String
    let rodUsed: String
    let caughtBy: String
    let notes: String
    let setup: Setup?
    let subSpot: String?
    let media: [MediaDTO]

    init(_ entry: Catch) {
        id = entry.id
        timestamp = entry.timestamp
        latitude = entry.latitude
        longitude = entry.longitude
        speciesCommonName = entry.species?.commonName
        speciesScientificName = entry.species?.scientificName
        weightLb = entry.weight
        isMeasured = entry.isMeasured
        baitUsed = entry.baitUsed
        rodUsed = entry.rodUsed
        caughtBy = entry.caughtBy
        notes = entry.notes
        setup = entry.setupSnapshot
        subSpot = entry.subSpotSnapshot
        media = entry.media
            .sorted { $0.createdAt < $1.createdAt }
            .map { MediaDTO($0) }
    }
}

struct MediaDTO: Codable {
    let id: UUID
    let relativePath: String
    let kind: String
    let createdAt: Date

    init(_ asset: MediaAsset) {
        id = asset.id
        relativePath = asset.relativePath
        kind = asset.kind.rawValue
        createdAt = asset.createdAt
    }
}

struct IntervalDTO: Codable {
    let start: Date
    let end: Date

    init(_ interval: DateInterval) {
        start = interval.start
        end = interval.end
    }
}
