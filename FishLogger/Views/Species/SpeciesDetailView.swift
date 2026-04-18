import SwiftUI
import SwiftData

struct SpeciesDetailView: View {
    let species: Species

    private var biggest: Catch? {
        species.catches.max { $0.weight < $1.weight }
    }

    private var mostUsedBait: String? {
        mostCommon(species.catches.map { $0.baitUsed.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private var mostCommonHour: Int? {
        let hours = species.catches.map { Calendar.current.component(.hour, from: $0.timestamp) }
        return mostCommon(hours)
    }

    private var mostCommonMonth: Int? {
        let months = species.catches.map { Calendar.current.component(.month, from: $0.timestamp) }
        return mostCommon(months)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CozyCard {
                    HStack(spacing: 16) {
                        FishIcon(commonName: species.commonName, size: 48, wiggle: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(species.commonName)
                                .font(.diaryHeader)
                                .foregroundStyle(Color.ink)
                            Text(species.scientificName)
                                .font(.scientificName)
                                .foregroundStyle(Color.inkFaded)
                        }
                        Spacer()
                    }
                }
                if !species.speciesDescription.isEmpty {
                    CozyCard {
                        Text(species.speciesDescription)
                            .font(.cozyBody)
                            .foregroundStyle(Color.ink)
                    }
                }
                CozyCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STATS").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                        Stat(label: "Total catches", value: "\(species.catches.count)")
                        if let big = biggest {
                            Stat(
                                label: "Biggest",
                                value: String(format: "%.1f lb %@", big.weight, big.isMeasured ? "(measured)" : "(guessed)")
                            )
                        }
                        if let bait = mostUsedBait {
                            Stat(label: "Favorite bait", value: bait)
                        }
                        if let hour = mostCommonHour {
                            Stat(label: "Most active hour", value: formatHour(hour))
                        }
                        if let month = mostCommonMonth {
                            Stat(label: "Best month", value: DateFormatter().monthSymbols[month - 1])
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatHour(_ h: Int) -> String {
        let d = Calendar.current.date(from: DateComponents(hour: h))!
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: d)
    }

    private func mostCommon<T: Hashable>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        var counts: [T: Int] = [:]
        for i in items { counts[i, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.cozyCaption).foregroundStyle(Color.inkFaded)
            Spacer()
            Text(value).font(.cozyBody).foregroundStyle(Color.ink)
        }
    }
}
