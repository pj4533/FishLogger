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

    @Relationship(inverse: \Catch.spot)
    var catches: [Catch] = []

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
}
