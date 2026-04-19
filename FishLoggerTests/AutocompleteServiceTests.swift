import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct AutocompleteServiceTests {

    @Test
    func deduplicatesCaseInsensitively() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let c1 = Catch(latitude: 0, longitude: 0, baitUsed: "Spinnerbait")
        c1.timestamp = Date(timeIntervalSince1970: 100)
        let c2 = Catch(latitude: 0, longitude: 0, baitUsed: "spinnerbait")
        c2.timestamp = Date(timeIntervalSince1970: 200)
        let c3 = Catch(latitude: 0, longitude: 0, baitUsed: "Nightcrawler")
        c3.timestamp = Date(timeIntervalSince1970: 300)
        [c1, c2, c3].forEach(context.insert)

        let suggestions = AutocompleteService.suggestions(for: .bait, context: context)
        #expect(suggestions.count == 2)
        // Recency-first: Nightcrawler (newest) then Spinnerbait
        #expect(suggestions.first == "Nightcrawler")
    }

    @Test
    func emptyValuesAreFiltered() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let c1 = Catch(latitude: 0, longitude: 0, baitUsed: "")
        let c2 = Catch(latitude: 0, longitude: 0, baitUsed: "   ")
        let c3 = Catch(latitude: 0, longitude: 0, baitUsed: "Jig")
        [c1, c2, c3].forEach(context.insert)

        let suggestions = AutocompleteService.suggestions(for: .bait, context: context)
        #expect(suggestions == ["Jig"])
    }

    @Test
    func filtersByQuery() {
        let all = ["Spinnerbait", "Nightcrawler", "Jig", "Spin fly"]
        let filtered = AutocompleteService.filtered(all, matching: "spin")
        #expect(filtered == ["Spinnerbait", "Spin fly"])
    }

    @Test
    func anglerSuggestionsDedupAndOrderByRecency() throws {
        let container = try TestContainer.make()
        let context = container.mainContext

        let c1 = Catch(latitude: 0, longitude: 0, caughtBy: "PJ")
        c1.timestamp = Date(timeIntervalSince1970: 100)
        let c2 = Catch(latitude: 0, longitude: 0, caughtBy: "pj")
        c2.timestamp = Date(timeIntervalSince1970: 200)
        let c3 = Catch(latitude: 0, longitude: 0, caughtBy: "Sam")
        c3.timestamp = Date(timeIntervalSince1970: 300)
        [c1, c2, c3].forEach(context.insert)

        let suggestions = AutocompleteService.suggestions(for: .angler, context: context)
        #expect(suggestions.count == 2)
        #expect(suggestions.first == "Sam")
    }
}
