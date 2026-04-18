import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DiaryListView() }
                .tabItem { Label("Diary", systemImage: "book.closed.fill") }

            NavigationStack { SpotsListView() }
                .tabItem { Label("Spots", systemImage: "map.fill") }

            NavigationStack { SpeciesListView() }
                .tabItem { Label("Species", systemImage: "checklist") }

            NavigationStack { LeaderboardView() }
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }
        }
        .tint(Color.sunset)
        .toolbarBackground(Color.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
