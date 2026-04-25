import SwiftUI
import SwiftData
import MapKit

struct CatchDetailView: View {
    @Bindable var entry: Catch
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Species.sortOrder) private var allSpecies: [Species]
    @State private var isEditing = false
    @State private var thumbnailPickerAsset: MediaAsset?

    private var anglerSuggestions: [String] {
        AutocompleteService.suggestions(for: .angler, context: context)
    }
    private var baitSuggestions: [String] {
        AutocompleteService.suggestions(for: .bait, context: context)
    }
    private var rodSuggestions: [String] {
        AutocompleteService.suggestions(for: .rod, context: context)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: entry.timestamp)
    }

    /// A catch was "during a solunar major/minor" if its timestamp falls
    /// inside any of the parent session's solunar windows.
    private var activeSolunarWindow: String? {
        guard let session = entry.session else { return nil }
        if session.solunarMajors.contains(where: { $0.contains(entry.timestamp) }) {
            return "major"
        }
        if session.solunarMinors.contains(where: { $0.contains(entry.timestamp) }) {
            return "minor"
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                photoHero
                VStack(spacing: 16) {
                    sessionLinkBlock
                    speciesBlock
                    statGrid
                    if isEditing && !videoAssets.isEmpty {
                        mediaBlock
                    }
                    if let window = activeSolunarWindow {
                        solunarCatchBadge(window: window)
                    }
                    mapBlock
                    notesBlock
                    dangerBlock
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(entry.species?.commonName ?? "Catch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .foregroundStyle(Color.sunset)
            }
        }
        .sheet(item: $thumbnailPickerAsset) { asset in
            ThumbnailPickerView(
                assetURL: asset.url,
                initialSeconds: asset.thumbnailTimeSeconds
            ) { chosen in
                asset.thumbnailTimeSeconds = chosen
                try? context.save()
            }
        }
    }

    private var videoAssets: [MediaAsset] {
        entry.media.filter { $0.kind == .video }
    }

    @ViewBuilder
    private var sessionLinkBlock: some View {
        if let session = entry.session {
            NavigationLink(value: session) {
                CozyCard {
                    HStack(spacing: 10) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(Color.sunset)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FROM SESSION")
                                .font(.fieldLabel)
                                .foregroundStyle(Color.inkFaded)
                            Text(session.spot?.name ?? "Session")
                                .font(.cozyBody.weight(.semibold))
                                .foregroundStyle(Color.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.inkFaded)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func solunarCatchBadge(window: String) -> some View {
        CozyCard {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sunset)
                Text("Caught during a solunar \(window)")
                    .font(.cozyBody.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
        }
    }

    private var mediaBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("VIDEO THUMBNAILS")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                ForEach(Array(videoAssets.enumerated()), id: \.element.id) { index, asset in
                    HStack(spacing: 12) {
                        VideoThumbnailView(
                            url: asset.url,
                            atSeconds: asset.thumbnailTimeSeconds,
                            iconSize: .caption,
                            showPlayIcon: false
                        )
                        .frame(width: 72, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Video \(index + 1)")
                                .font(.cozyBody)
                                .foregroundStyle(Color.ink)
                            Text("Thumb at \(formatTimecode(asset.thumbnailTimeSeconds))")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                        }
                        Spacer()
                        Button {
                            thumbnailPickerAsset = asset
                        } label: {
                            Label("Change", systemImage: "slider.horizontal.3")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.sunset))
                        }
                    }
                }
            }
        }
    }

    private func formatTimecode(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var photoHero: some View {
        Group {
            if !entry.media.isEmpty {
                MediaCarousel(assets: sortedMedia, height: 280)
                    .overlay(alignment: .bottom) {
                        TornEdge()
                            .fill(Color.paper)
                            .frame(height: 22)
                    }
            } else {
                ZStack {
                    LinearGradient(colors: [Color.waterLight, Color.waterDeep.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom)
                    FishIcon(commonName: entry.species?.commonName ?? "", size: 80, wiggle: true)
                }
                .frame(height: 200)
                .overlay(alignment: .bottom) {
                    TornEdge().fill(Color.paper).frame(height: 22)
                }
            }
        }
    }

    /// Photos first, then videos — puts stills up front so the gallery opens
    /// on an image rather than a video that might not be ready to play yet.
    private var sortedMedia: [MediaAsset] {
        entry.media.sorted { a, b in
            if a.kind == b.kind { return a.createdAt < b.createdAt }
            return a.kind == .photo
        }
    }

    private var speciesBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                if isEditing {
                    Picker("Species", selection: Binding(
                        get: { entry.species?.id },
                        set: { newID in entry.species = allSpecies.first(where: { $0.id == newID }) }
                    )) {
                        Text("Pick species").tag(UUID?.none)
                        ForEach(allSpecies) { s in
                            Text(s.commonName).tag(Optional(s.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Divider()

                    HStack {
                        Text("WHEN")
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                        Spacer()
                    }
                    DatePicker(
                        "",
                        selection: $entry.timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.sunset)
                } else if let s = entry.species {
                    SpeciesTag(commonName: s.commonName, scientificName: s.scientificName)
                    if !s.speciesDescription.isEmpty {
                        Text(s.speciesDescription)
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                }
                if !isEditing {
                    Text(dateText)
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                }
            }
        }
    }

    private var statGrid: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 14) {
                if isEditing {
                    HStack {
                        Text("Weight").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                        Spacer()
                        TextField("0", value: $entry.weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("lb").foregroundStyle(Color.inkFaded)
                    }
                    Picker("", selection: $entry.isMeasured) {
                        Label("Guessed", systemImage: "questionmark.circle.fill").tag(false)
                        Label("Measured", systemImage: "ruler.fill").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Text("WHO").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                    AutocompleteField(
                        label: "Who caught it?",
                        text: $entry.caughtBy,
                        suggestions: anglerSuggestions,
                        icon: "person.fill"
                    )
                    Text("BAIT").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                    AutocompleteField(
                        label: "Bait",
                        text: $entry.baitUsed,
                        suggestions: baitSuggestions,
                        icon: "ladybug.fill"
                    )
                    Text("ROD").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                    AutocompleteField(
                        label: "Rod",
                        text: $entry.rodUsed,
                        suggestions: rodSuggestions,
                        icon: "fishingrod"
                    )
                } else {
                    HStack {
                        WeightBadge(weight: entry.weight, isMeasured: entry.isMeasured)
                        Spacer()
                    }
                    StatRow(label: "WHO",  value: entry.caughtBy.isEmpty ? "—" : entry.caughtBy, icon: "person.fill")
                    StatRow(label: "BAIT", value: entry.baitUsed.isEmpty ? "—" : entry.baitUsed, icon: "ladybug.fill")
                    StatRow(label: "ROD",  value: entry.rodUsed.isEmpty  ? "—" : entry.rodUsed,  icon: "fishingrod")
                    if let spot = entry.spot {
                        StatRow(label: "SPOT", value: spot.name, icon: "mappin.and.ellipse")
                    }
                }
            }
        }
    }

    private var mapBlock: some View {
        CozyCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DetailMap(coordinate: entry.coordinate)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var notesBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                if isEditing {
                    TextEditor(text: $entry.notes)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color.paper)
                } else {
                    Text(entry.notes.isEmpty ? "No notes." : entry.notes)
                        .font(.cozyBody)
                        .foregroundStyle(entry.notes.isEmpty ? Color.inkFaded : Color.ink)
                }
            }
        }
    }

    private var dangerBlock: some View {
        Group {
            if isEditing {
                Button(role: .destructive) {
                    for asset in entry.media { MediaStore.delete(asset) }
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                } label: {
                    Label("Delete catch", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.inkFaded)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.fieldLabel).foregroundStyle(Color.inkFaded)
                Text(value).font(.cozyBody).foregroundStyle(Color.ink)
            }
            Spacer()
        }
    }
}

private struct DetailMap: View {
    let coordinate: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _camera = State(initialValue: .region(
            MKCoordinateRegion(center: coordinate,
                               span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))
        ))
    }

    var body: some View {
        Map(position: $camera) {
            Annotation("", coordinate: coordinate) { WoodenStake() }
        }
    }
}

/// Irregular bottom edge drawn like a torn paper tear — used on the detail hero image.
struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        let stepCount = 28
        let stepWidth = rect.width / CGFloat(stepCount)
        for i in 0...stepCount {
            let x = CGFloat(i) * stepWidth
            let jitter = (i % 2 == 0) ? rect.midY - 2 : rect.midY + 3
            path.addLine(to: CGPoint(x: x, y: jitter))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Loads an image from disk asynchronously. Previously in DiaryListView, now
/// shared between SessionListView rows and any other catch-surface UI.
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
