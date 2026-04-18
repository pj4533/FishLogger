import SwiftUI
import SwiftData

@main
struct FishLoggerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(for: Catch.self, Species.self, Spot.self, MediaAsset.self)
            self.modelContainer = container
            try SpeciesSeeder.seedIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to set up SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.sunset)
        }
        .modelContainer(modelContainer)
    }
}
