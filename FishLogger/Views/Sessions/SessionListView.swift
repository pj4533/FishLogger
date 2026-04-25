import SwiftUI
import SwiftData
import MapKit

struct SessionListView: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var showingNew = false
    @State private var showingAddCatch = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                EmptyState(
                    symbol: "fish",
                    title: "No sessions yet",
                    message: "Tap the + to log your first outing — fish or no fish."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
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
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNew = true
                    } label: {
                        Label("Start session", systemImage: "play.circle.fill")
                    }
                    Button {
                        showingAddCatch = true
                    } label: {
                        Label("Add catch", systemImage: "fish.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.sunset)
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            NewSessionSheet()
        }
        .sheet(isPresented: $showingAddCatch) {
            AddCatchSheet()
        }
        .navigationDestination(for: Session.self) { session in
            SessionDetailView(session: session)
        }
        .navigationDestination(for: Catch.self) { entry in
            CatchDetailView(entry: entry)
        }
        .background(Color.paper.ignoresSafeArea())
    }
}

private struct SessionRow: View {
    let session: Session

    private var dateRangeText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let day = f.string(from: session.startedAt).uppercased()

        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        let start = t.string(from: session.startedAt)
        if let end = session.endedAt {
            let sameDay = Calendar.current.isDate(session.startedAt, inSameDayAs: end)
            if sameDay {
                return "\(day) · \(start) – \(t.string(from: end))"
            }
            return "\(day) · \(start) – \(f.string(from: end)), \(t.string(from: end))"
        }
        return "\(day) · \(start) · ongoing"
    }

    private var durationText: String {
        let mins = Int(session.duration / 60)
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var weatherSummary: String? {
        guard session.conditionsFetchedAt != nil else { return nil }
        var parts: [String] = []
        if let c = session.airTempC {
            let f = Int((c * 9 / 5 + 32).rounded())
            parts.append("\(f)°F")
        }
        if let wind = session.windSpeedKmh {
            parts.append("\(Int(wind.rounded())) km/h")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var biggestCatch: Catch? {
        session.catches.max { ($0.weight) < ($1.weight) }
    }

    var body: some View {
        CozyCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let symbol = session.conditionSymbol {
                            Image(systemName: symbol)
                                .font(.title3)
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
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    HStack(spacing: 12) {
                        Label(durationText, systemImage: "clock")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                        Label("\(session.catches.count) \(session.catches.count == 1 ? "catch" : "catches")",
                              systemImage: "fish")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                        if let summary = weatherSummary {
                            Text(summary)
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                        }
                    }
                    if let big = biggestCatch, let s = big.species {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(Color.sunset)
                            Text("\(s.commonName) · ")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.ink)
                            + Text(String(format: "%.1f lb", big.weight))
                                .font(.cozyCaption.weight(.semibold))
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
                Spacer()
                MiniMapThumb(coordinate: session.coordinate)
                    .frame(width: 60, height: 60)
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
