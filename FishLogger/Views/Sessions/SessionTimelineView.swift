import SwiftUI
import SwiftData

/// The session's chronological, fully-editable record: every `SessionEvent`
/// (setup change, sub-spot, bite, note) and every `Catch`, merged by time on a
/// single "fishing line" running top to bottom. Tapping an event opens the
/// editor; tapping a catch pushes its detail. "Add to timeline" gives manual
/// parity with everything the voice assistant can log.
struct SessionTimelineView: View {
    let session: Session

    @Environment(\.modelContext) private var context
    @State private var editor: EditorPresentation?
    @State private var showingAddCatch = false

    var body: some View {
        VStack(spacing: 16) {
            CozyCard {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TimelineRow(
                                item: item,
                                isFirst: index == 0,
                                isLast: index == items.count - 1,
                                onSelectEvent: { editor = EditorPresentation(mode: .edit($0)) }
                            )
                        }
                    }
                }
            }
        }
        .sheet(item: $editor) { presentation in
            EventEditorSheet(session: session, mode: presentation.mode)
        }
        .sheet(isPresented: $showingAddCatch) {
            AddCatchSheet()
        }
    }

    private var header: some View {
        HStack {
            Text("TIMELINE")
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
            Spacer()
            Menu {
                Button { editor = EditorPresentation(mode: .add(.setupChange)) } label: {
                    Label("Setup change", systemImage: "fishingrod")
                }
                Button { editor = EditorPresentation(mode: .add(.subSpotChange)) } label: {
                    Label("Sub-spot", systemImage: "mappin")
                }
                Button { editor = EditorPresentation(mode: .add(.bite)) } label: {
                    Label("Bite", systemImage: "drop.triangle")
                }
                Button { editor = EditorPresentation(mode: .add(.note)) } label: {
                    Label("Note", systemImage: "text.quote")
                }
                Divider()
                Button { showingAddCatch = true } label: {
                    Label("Catch", systemImage: "fish.fill")
                }
            } label: {
                Label("Add to timeline", systemImage: "plus.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.sunset)
            }
        }
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        Text("Nothing logged yet. Talk to the fishing buddy, or tap “Add to timeline” to record a setup, bite, note, or catch.")
            .font(.cozyCaption)
            .foregroundStyle(Color.inkFaded)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    /// Events + catches merged and sorted ascending by time. Same-timestamp ties
    /// keep a stable order (events before catches) so the line doesn't reshuffle.
    private var items: [TimelineItem] {
        let events = session.events.map { TimelineItem.event($0) }
        let catches = session.catches.map { TimelineItem.catchEntry($0) }
        return (events + catches).sorted { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.sortRank < b.sortRank
        }
    }
}

// MARK: - Item model

enum TimelineItem: Identifiable {
    case event(SessionEvent)
    case catchEntry(Catch)

    var id: String {
        switch self {
        case let .event(e):      return "e-\(e.id.uuidString)"
        case let .catchEntry(c): return "c-\(c.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case let .event(e):      return e.timestamp
        case let .catchEntry(c): return c.timestamp
        }
    }

    /// Tiebreak for identical timestamps: events render above catches.
    var sortRank: Int {
        switch self {
        case .event:      return 0
        case .catchEntry: return 1
        }
    }
}

// MARK: - Row

private struct TimelineRow: View {
    let item: TimelineItem
    let isFirst: Bool
    let isLast: Bool
    let onSelectEvent: (SessionEvent) -> Void

    var body: some View {
        switch item {
        case let .event(event):
            Button { onSelectEvent(event) } label: { rowBody }
                .buttonStyle(.plain)
        case let .catchEntry(entry):
            NavigationLink(value: entry) { rowBody }
                .buttonStyle(.plain)
        }
    }

    private var rowBody: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(timeText)
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
                .frame(width: 56, alignment: .trailing)

            spine

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.inkFaded.opacity(0.6))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// The continuous "fishing line" with this item's node centered on it.
    private var spine: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : lineColor)
                Rectangle().fill(isLast ? Color.clear : lineColor)
            }
            .frame(width: 1.5)

            Circle()
                .fill(nodeColor)
                .frame(width: nodeSize, height: nodeSize)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: isCatch ? 15 : 12, weight: .bold))
                        .foregroundStyle(Color.white)
                )
                .overlay(
                    Circle().stroke(Color.paperDeep, lineWidth: 2)
                )
        }
        .frame(width: 34)
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .event(event):
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle(event))
                    .font(.cozyBody)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let detail = eventDetail(event) {
                    Text(detail)
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                        .lineLimit(2)
                }
            }
        case let .catchEntry(entry):
            CatchTimelineContent(entry: entry)
        }
    }

    // MARK: Presentation

    private var lineColor: Color { Color.bark.opacity(0.35) }
    private var nodeSize: CGFloat { isCatch ? 30 : 26 }

    private var isCatch: Bool {
        if case .catchEntry = item { return true }
        return false
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: item.timestamp)
    }

    private var symbol: String {
        switch item {
        case let .event(e):
            switch e.kind {
            case .setupChange:   return "fishingrod"
            case .subSpotChange: return "mappin"
            case .bite:          return "drop.triangle"
            case .note:          return "text.quote"
            }
        case .catchEntry:
            return "fish.fill"
        }
    }

    private var nodeColor: Color {
        switch item {
        case let .event(e):
            switch e.kind {
            case .setupChange:   return Color.waterDeep
            case .subSpotChange: return Color.moss
            case .bite:          return Color.sunset
            case .note:          return Color.bark
            }
        case .catchEntry:
            return Color.sunset
        }
    }

    private func eventTitle(_ event: SessionEvent) -> String {
        switch event.kind {
        case .setupChange:
            let s = SessionEventLogger.summary(of: event.setupSnapshot ?? Setup())
            return s.isEmpty ? "Setup cleared" : s
        case .subSpotChange:
            let loc = event.subSpot ?? ""
            return loc.isEmpty ? "Sub-spot cleared" : "Now at \(loc)"
        case .bite:
            return event.outcome?.display ?? "Bite"
        case .note:
            let text = event.detail ?? ""
            return text.isEmpty ? "Note" : text
        }
    }

    private func eventDetail(_ event: SessionEvent) -> String? {
        switch event.kind {
        case .bite:
            let d = event.detail ?? ""
            return d.isEmpty ? nil : d
        case .setupChange, .subSpotChange, .note:
            return nil
        }
    }
}

/// Compact catch row for the timeline — species, weight, and who. Time lives in
/// the gutter, so unlike the old catches list this row doesn't repeat it.
private struct CatchTimelineContent: View {
    let entry: Catch

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                if let s = entry.species {
                    SpeciesTag(commonName: s.commonName, scientificName: s.scientificName, compact: true)
                } else {
                    Text("Catch").font(.cozyBody).foregroundStyle(Color.ink)
                }
                HStack(spacing: 8) {
                    WeightBadge(weight: entry.weight, isMeasured: entry.isMeasured)
                    if !entry.caughtBy.isEmpty {
                        Label(entry.caughtBy, systemImage: "person.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.fieldLabel)
                            .foregroundStyle(Color.inkFaded)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo = entry.media.first(where: { $0.kind == .photo }) {
            AsyncImageFromURL(url: photo.url)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if let video = entry.media.first(where: { $0.kind == .video }) {
            VideoThumbnailView(url: video.url, atSeconds: video.thumbnailTimeSeconds)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// Identifiable wrapper so a single `.sheet(item:)` can present add and edit.
struct EditorPresentation: Identifiable {
    let id = UUID()
    let mode: EventEditorSheet.Mode
}
