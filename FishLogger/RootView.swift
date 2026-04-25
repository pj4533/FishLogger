import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            NavigationStack { SessionListView() }
                .tabItem { Label("Sessions", systemImage: "book.closed.fill") }

            NavigationStack { SpotsListView() }
                .tabItem { Label("Spots", systemImage: "map.fill") }

            NavigationStack { ConditionsTabView() }
                .tabItem { Label("Conditions", systemImage: "cloud.sun.fill") }

            NavigationStack { SpeciesListView() }
                .tabItem { Label("Species", systemImage: "checklist") }

            NavigationStack { LeaderboardView() }
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
        }
        .tint(Color.sunset)
        .toolbarBackground(Color.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await ConditionsBackfillService.shared.backfillPending(
                context: modelContext,
                weather: WeatherService.shared
            )
        }
    }
}
