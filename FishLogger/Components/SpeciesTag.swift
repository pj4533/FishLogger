import SwiftUI

struct SpeciesTag: View {
    let commonName: String
    let scientificName: String
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commonName)
                .font(compact ? .cozyBody : .species)
                .foregroundStyle(Color.ink)
            Text(scientificName)
                .font(.scientificName)
                .foregroundStyle(Color.inkFaded)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.moss.opacity(0.25))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(commonName), \(scientificName)")
    }
}

#Preview {
    VStack(spacing: 12) {
        SpeciesTag(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides")
        SpeciesTag(commonName: "Bluegill", scientificName: "Lepomis macrochirus", compact: true)
    }
    .padding()
    .background(Color.paper)
}
