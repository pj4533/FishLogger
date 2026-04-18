import SwiftUI
import SwiftData
import MapKit

struct SpotsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Spot.createdAt, order: .reverse) private var spots: [Spot]
    @State private var showingAddSheet = false

    private var overviewRegion: MKCoordinateRegion? {
        guard !spots.isEmpty else { return nil }
        let lats = spots.map(\.centerLat)
        let lons = spots.map(\.centerLon)
        let midLat = (lats.min()! + lats.max()!) / 2
        let midLon = (lons.min()! + lons.max()!) / 2
        let spanLat = max(0.003, (lats.max()! - lats.min()!) * 1.6)
        let spanLon = max(0.003, (lons.max()! - lons.min()!) * 1.6)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }

    var body: some View {
        Group {
            if spots.isEmpty {
                EmptyState(
                    symbol: "mappin.slash",
                    title: "No spots yet",
                    message: "Spots appear automatically when you log a catch, or you can add one manually."
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let region = overviewRegion {
                            SpotsOverviewMap(region: region, spots: spots)
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.bark, lineWidth: 2)
                                )
                                .padding(.horizontal, 16)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(spots) { spot in
                                NavigationLink(value: spot) {
                                    SpotRow(spot: spot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
                .background(Color.paper)
            }
        }
        .navigationTitle("Spots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.sunset)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSpotSheet()
        }
        .navigationDestination(for: Spot.self) { spot in
            SpotDetailView(spot: spot)
        }
        .background(Color.paper.ignoresSafeArea())
    }
}

private struct SpotsOverviewMap: View {
    let region: MKCoordinateRegion
    let spots: [Spot]
    @State private var camera: MapCameraPosition

    init(region: MKCoordinateRegion, spots: [Spot]) {
        self.region = region
        self.spots = spots
        _camera = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    WoodenStake(label: spot.name)
                }
            }
        }
    }
}

private struct SpotRow: View {
    let spot: Spot

    var body: some View {
        CozyCard {
            HStack(spacing: 14) {
                Image(systemName: spot.isManual ? "mappin.circle.fill" : "mappin.and.ellipse")
                    .font(.title2)
                    .foregroundStyle(Color.sunset)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.species)
                        .foregroundStyle(Color.ink)
                    Text("\(spot.catches.count) \(spot.catches.count == 1 ? "catch" : "catches")")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.inkFaded)
            }
        }
    }
}

private struct AddSpotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String = ""
    @State private var location = LocationService()
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var error: String?
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CozyCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NAME").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                            TextField("e.g. The Cove", text: $name)
                                .font(.cozyBody)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.paper)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
                                )
                        }
                    }
                    CozyCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LOCATION").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                            if isRequesting { ProgressView() }
                            if let c = coordinate {
                                Text(String(format: "%.5f, %.5f", c.latitude, c.longitude))
                                    .font(.cozyCaption)
                                    .foregroundStyle(Color.ink)
                            }
                            Button {
                                Task {
                                    isRequesting = true
                                    defer { isRequesting = false }
                                    do {
                                        let loc = try await location.requestCurrentLocation()
                                        coordinate = loc.coordinate
                                    } catch {
                                        self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                                    }
                                }
                            } label: {
                                Label("Use my current location", systemImage: "location.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.sunset)
                        }
                    }
                    if let error {
                        Text(error).font(.cozyCaption).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("New Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        guard let c = coordinate else { return }
                        let spot = Spot(
                            name: name.isEmpty ? "Untitled Spot" : name,
                            centerLat: c.latitude,
                            centerLon: c.longitude,
                            isManual: true
                        )
                        context.insert(spot)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(coordinate == nil)
                }
            }
        }
    }
}
