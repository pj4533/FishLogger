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
}
