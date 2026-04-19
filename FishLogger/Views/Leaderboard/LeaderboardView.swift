import SwiftUI
import SwiftData

enum LeaderboardMode: String, CaseIterable, Identifiable {
    case species
    case angler
    var id: String { rawValue }
    var label: String {
        switch self {
        case .species: return "Species"
        case .angler:  return "Anglers"
        }
    }
    var icon: String {
        switch self {
        case .species: return "fish.fill"
        case .angler:  return "person.2.fill"
        }
    }
}

struct SpeciesLeaderGroup: Identifiable {
    let species: Species
    let top: [Catch]
    var id: PersistentIdentifier { species.id }
}

struct AnglerLeaderGroup: Identifiable {
    let name: String
    let top: [Catch]
    var id: String { name }
}

struct LeaderboardView: View {
    @Query(sort: \Species.sortOrder) private var species: [Species]
    @Query(sort: \Catch.weight, order: .reverse) private var catches: [Catch]
    @State private var mode: LeaderboardMode = .species

    private var speciesGroups: [SpeciesLeaderGroup] {
        species
            .compactMap { s -> SpeciesLeaderGroup? in
                let top = Array(s.catches.sorted { $0.weight > $1.weight }.prefix(5))
                guard !top.isEmpty else { return nil }
                return SpeciesLeaderGroup(species: s, top: top)
            }
            .sorted { ($0.top.first?.weight ?? 0) > ($1.top.first?.weight ?? 0) }
    }

    private var anglerGroups: [AnglerLeaderGroup] {
        var byAngler: [String: [Catch]] = [:]
        for c in catches {
            let key = c.caughtBy.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = key.isEmpty ? "Unknown" : key
            byAngler[name, default: []].append(c)
        }
        return byAngler
            .map { AnglerLeaderGroup(name: $0.key, top: Array($0.value.prefix(5))) }
            .sorted { ($0.top.first?.weight ?? 0) > ($1.top.first?.weight ?? 0) }
    }

    private var hasAnyCatches: Bool {
        !catches.isEmpty
    }

    var body: some View {
        Group {
            if !hasAnyCatches {
                EmptyState(
                    symbol: "trophy",
                    title: "No records yet",
                    message: "Catches will line up here as trophies, ranked by weight."
                )
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        modePicker
                        switch mode {
                        case .species:
                            ForEach(speciesGroups) { group in
                                SpeciesPodium(group: group)
                            }
                        case .angler:
                            ForEach(anglerGroups) { group in
                                AnglerPodium(group: group)
                            }
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

    private var modePicker: some View {
        Picker("Group by", selection: $mode) {
            ForEach(LeaderboardMode.allCases) { m in
                Label(m.label, systemImage: m.icon).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Species podium

private struct SpeciesPodium: View {
    let group: SpeciesLeaderGroup

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
                    ForEach(Array(group.top.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry, showAngler: true, showSpecies: false)
                    }
                }
            }
        }
    }
}

// MARK: - Angler podium

private struct AnglerPodium: View {
    let group: AnglerLeaderGroup

    private var initials: String {
        let trimmed = group.name.trimmingCharacters(in: .whitespaces)
        let components = trimmed.split(separator: " ")
        let letters = components.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.moss.opacity(0.35))
                            .frame(width: 38, height: 38)
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.ink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.species)
                            .foregroundStyle(Color.ink)
                        Text("\(group.top.count) top catch\(group.top.count == 1 ? "" : "es")")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Color.sunset)
                }
                VStack(spacing: 8) {
                    ForEach(Array(group.top.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry, showAngler: false, showSpecies: true)
                    }
                }
            }
        }
    }
}

// MARK: - Row

struct LeaderboardRow: View {
    let rank: Int
    let entry: Catch
    var showAngler: Bool = true
    var showSpecies: Bool = false

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
                HStack(spacing: 6) {
                    Text(String(format: "%.2f lb", entry.weight))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .strikethrough(!entry.isMeasured, color: Color.inkFaded)
                        .foregroundStyle(Color.ink)
                    if showSpecies, let s = entry.species {
                        Text("·").foregroundStyle(Color.inkFaded)
                        Text(s.commonName)
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                }
                HStack(spacing: 8) {
                    Text(dateString)
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                    if showAngler, !entry.caughtBy.isEmpty {
                        Label(entry.caughtBy, systemImage: "person.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                }
            }
            Spacer()
            Image(systemName: entry.isMeasured ? "ruler.fill" : "questionmark.circle.fill")
                .foregroundStyle(entry.isMeasured ? Color.moss : Color.sunset)
        }
    }
}
