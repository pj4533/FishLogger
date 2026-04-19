import SwiftUI
import SwiftData
import MapKit

struct SpotDetailView: View {
    @Bindable var spot: Spot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    private var sortedCatches: [Catch] {
        spot.catches.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SpotMap(coordinate: spot.coordinate, catches: sortedCatches)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.bark, lineWidth: 2)
                    )
                    .padding(.horizontal, 16)

                CozyCard {
                    VStack(alignment: .leading, spacing: 10) {
                        if isEditing {
                            TextField("Name", text: $spot.name)
                                .font(.species)
                        } else {
                            Text(spot.name).font(.species).foregroundStyle(Color.ink)
                        }
                        HStack {
                            Image(systemName: spot.isManual ? "pencil.circle.fill" : "sparkles")
                                .foregroundStyle(Color.inkFaded)
                            Text(spot.isManual ? "Manually added" : "Auto-clustered")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Text("Catches at this spot")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                LazyVStack(spacing: 10) {
                    ForEach(sortedCatches) { entry in
                        NavigationLink(value: entry) {
                            CozyCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        if let s = entry.species {
                                            SpeciesTag(commonName: s.commonName, scientificName: s.scientificName, compact: true)
                                        }
                                        Spacer()
                                        WeightBadge(weight: entry.weight, isMeasured: entry.isMeasured)
                                    }
                                    if !entry.caughtBy.isEmpty {
                                        Label(entry.caughtBy, systemImage: "person.fill")
                                            .font(.fieldLabel)
                                            .foregroundStyle(Color.inkFaded)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .foregroundStyle(Color.sunset)
            }
        }
    }
}

private struct SpotMap: View {
    let coordinate: CLLocationCoordinate2D
    let catches: [Catch]
    @State private var camera: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, catches: [Catch]) {
        self.coordinate = coordinate
        self.catches = catches
        _camera = State(initialValue: .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        ))
    }

    var body: some View {
        Map(position: $camera) {
            Annotation("", coordinate: coordinate) { WoodenStake() }
            ForEach(catches) { c in
                Annotation("", coordinate: c.coordinate) {
                    Circle()
                        .fill(Color.sunset)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.paper, lineWidth: 2))
                }
            }
        }
    }
}
