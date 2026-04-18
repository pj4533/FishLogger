import Foundation
import SwiftData

struct SpeciesSeedEntry: Decodable {
    let commonName: String
    let scientificName: String
    let description: String?
}

enum SpeciesSeederError: Error {
    case missingResource
    case decodingFailed(underlying: Error)
}

enum SpeciesSeeder {
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws {
        let entries = try loadEntries(bundle: bundle)
        guard !entries.isEmpty else { return }

        let existing = try context.fetch(FetchDescriptor<Species>())
        let existingNames = Set(existing.map { $0.commonName.lowercased() })

        var sortOrder = (existing.map { $0.sortOrder }.max() ?? -1) + 1
        var inserted = 0

        for entry in entries {
            if existingNames.contains(entry.commonName.lowercased()) { continue }
            let species = Species(
                commonName: entry.commonName,
                scientificName: entry.scientificName,
                speciesDescription: entry.description ?? "",
                sortOrder: sortOrder
            )
            context.insert(species)
            sortOrder += 1
            inserted += 1
        }

        if inserted > 0 {
            try context.save()
        }
    }

    static func loadEntries(bundle: Bundle = .main) throws -> [SpeciesSeedEntry] {
        guard let url = bundle.url(forResource: "Species", withExtension: "json") else {
            throw SpeciesSeederError.missingResource
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([SpeciesSeedEntry].self, from: data)
        } catch {
            throw SpeciesSeederError.decodingFailed(underlying: error)
        }
    }
}
