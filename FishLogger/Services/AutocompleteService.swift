import Foundation
import SwiftData

enum AutocompleteFieldKind {
    case bait
    case rod
}

enum AutocompleteService {
    static func suggestions(for field: AutocompleteFieldKind, context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Catch>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let catches = (try? context.fetch(descriptor)) ?? []

        var seen = Set<String>()
        var ordered: [String] = []
        for c in catches {
            let raw = field == .bait ? c.baitUsed : c.rodUsed
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

    static func filtered(_ all: [String], matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        let lower = trimmed.lowercased()
        return all.filter { $0.lowercased().contains(lower) }
    }
}
