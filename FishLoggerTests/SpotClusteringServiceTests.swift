import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct SpotClusteringServiceTests {

    @Test
    func newSessionWithoutSpotsCreatesFirstSpot() throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        let session = Session(latitude: 41.5, longitude: -74.0)
        context.insert(session)
        let spot = SpotClusteringService.assignSpot(for: session, in: context)
        #expect(spot.name == "Spot 1")
        #expect(session.spot === spot)
    }

    @Test
    func sessionWithinRadiusJoinsExistingSpot() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let a = Session(latitude: 41.5000, longitude: -74.0000)
        context.insert(a)
        let s1 = SpotClusteringService.assignSpot(for: a, in: context)

        // ~50m north (~0.00045 deg lat)
        let b = Session(latitude: 41.50045, longitude: -74.0000)
        context.insert(b)
        let s2 = SpotClusteringService.assignSpot(for: b, in: context)

        #expect(s1 === s2)
        // Centroid should have moved slightly north (average of the two sessions).
        #expect(s2.centerLat > 41.5)
        #expect(s2.centerLat < 41.50045)
    }

    @Test
    func sessionOutsideRadiusCreatesNewSpot() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let a = Session(latitude: 41.5000, longitude: -74.0000)
        context.insert(a)
        _ = SpotClusteringService.assignSpot(for: a, in: context)

        // ~500m north
        let b = Session(latitude: 41.5045, longitude: -74.0000)
        context.insert(b)
        let s2 = SpotClusteringService.assignSpot(for: b, in: context)

        #expect(s2.name == "Spot 2")
    }

    @Test
    func nearestSpotWins() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        // Manual spot farther away
        let farSpot = Spot(name: "Far", centerLat: 41.505, centerLon: -74.0, isManual: true)
        context.insert(farSpot)

        // Auto spot nearer
        let near = Session(latitude: 41.5005, longitude: -74.0)
        context.insert(near)
        _ = SpotClusteringService.assignSpot(for: near, in: context)

        let test = Session(latitude: 41.5006, longitude: -74.0)
        context.insert(test)
        let chosen = SpotClusteringService.assignSpot(for: test, in: context)
        #expect(chosen !== farSpot)
    }

    @Test
    func manualSpotParticipatesInClustering() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let manual = Spot(name: "The Cove", centerLat: 41.5, centerLon: -74.0, isManual: true)
        context.insert(manual)

        let session = Session(latitude: 41.5001, longitude: -74.0)
        context.insert(session)
        let assigned = SpotClusteringService.assignSpot(for: session, in: context)
        #expect(assigned === manual)
    }

    @Test
    func centroidWeightedBySessionCountNotCatchCount() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        // Two sessions ~55m apart (well inside the 100m clustering radius).
        // The second session has 20 catches — those catches should NOT drag
        // the centroid more than the session itself does.
        let a = Session(latitude: 41.5000, longitude: -74.0)
        context.insert(a)
        _ = SpotClusteringService.assignSpot(for: a, in: context)

        let b = Session(latitude: 41.5005, longitude: -74.0)
        context.insert(b)
        for _ in 0..<20 {
            let c = Catch(latitude: 41.5005, longitude: -74.0, session: b)
            context.insert(c)
        }
        let spot = SpotClusteringService.assignSpot(for: b, in: context)

        // Midpoint of two sessions at equal weight, regardless of catch counts.
        #expect(abs(spot.centerLat - 41.50025) < 0.00001)
    }
}
