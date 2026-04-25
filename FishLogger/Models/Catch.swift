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
    var session: Session?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.owner)
    var media: [MediaAsset] = []

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
        session: Session? = nil
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
        self.session = session
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Convenience: the Spot associated with this catch's parent Session.
    var spot: Spot? { session?.spot }
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
