import SwiftUI
import SwiftData
import PhotosUI
import MapKit
import CoreLocation

/// Log a catch independently of any session lifecycle. Catches auto-attach
/// to whichever session covers their timestamp on save. Timestamp prefers
/// photo EXIF, then manual entry, then "now".
struct AddCatchSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var form = CatchFormState()
    @State private var location = LocationService()
    @State private var isSaving = false
    @State private var showSavedRipple = false

    @Query(sort: \Species.sortOrder) private var allSpecies: [Species]

    private var baitSuggestions: [String] {
        AutocompleteService.suggestions(for: .bait, context: context)
    }
    private var rodSuggestions: [String] {
        AutocompleteService.suggestions(for: .rod, context: context)
    }
    private var anglerSuggestions: [String] {
        AutocompleteService.suggestions(for: .angler, context: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoSection
                    speciesSection
                    whenSection
                    whoSection
                    weightSection
                    baitSection
                    rodSection
                    locationSection
                    notesSection
                    if let error = form.lastError {
                        Text(error)
                            .font(.cozyCaption)
                            .foregroundStyle(Color.sunset)
                            .multilineTextAlignment(.center)
                    }
                    saveButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.paper)
            .navigationTitle("New Catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // reserved for future dictation mode
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                    .disabled(true)
                    .help("Dictation coming soon")
                }
            }
            .task { await requestLocationIfNeeded() }
            .onChange(of: form.pickedMedia) { _, newItems in
                Task { await extractMetadataFromFirstPhoto(newItems) }
            }
        }
    }

    private var photoSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("PHOTOS")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)

                PhotosPicker(
                    selection: $form.pickedMedia,
                    maxSelectionCount: 6,
                    matching: .any(of: [.images, .videos])
                ) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text(form.pickedMedia.isEmpty ? "Add photos or video" : "\(form.pickedMedia.count) selected")
                            .font(.cozyBody)
                    }
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.waterLight.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.bark.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                }
            }
        }
    }

    private var whenSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("WHEN")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    Spacer()
                    if form.timestampSource == .photo {
                        SourceBadge(icon: "camera.fill", label: "from photo")
                    }
                }
                DatePicker(
                    "",
                    selection: Binding(
                        get: { form.timestamp },
                        set: {
                            form.timestamp = $0
                            form.userEditedTimestamp = true
                            form.timestampSource = .manual
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.sunset)
            }
        }
    }

    private var speciesSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("SPECIES")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                Menu {
                    ForEach(allSpecies) { species in
                        Button {
                            form.species = species
                        } label: {
                            Text("\(species.commonName) — \(species.scientificName)")
                        }
                    }
                } label: {
                    HStack {
                        if let s = form.species {
                            SpeciesTag(commonName: s.commonName, scientificName: s.scientificName, compact: true)
                        } else {
                            Text("Tap to pick a species")
                                .font(.cozyBody)
                                .foregroundStyle(Color.inkFaded)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(Color.inkFaded)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var whoSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHO")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                AutocompleteField(
                    label: "Who caught it?",
                    text: $form.caughtBy,
                    suggestions: anglerSuggestions,
                    icon: "person.fill"
                )
            }
        }
    }

    private var weightSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("WEIGHT")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                HStack(spacing: 10) {
                    TextField("0.0", text: $form.weightText)
                        .keyboardType(.decimalPad)
                        .font(.statValue)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: 100)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .background(Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
                        )
                    Text("lb")
                        .font(.diaryHeader)
                        .foregroundStyle(Color.inkFaded)
                    Spacer()
                }
                Picker("", selection: $form.isMeasured) {
                    Label("Guessed", systemImage: "questionmark.circle.fill").tag(false)
                    Label("Measured", systemImage: "ruler.fill").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var baitSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("BAIT")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                AutocompleteField(
                    label: "e.g. spinnerbait, nightcrawler",
                    text: $form.baitUsed,
                    suggestions: baitSuggestions,
                    icon: "ladybug.fill"
                )
            }
        }
    }

    private var rodSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ROD")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                AutocompleteField(
                    label: "e.g. Ugly Stik 6'6",
                    text: $form.rodUsed,
                    suggestions: rodSuggestions,
                    icon: "fishingrod"
                )
            }
        }
    }

    private var locationSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LOCATION")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    if form.locationSource == .photo {
                        SourceBadge(icon: "camera.fill", label: "from photo")
                    }
                    Spacer()
                    if form.isLocationRequesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await requestLocationIfNeeded(force: true) }
                        } label: {
                            Label("Use GPS", systemImage: "location.circle.fill")
                                .font(.cozyCaption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.sunset)
                    }
                }
                if let coord = form.location {
                    LocationPreviewMap(coordinate: coord)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Text("No location yet — auto-fills from photo or GPS, otherwise inherits from the matching session.")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var notesSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("NOTES")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                TextEditor(text: $form.notes)
                    .font(.cozyBody)
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.bark.opacity(0.4), lineWidth: 1.5)
                    )
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "fish.fill")
                    .symbolEffect(.bounce, value: showSavedRipple)
                Text("Log this catch")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(canSave ? Color.sunset : Color.sunset.opacity(0.4))
            )
        }
        .disabled(!canSave || isSaving)
        .sensoryFeedback(.success, trigger: showSavedRipple)
    }

    private var canSave: Bool {
        form.species != nil && form.weightValue >= 0
    }

    // MARK: - Actions

    private func requestLocationIfNeeded(force: Bool = false) async {
        if !force && form.location != nil { return }
        form.isLocationRequesting = true
        defer { form.isLocationRequesting = false }
        do {
            let loc = try await location.requestCurrentLocation()
            form.location = loc.coordinate
            form.locationAccuracy = loc.horizontalAccuracy
            form.locationSource = force ? .manual : .gps
            if force { form.userEditedLocation = true }
        } catch {
            // Silent — location is optional now; on save we fall back to the
            // matching session's coordinate.
        }
    }

    private func extractMetadataFromFirstPhoto(_ items: [PhotosPickerItem]) async {
        guard let first = items.first else { return }
        guard let meta = await PhotoMetadataExtractor.extract(from: first) else { return }
        // Photo EXIF wins over the .now default. No clamping — if the photo
        // was taken yesterday, the catch will auto-attach to yesterday's
        // session on save.
        if let captured = meta.capturedAt, !form.userEditedTimestamp {
            form.timestamp = captured
            form.timestampSource = .photo
        }
        if let coord = meta.coordinate, !form.userEditedLocation {
            form.location = coord
            form.locationSource = .photo
        }
    }

    /// Find the session whose [startedAt, endedAt ?? .now] range contains the
    /// given timestamp. If multiple match (rare — overlapping sessions), prefer
    /// the most recently started.
    private func findMatchingSession(for timestamp: Date) -> Session? {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let sessions = try? context.fetch(descriptor) else { return nil }
        return sessions.first { session in
            guard timestamp >= session.startedAt else { return false }
            let upper = session.endedAt ?? .now
            return timestamp <= upper
        }
    }

    private func save() async {
        guard let species = form.species else { return }
        isSaving = true
        defer { isSaving = false }

        guard let matchedSession = findMatchingSession(for: form.timestamp) else {
            form.lastError = "No session covers this time. Start a session that includes \(form.timestamp.formatted(date: .abbreviated, time: .shortened)), or pick a different time."
            return
        }

        let coord = form.location ?? matchedSession.coordinate

        let newCatch = Catch(
            timestamp: form.timestamp,
            latitude: coord.latitude,
            longitude: coord.longitude,
            weight: form.weightValue,
            isMeasured: form.isMeasured,
            baitUsed: form.baitUsed.trimmingCharacters(in: .whitespacesAndNewlines),
            rodUsed: form.rodUsed.trimmingCharacters(in: .whitespacesAndNewlines),
            caughtBy: form.caughtBy.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: form.notes,
            species: species,
            session: matchedSession
        )
        context.insert(newCatch)

        for item in form.pickedMedia {
            if let asset = try? await MediaStore.save(item) {
                context.insert(asset)
                asset.owner = newCatch
                newCatch.media.append(asset)
            }
        }

        do {
            try context.save()
            showSavedRipple.toggle()
            dismiss()
        } catch {
            form.lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

private struct LocationPreviewMap: View {
    let coordinate: CLLocationCoordinate2D

    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        ))
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            Annotation("", coordinate: coordinate) {
                WoodenStake()
            }
        }
    }
}
