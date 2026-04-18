import Foundation
import SwiftData
@testable import FishLogger

enum TestContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Catch.self, Species.self, Spot.self, MediaAsset.self,
            configurations: config
        )
    }
}
