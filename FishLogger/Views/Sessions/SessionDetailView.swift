import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct SessionDetailView: View {
    @Bindable var session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var tab: DetailTab = .overview

    private enum DetailTab: Hashable { case overview, timeline }

    private var anglerSuggestions: [String] {
        AutocompleteService.suggestions(for: .angler, context: context)
    }

    private static let significantTimeDelta: TimeInterval = 30 * 60
    private static let significantLocationDelta: CLLocationDistance = 500

    private var dateRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let start = f.string(from: session.startedAt)
        if let end = session.endedAt {
            let t = DateFormatter()
            t.dateFormat = Calendar.current.isDate(session.startedAt, inSameDayAs: end) ? "h:mm a" : "MMM d, h:mm a"
            return "\(start) – \(t.string(from: end))"
        }
        return "\(start) · ongoing"
    }

    private var durationText: String {
        let mins = Int(session.duration / 60)
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerBlock
                Picker("", selection: $tab) {
                    Text("Overview").tag(DetailTab.overview)
                    Text("Timeline").tag(DetailTab.timeline)
                }
                .pickerStyle(.segmented)

                switch tab {
                case .overview: overviewContent
                case .timeline: SessionTimelineView(session: session)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle(session.spot?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if session.isOngoing {
                        Button {
                            session.endedAt = .now
                            try? context.save()
                        } label: {
                            Label("End session", systemImage: "flag.checkered")
                        }
                    }
                    Button {
                        isEditing.toggle()
                    } label: {
                        Label(isEditing ? "Done editing" : "Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.sunset)
                }
            }
        }
        .confirmationDialog(
            "Delete this session and all its catches?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                for c in session.catches {
                    for asset in c.media { MediaStore.delete(asset) }
                }
                context.delete(session)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if session.isOngoing {
            AssistantPanel(session: session)
        }
        if isEditing {
            editBlock
        }
        ConditionsSessionCard(session: session)
        notesBlock
        if isEditing {
            dangerBlock
        }
    }

    private var headerBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let symbol = session.conditionSymbol {
                        Image(systemName: symbol)
                            .font(.title2)
                            .foregroundStyle(Color.sunset)
                    }
                    Text(session.spot?.name ?? "Unassigned spot")
                        .font(.diaryHeader)
                        .foregroundStyle(Color.ink)
                    if session.isOngoing {
                        Text("ONGOING")
                            .font(.fieldLabel)
                            .foregroundStyle(Color.paper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.sunset))
                    }
                }
                Text(dateRangeText)
                    .font(.cozyBody)
                    .foregroundStyle(Color.ink)
                HStack(spacing: 16) {
                    Label(durationText, systemImage: "clock")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                    Label("\(session.catches.count) \(session.catches.count == 1 ? "catch" : "catches")",
                          systemImage: "fish")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
                SessionMap(coordinate: session.coordinate)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var editBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("EDIT")
                    .font(.fieldLabel)
                    .foregroundStyle(Color.inkFaded)

                Text("STARTED AT").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { session.startedAt },
                        set: { newVal in
                            let delta = abs(newVal.timeIntervalSince(session.startedAt))
                            session.startedAt = newVal
                            if delta > Self.significantTimeDelta {
                                ConditionsBackfillService.shared.markStale(session)
                            }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.sunset)

                Text("ENDED AT").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                Toggle("Ongoing", isOn: Binding(
                    get: { session.endedAt == nil },
                    set: { isOngoing in
                        session.endedAt = isOngoing ? nil : .now
                    }
                ))
                .tint(Color.sunset)
                if let endedAt = session.endedAt {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { endedAt },
                            set: { session.endedAt = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.sunset)
                }

                Text("ANGLER").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                AutocompleteField(
                    label: "Who's fishing this session?",
                    text: $session.currentAngler,
                    suggestions: anglerSuggestions,
                    icon: "person.fill"
                )
            }
        }
    }

    private var notesBlock: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                if isEditing {
                    TextEditor(text: $session.notes)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color.paper)
                } else {
                    Text(session.notes.isEmpty ? "No notes." : session.notes)
                        .font(.cozyBody)
                        .foregroundStyle(session.notes.isEmpty ? Color.inkFaded : Color.ink)
                }
            }
        }
    }

    private var dangerBlock: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete session", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

private struct SessionMap: View {
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
        Map(position: $camera, interactionModes: []) {
            Annotation("", coordinate: coordinate) { WoodenStake() }
        }
    }
}
