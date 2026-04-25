import Foundation
import CoreLocation
import SwiftData

@Model
final class Spot {
    var id: UUID
    var name: String
    var centerLat: Double
    var centerLon: Double
    var isManual: Bool
    var createdAt: Date

    @Relationship(inverse: \Session.spot)
    var sessions: [Session] = []

    init(name: String, centerLat: Double, centerLon: Double, isManual: Bool = false, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.isManual = isManual
        self.createdAt = createdAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
    }

    /// All catches logged at this spot, derived via sessions.
    var catches: [Catch] {
        sessions.flatMap { $0.catches }
    }
}
