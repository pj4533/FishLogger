import SwiftUI
import SwiftData

struct LeaderboardGroup: Identifiable {
    let species: Species
    let top: [Catch]
    var id: PersistentIdentifier { species.id }
}

struct LeaderboardView: View {
    @Query(sort: \Species.sortOrder) private var species: [Species]

    private var grouped: [LeaderboardGroup] {
        species
            .compactMap { s -> LeaderboardGroup? in
                let top = Array(s.catches.sorted { $0.weight > $1.weight }.prefix(5))
                guard !top.isEmpty else { return nil }
                return LeaderboardGroup(species: s, top: top)
            }
            .sorted { ($0.top.first?.weight ?? 0) > ($1.top.first?.weight ?? 0) }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                EmptyState(
                    symbol: "trophy",
                    title: "No records yet",
                    message: "Catches will line up here as trophies, ranked by weight."
                )
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(grouped) { group in
                            SpeciesPodium(group: group)
                        }
                    }
                    .padding(16)
                }
                .background(Color.paper)
            }
        }
        .navigationTitle("Leaderboard")
        .background(Color.paper.ignoresSafeArea())
    }
}

private struct SpeciesPodium: View {
    let group: LeaderboardGroup

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FishIcon(commonName: group.species.commonName, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.species.commonName)
                            .font(.species)
                            .foregroundStyle(Color.ink)
                        Text(group.species.scientificName)
                            .font(.scientificName)
                            .foregroundStyle(Color.inkFaded)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Color.sunset)
                }
                VStack(spacing: 8) {
                    ForEach(Array(group.top.enumerated()), id: \.element.id) { (index, entry) in
                        LeaderboardRow(rank: index + 1, entry: entry)
                    }
                }
            }
        }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: Catch

    private var rankColor: Color {
        switch rank {
        case 1: return .sunset
        case 2: return .inkFaded
        case 3: return .bark
        default: return .inkFaded.opacity(0.6)
        }
    }

    private var rankLabel: String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rankColor)
                    .frame(width: 38, height: 26)
                Text(rankLabel)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.paper)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.2f lb", entry.weight))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .strikethrough(!entry.isMeasured, color: Color.inkFaded)
                    .foregroundStyle(Color.ink)
                Text(dateString)
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
            Spacer()
            Image(systemName: entry.isMeasured ? "ruler.fill" : "questionmark.circle.fill")
                .foregroundStyle(entry.isMeasured ? Color.moss : Color.sunset)
        }
    }
}
