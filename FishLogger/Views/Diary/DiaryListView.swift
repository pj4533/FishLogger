import SwiftUI
import SwiftData
import MapKit

struct DiaryListView: View {
    @Query(sort: \Catch.timestamp, order: .reverse) private var catches: [Catch]
    @State private var showingAdd = false

    var body: some View {
        Group {
            if catches.isEmpty {
                EmptyState(
                    symbol: "fish",
                    title: "No catches yet",
                    message: "Tap the + to log your first one. The pond awaits."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(catches) { entry in
                            NavigationLink(value: entry) {
                                DiaryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.paper)
            }
        }
        .navigationTitle("Diary")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.sunset)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCatchSheet()
        }
        .navigationDestination(for: Catch.self) { entry in
            CatchDetailView(entry: entry)
        }
        .background(Color.paper.ignoresSafeArea())
    }
}

private struct DiaryRow: View {
    let entry: Catch

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: entry.timestamp).uppercased()
    }

    var body: some View {
        CozyCard {
            HStack(alignment: .top, spacing: 12) {
                if let first = entry.media.first(where: { $0.kind == .photo }) {
                    AsyncImageFromURL(url: first.url)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.waterLight.opacity(0.6))
                        .frame(width: 72, height: 72)
                        .overlay(FishIcon(commonName: entry.species?.commonName ?? "", size: 32))
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let s = entry.species {
                        SpeciesTag(commonName: s.commonName, scientificName: s.scientificName, compact: true)
                    }
                    WeightBadge(weight: entry.weight, isMeasured: entry.isMeasured)
                    HStack(spacing: 8) {
                        Text(dateText)
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                        if !entry.caughtBy.isEmpty {
                            Label(entry.caughtBy, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.fieldLabel)
                                .foregroundStyle(Color.inkFaded)
                        }
                    }
                }
                Spacer()
                MiniMapThumb(coordinate: entry.coordinate)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.bark.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }
}

private struct MiniMapThumb: View {
    let coordinate: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        ))
    }

    var body: some View {
        Map(position: $camera, interactionModes: []) {
            Annotation("", coordinate: coordinate) {
                Circle().fill(Color.sunset).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.paper, lineWidth: 2))
            }
        }
        .allowsHitTesting(false)
    }
}

struct AsyncImageFromURL: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.waterLight.opacity(0.5)
                    .overlay(ProgressView())
            }
        }
        .task(id: url) {
            image = await Self.load(url)
        }
    }

    private static func load(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }
}
