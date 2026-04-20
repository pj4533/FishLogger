import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import FishLogger

@MainActor
struct FishingAreaClustererTests {

    @Test
    func singleSpotMakesOneArea() throws {
        let container = try TestContainer.make()
        let spot = Spot(name: "Dock", centerLat: 41.5, centerLon: -74.0)
        container.mainContext.insert(spot)

        let areas = FishingAreaClusterer.cluster(spots: [spot])
        #expect(areas.count == 1)
        #expect(areas[0].spots.count == 1)
        #expect(areas[0].name == "Dock")
    }

    @Test
    func spotsWithin2kmCollapseToOneArea() throws {
        let container = try TestContainer.make()
        // Three points within ~400m of each other — same pond scenario.
        let a = Spot(name: "Dock",        centerLat: 41.5000, centerLon: -74.0000)
        let b = Spot(name: "Weed bed",    centerLat: 41.5020, centerLon: -74.0010)
        let c = Spot(name: "Lily pads",   centerLat: 41.5015, centerLon: -73.9990)
        [a, b, c].forEach { container.mainContext.insert($0) }

        let areas = FishingAreaClusterer.cluster(spots: [a, b, c])
        #expect(areas.count == 1)
        #expect(areas[0].spots.count == 3)
    }

    @Test
    func distantSpotsFormSeparateAreas() throws {
        let container = try TestContainer.make()
        // Two points ~5km apart.
        let pondSpot = Spot(name: "Pond",  centerLat: 41.5000, centerLon: -74.0000)
        let lakeSpot = Spot(name: "Lake",  centerLat: 41.5500, centerLon: -74.0000)
        [pondSpot, lakeSpot].forEach { container.mainContext.insert($0) }

        let areas = FishingAreaClusterer.cluster(spots: [pondSpot, lakeSpot])
        #expect(areas.count == 2)
        let names = Set(areas.map { $0.name })
        #expect(names.contains("Pond"))
        #expect(names.contains("Lake"))
    }

    @Test
    func centroidIsMeanOfMemberSpots() throws {
        let container = try TestContainer.make()
        let a = Spot(name: "A", centerLat: 41.5, centerLon: -74.0)
        let b = Spot(name: "B", centerLat: 41.502, centerLon: -74.001)
        [a, b].forEach { container.mainContext.insert($0) }

        let areas = FishingAreaClusterer.cluster(spots: [a, b])
        #expect(areas.count == 1)
        let centroid = areas[0].centroid
        #expect(abs(centroid.latitude - 41.501) < 0.0001)
        #expect(abs(centroid.longitude - (-74.0005)) < 0.0001)
    }

    @Test
    func identifierIsStableAcrossReruns() throws {
        let container = try TestContainer.make()
        let a = Spot(name: "A", centerLat: 41.5, centerLon: -74.0)
        let b = Spot(name: "B", centerLat: 41.5005, centerLon: -74.0)
        [a, b].forEach { container.mainContext.insert($0) }

        let first = FishingAreaClusterer.cluster(spots: [a, b])
        let second = FishingAreaClusterer.cluster(spots: [b, a])
        #expect(first[0].id == second[0].id)
    }

    @Test
    func emptyInputReturnsEmpty() {
        let areas = FishingAreaClusterer.cluster(spots: [])
        #expect(areas.isEmpty)
    }
}
