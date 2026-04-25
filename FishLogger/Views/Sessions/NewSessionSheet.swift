import SwiftUI
import SwiftData
import CoreLocation
import MapKit

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt: Date = .now
    @State private var location: CLLocationCoordinate2D?
    @State private var locationAccuracy: Double?
    @State private var notes: String = ""
    @State private var lastError: String?
    @State private var isLocationRequesting = false
    @State private var isSaving = false
    @State private var autoEndedMessage: String?

    @State private var locationService = LocationService()

    @Query private var sessions: [Session]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let autoEndedMessage {
                        CozyCard {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.sunset)
                                Text(autoEndedMessage)
                                    .font(.cozyCaption)
                                    .foregroundStyle(Color.ink)
                            }
                        }
                    }

                    whenSection
                    locationSection
                    notesSection

                    if let lastError {
                        Text(lastError)
                            .font(.cozyCaption)
                            .foregroundStyle(Color.sunset)
                            .multilineTextAlignment(.center)
                    }
                    saveButton.padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.paper)
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .task { await autoEndOngoingAndFetchLocation() }
        }
    }

    private var whenSection: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("STARTED AT")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)
                DatePicker(
                    "",
                    selection: $startedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.sunset)
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
                    Spacer()
                    if isLocationRequesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await requestLocation(force: true) }
                        } label: {
                            Label("Use GPS", systemImage: "location.circle.fill")
                                .font(.cozyCaption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.sunset)
                    }
                }
                if let coord = location {
                    LocationPreviewMap(coordinate: coord)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Text("Waiting for GPS…")
                        .font(.cozyBody)
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
                TextEditor(text: $notes)
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
                Text("Start fishing")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(location != nil ? Color.sunset : Color.sunset.opacity(0.4))
            )
        }
        .disabled(location == nil || isSaving)
    }

    private func autoEndOngoingAndFetchLocation() async {
        // Auto-end any session that's still marked ongoing. Prevents "forgot to
        // tap End session yesterday, starting a new one today" from stacking
        // two ongoing sessions.
        let ongoing = sessions.filter { $0.endedAt == nil }
        if !ongoing.isEmpty {
            for s in ongoing {
                let lastCatch = s.catches.map(\.timestamp).max()
                s.endedAt = max(lastCatch ?? s.startedAt, s.startedAt.addingTimeInterval(3600))
            }
            try? context.save()
            autoEndedMessage = ongoing.count == 1
                ? "Ended previous session."
                : "Ended \(ongoing.count) previous sessions."
        }

        await requestLocation(force: false)
    }

    private func requestLocation(force: Bool) async {
        if !force, location != nil { return }
        isLocationRequesting = true
        defer { isLocationRequesting = false }
        do {
            let loc = try await locationService.requestCurrentLocation()
            location = loc.coordinate
            locationAccuracy = loc.horizontalAccuracy
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Couldn't get location."
        }
    }

    private func save() async {
        guard let coord = location else { return }
        isSaving = true
        defer { isSaving = false }

        let session = Session(
            startedAt: startedAt,
            endedAt: nil,
            latitude: coord.latitude,
            longitude: coord.longitude,
            notes: notes
        )
        context.insert(session)
        _ = SpotClusteringService.assignSpot(for: session, in: context)

        do {
            try context.save()
            // Fire-and-forget conditions fetch. Failures are logged on the
            // session and retried next launch.
            Task { @MainActor in
                do {
                    try await ConditionsBackfillService.shared.backfillOne(
                        session,
                        weather: WeatherService.shared
                    )
                    try? context.save()
                } catch {
                    session.conditionsFetchFailureCount += 1
                    session.conditionsFetchAttemptAt = .now
                    try? context.save()
                }
            }
            dismiss()
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
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
