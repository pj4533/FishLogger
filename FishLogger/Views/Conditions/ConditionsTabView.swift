import SwiftUI
import SwiftData

struct ConditionsTabView: View {
    @Query(sort: \Spot.createdAt) private var spots: [Spot]

    private var areas: [FishingArea] {
        FishingAreaClusterer.cluster(spots: spots)
    }

    var body: some View {
        Group {
            if areas.isEmpty {
                EmptyState(
                    symbol: "cloud.sun.fill",
                    title: "No fishing areas yet",
                    message: "Log a catch so FishLogger can show you the forecast for your spot."
                )
                .navigationTitle("Conditions")
                .background(Color.paper.ignoresSafeArea())
            } else if areas.count == 1, let only = areas.first {
                ConditionsDetailView(area: only)
                    .navigationTitle(only.name)
                    .navigationBarTitleDisplayMode(.large)
            } else {
                AreaListView(areas: areas)
                    .navigationTitle("Conditions")
                    .navigationBarTitleDisplayMode(.large)
            }
        }
    }
}

private struct AreaListView: View {
    let areas: [FishingArea]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(areas) { area in
                    NavigationLink(value: area) {
                        AreaRow(area: area)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.paper)
        .navigationDestination(for: FishingArea.self) { area in
            ConditionsDetailView(area: area)
                .navigationTitle(area.name)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AreaRow: View {
    let area: FishingArea

    var body: some View {
        CozyCard {
            HStack(spacing: 12) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundStyle(Color.sunset)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(area.name)
                        .font(.species)
                        .foregroundStyle(Color.ink)
                    Text("\(area.spots.count) spot\(area.spots.count == 1 ? "" : "s")")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFaded)
            }
        }
    }
}
