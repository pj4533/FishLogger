import Foundation
import CoreLocation
import SwiftData

enum SpotClusteringService {
    static let defaultRadiusMeters: Double = 100

    @discardableResult
    static func assignSpot(
        for session: Session,
        in context: ModelContext,
        radiusMeters: Double = defaultRadiusMeters
    ) -> Spot {
        let sessionLocation = CLLocation(latitude: session.latitude, longitude: session.longitude)
        let descriptor = FetchDescriptor<Spot>()
        let spots = (try? context.fetch(descriptor)) ?? []

        let nearest = spots
            .map { (spot: $0, distance: CLLocation(latitude: $0.centerLat, longitude: $0.centerLon).distance(from: sessionLocation)) }
            .sorted { a, b in
                if a.distance == b.distance { return a.spot.createdAt < b.spot.createdAt }
                return a.distance < b.distance
            }
            .first

        if let nearest, nearest.distance <= radiusMeters {
            assign(session, to: nearest.spot)
            return nearest.spot
        }

        let count = spots.count
        let newSpot = Spot(
            name: "Spot \(count + 1)",
            centerLat: session.latitude,
            centerLon: session.longitude,
            isManual: false
        )
        context.insert(newSpot)
        assign(session, to: newSpot)
        return newSpot
    }

    /// Weighted by session count — a multi-catch session pulls the centroid
    /// the same as a single-catch session at the same coordinates, which keeps
    /// the cluster center honest to where you actually fished, not where you
    /// happened to land the most fish.
    private static func assign(_ session: Session, to spot: Spot) {
        // Read member count BEFORE the assignment — SwiftData propagates the
        // inverse eagerly, so `spot.sessions` already includes `session` as
        // soon as `session.spot = spot` runs, which would over-count by one.
        let memberCount = spot.sessions.count
        session.spot = spot
        let total = Double(memberCount + 1)
        spot.centerLat = (spot.centerLat * Double(memberCount) + session.latitude) / total
        spot.centerLon = (spot.centerLon * Double(memberCount) + session.longitude) / total
    }
}
