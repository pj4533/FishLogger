import Foundation
import CoreLocation
import SwiftData

enum SpotClusteringService {
    static let defaultRadiusMeters: Double = 100

    static func assignSpot(
        for catchEntry: Catch,
        in context: ModelContext,
        radiusMeters: Double = defaultRadiusMeters
    ) -> Spot {
        let catchLocation = CLLocation(latitude: catchEntry.latitude, longitude: catchEntry.longitude)
        let descriptor = FetchDescriptor<Spot>()
        let spots = (try? context.fetch(descriptor)) ?? []

        let nearest = spots
            .map { (spot: $0, distance: CLLocation(latitude: $0.centerLat, longitude: $0.centerLon).distance(from: catchLocation)) }
            .sorted { a, b in
                if a.distance == b.distance { return a.spot.createdAt < b.spot.createdAt }
                return a.distance < b.distance
            }
            .first

        if let nearest, nearest.distance <= radiusMeters {
            assign(catchEntry, to: nearest.spot)
            return nearest.spot
        }

        let count = spots.count
        let newSpot = Spot(
            name: "Spot \(count + 1)",
            centerLat: catchEntry.latitude,
            centerLon: catchEntry.longitude,
            isManual: false
        )
        context.insert(newSpot)
        assign(catchEntry, to: newSpot)
        return newSpot
    }

    private static func assign(_ catchEntry: Catch, to spot: Spot) {
        catchEntry.spot = spot
        let memberCount = spot.catches.count
        let total = Double(memberCount + 1)
        spot.centerLat = (spot.centerLat * Double(memberCount) + catchEntry.latitude) / total
        spot.centerLon = (spot.centerLon * Double(memberCount) + catchEntry.longitude) / total
    }
}
