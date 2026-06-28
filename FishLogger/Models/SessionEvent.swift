import Foundation
import SwiftData

/// A timestamped signal recorded during a session that isn't itself a catch:
/// a setup change, a sub-spot move, a bite/missed fish, or a free-text note.
///
/// Catches stay their own `Catch` model (authoritative) and are merged into the
/// timeline by timestamp at derivation/export — they are not duplicated here.
@Model
final class SessionEvent {
    var id: UUID
    var timestamp: Date
    var kindRaw: String

    var session: Session?

    /// `.setupChange`: the full resolved setup *after* the change (not a delta),
    /// so coverage derivation is a trivial state walk. JSON-encoded; use
    /// `setupSnapshot` for the typed view.
    var setupSnapshotJSON: String?
    /// `.subSpotChange`: the new micro-location ("by the dam").
    var subSpot: String?
    /// `.bite`: the `BiteOutcome` rawValue.
    var outcomeRaw: String?
    /// `.note` text, or a freeform annotation on any kind.
    var detail: String?
    var latitude: Double?
    var longitude: Double?

    init(
        timestamp: Date = .now,
        kind: SessionEventKind,
        session: Session? = nil,
        setupSnapshot: Setup? = nil,
        subSpot: String? = nil,
        outcome: BiteOutcome? = nil,
        detail: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.session = session
        self.setupSnapshotJSON = setupSnapshot?.jsonString
        self.subSpot = subSpot
        self.outcomeRaw = outcome?.rawValue
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }

    var kind: SessionEventKind { SessionEventKind(rawValue: kindRaw) ?? .note }
    var outcome: BiteOutcome? { outcomeRaw.flatMap(BiteOutcome.init(rawValue:)) }

    /// Typed view over the stored JSON setup snapshot.
    var setupSnapshot: Setup? {
        get { Setup(jsonString: setupSnapshotJSON) }
        set { setupSnapshotJSON = newValue?.jsonString }
    }
}

enum SessionEventKind: String, CaseIterable {
    case setupChange
    case subSpotChange
    case bite
    case note
}

enum BiteOutcome: String, CaseIterable {
    case bite
    case missed
    case blowup
    case follow

    var display: String {
        switch self {
        case .bite:   return "Bite"
        case .missed: return "Missed"
        case .blowup: return "Blowup"
        case .follow: return "Follow"
        }
    }
}
