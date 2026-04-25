import SwiftUI
import SwiftData
import OSLog

@main
struct FishLoggerApp: App {
    private let modelContainer: ModelContainer
    private static let log = Logger(subsystem: "com.saygoodnight.FishLogger", category: "App")

    init() {
        do {
            let container: ModelContainer
            do {
                container = try ModelContainer(
                    for: Catch.self, Species.self, Spot.self, Session.self, MediaAsset.self
                )
            } catch {
                // Schema migration failed. Since FishLogger is a single-user
                // dev app and media survives on disk, prefer wiping the store
                // and starting fresh over crashing on every launch.
                Self.log.error("ModelContainer init failed, resetting store: \(error.localizedDescription, privacy: .public)")
                Self.wipeDefaultStore()
                container = try ModelContainer(
                    for: Catch.self, Species.self, Spot.self, Session.self, MediaAsset.self
                )
            }
            self.modelContainer = container
            try SpeciesSeeder.seedIfNeeded(context: container.mainContext)
            SessionMigrator.migrateIfNeeded(context: container.mainContext)
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

    private static func wipeDefaultStore() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let url = appSupport.appendingPathComponent(name)
            try? fm.removeItem(at: url)
        }
    }
}
