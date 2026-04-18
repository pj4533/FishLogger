import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct SpeciesSeederTests {

    @Test
    func loadsSpeciesFromBundle() throws {
        let entries = try SpeciesSeeder.loadEntries(bundle: .main)
        #expect(!entries.isEmpty)
        #expect(entries.contains { $0.commonName == "Largemouth Bass" })
    }

    @Test
    func firstRunInsertsAllSpeciesAndSecondRunIsIdempotent() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        try SpeciesSeeder.seedIfNeeded(context: context, bundle: .main)
        let firstCount = try context.fetch(FetchDescriptor<Species>()).count
        #expect(firstCount > 0)

        try SpeciesSeeder.seedIfNeeded(context: context, bundle: .main)
        let secondCount = try context.fetch(FetchDescriptor<Species>()).count
        #expect(secondCount == firstCount)
    }

    @Test
    func doesNotDuplicateOnExistingCommonName() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let existing = Species(commonName: "Largemouth Bass", scientificName: "test")
        context.insert(existing)

        try SpeciesSeeder.seedIfNeeded(context: context, bundle: .main)
        let results = try context.fetch(FetchDescriptor<Species>())
        let largemouthMatches = results.filter { $0.commonName == "Largemouth Bass" }
        #expect(largemouthMatches.count == 1)
    }
}
