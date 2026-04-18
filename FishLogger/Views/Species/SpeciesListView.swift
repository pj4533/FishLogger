import SwiftUI
import SwiftData

struct SpeciesListView: View {
    @Query(sort: \Species.sortOrder) private var species: [Species]
    @Query(sort: \Spot.createdAt) private var spots: [Spot]

    private var caughtSpeciesBySpot: [Spot: [Species]] {
        var map: [Spot: Set<Species>] = [:]
        for spot in spots {
            for entry in spot.catches {
                if let s = entry.species {
                    map[spot, default: []].insert(s)
                }
            }
        }
        return map.mapValues { Array($0).sorted { $0.sortOrder < $1.sortOrder } }
    }

    private var uncaughtSpecies: [Species] {
        let caught = Set(species.filter { !$0.catches.isEmpty })
        return species.filter { !caught.contains($0) }
    }

    var body: some View {
        Group {
            if species.isEmpty {
                EmptyState(
                    symbol: "checklist",
                    title: "No species yet",
                    message: "Add species to your checkoff via Species.json, then start catching."
                )
            } else {
                List {
                    if !spots.isEmpty {
                        Section("By Spot") {
                            ForEach(spots) { spot in
                                DisclosureGroup {
                                    let caughtHere = caughtSpeciesBySpot[spot] ?? []
                                    if caughtHere.isEmpty {
                                        Text("No species caught here yet.")
                                            .font(.cozyCaption)
                                            .foregroundStyle(Color.inkFaded)
                                    } else {
                                        ForEach(caughtHere) { s in
                                            NavigationLink(value: s) {
                                                SpeciesRow(species: s, caught: true)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(Color.sunset)
                                        Text(spot.name).font(.species)
                                            .foregroundStyle(Color.ink)
                                        Spacer()
                                        Text("\((caughtSpeciesBySpot[spot] ?? []).count)")
                                            .font(.cozyCaption)
                                            .foregroundStyle(Color.inkFaded)
                                    }
                                }
                                .listRowBackground(Color.paperDeep)
                            }
                        }
                        .listRowBackground(Color.paperDeep)
                    }

                    Section("Full Checkoff") {
                        ForEach(species) { s in
                            NavigationLink(value: s) {
                                SpeciesRow(species: s, caught: !s.catches.isEmpty)
                            }
                            .listRowBackground(Color.paperDeep)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.paper)
            }
        }
        .navigationTitle("Species")
        .navigationDestination(for: Species.self) { s in
            SpeciesDetailView(species: s)
        }
        .background(Color.paper.ignoresSafeArea())
    }
}

private struct SpeciesRow: View {
    let species: Species
    let caught: Bool

    var body: some View {
        HStack(spacing: 12) {
            FishIcon(commonName: species.commonName, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(species.commonName)
                    .font(.cozyBody)
                    .foregroundStyle(Color.ink)
                Text(species.scientificName)
                    .font(.scientificName)
                    .foregroundStyle(Color.inkFaded)
            }
            Spacer()
            Image(systemName: caught ? "checkmark.seal.fill" : "circle.dotted")
                .foregroundStyle(caught ? Color.moss : Color.inkFaded)
        }
        .padding(.vertical, 2)
    }
}
