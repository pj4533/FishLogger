import Foundation

/// A contiguous stretch of a session during which one setup was fished at one
/// sub-spot, annotated with what it produced. This is how the app captures the
/// *negative* signal the angler never narrates: a setup that caught nothing
/// becomes a `.barren` segment.
struct CoverageSegment: Equatable {
    let start: Date
    let end: Date
    let setup: Setup
    let subSpot: String
    let catchIds: [UUID]
    let biteCount: Int
    let outcome: SegmentOutcome

    var catchCount: Int { catchIds.count }
    var durationSeconds: Double { end.timeIntervalSince(start) }
}

enum SegmentOutcome: String {
    case caught
    case bites
    case barren
}

/// Derives `CoverageSegment`s from a session's event timeline. Pure and
/// SwiftData-free so it's unit-testable without a container (mirrors
/// `SpotClusteringService` / `SessionMigrator`). Never persisted — computed at
/// export time and on demand for UI.
enum CoverageDerivation {

    /// A light, container-free view of a catch for attribution.
    struct CatchPoint {
        let id: UUID
        let timestamp: Date
    }

    /// A light, container-free view of an event boundary/bite.
    struct EventPoint {
        let timestamp: Date
        let kind: SessionEventKind
        /// Full resolved setup after a `.setupChange`.
        let setupSnapshot: Setup?
        /// New micro-location after a `.subSpotChange`.
        let subSpot: String?
    }

    /// Half-open `[start, end)` walk over setup/sub-spot boundaries.
    ///
    /// - `initialSetup`/`initialSubSpot`: the state in effect at `start` (the
    ///   snapshot of the last change at-or-before `start`, else the session's
    ///   current values).
    /// - Catches and bites are attributed by timestamp; an event landing
    ///   exactly on a boundary belongs to the segment *starting* at that
    ///   boundary (a change is narrated before the next cast).
    static func segments(
        start: Date,
        end: Date,
        events: [EventPoint],
        catches: [CatchPoint],
        initialSetup: Setup,
        initialSubSpot: String
    ) -> [CoverageSegment] {
        guard end > start else { return [] }

        // Boundaries: setup/sub-spot changes strictly inside (start, end),
        // sorted and de-duplicated (coincident changes collapse to one).
        let boundaryTimes = events
            .filter { $0.kind == .setupChange || $0.kind == .subSpotChange }
            .map(\.timestamp)
            .filter { $0 > start && $0 < end }
            .sorted()
        var uniqueBoundaries: [Date] = []
        for t in boundaryTimes where uniqueBoundaries.last != t {
            uniqueBoundaries.append(t)
        }

        // Running state begins at the initial values, then folds in any change
        // events at-or-before `start` (so a change exactly at `start` has no
        // leading zero-length segment).
        var runningSetup = initialSetup
        var runningSubSpot = initialSubSpot
        applyChanges(at: start, inclusive: true, before: start, events: events,
                     setup: &runningSetup, subSpot: &runningSubSpot)

        let bites = events.filter { $0.kind == .bite }
        var result: [CoverageSegment] = []
        var segStart = start

        for boundary in uniqueBoundaries {
            result.append(makeSegment(
                start: segStart, end: boundary,
                setup: runningSetup, subSpot: runningSubSpot,
                catches: catches, bites: bites
            ))
            // Apply every change at this boundary before opening the next segment.
            applyChanges(at: boundary, inclusive: true, before: nil, events: events,
                         setup: &runningSetup, subSpot: &runningSubSpot)
            segStart = boundary
        }

        result.append(makeSegment(
            start: segStart, end: end,
            setup: runningSetup, subSpot: runningSubSpot,
            catches: catches, bites: bites
        ))

        return result
    }

    // MARK: - Helpers

    /// Folds change events at time `t` into the running state.
    /// When `before` is non-nil, only events with `timestamp <= before` apply
    /// (used to seed initial state from changes at-or-before `start`).
    private static func applyChanges(
        at t: Date,
        inclusive: Bool,
        before: Date?,
        events: [EventPoint],
        setup: inout Setup,
        subSpot: inout String
    ) {
        let relevant = events
            .filter { $0.kind == .setupChange || $0.kind == .subSpotChange }
            .filter { e in
                if let before { return e.timestamp <= before }
                return e.timestamp == t
            }
            .sorted { $0.timestamp < $1.timestamp }
        for e in relevant {
            if e.kind == .setupChange, let s = e.setupSnapshot { setup = s }
            if e.kind == .subSpotChange, let sub = e.subSpot { subSpot = sub }
        }
    }

    // MARK: - Session bridge

    /// Convenience overload that derives a session's segments from its stored
    /// events and catches. `now` terminates the open final segment of an
    /// ongoing session (defaults to `session.effectiveEnd`).
    static func segments(for session: Session, now: Date? = nil) -> [CoverageSegment] {
        let end = now ?? session.effectiveEnd
        let start = session.startedAt

        let events = session.events.map { e in
            EventPoint(timestamp: e.timestamp, kind: e.kind,
                       setupSnapshot: e.setupSnapshot, subSpot: e.subSpot)
        }
        let catches = session.catches.map { CatchPoint(id: $0.id, timestamp: $0.timestamp) }

        // Initial state, per dimension. If a dimension has change events, the
        // segment before its first change is genuinely "unknown" (empty) — the
        // live current value only applies pre-start changes, which `segments`
        // folds in. If a dimension has NO change events at all, the session's
        // live value applies for the whole span (setup configured without
        // emitting events, e.g. legacy/manual sessions).
        let hasSetupChange = session.events.contains { $0.kind == .setupChange }
        let hasSubSpotChange = session.events.contains { $0.kind == .subSpotChange }
        let initialSetup = hasSetupChange ? Setup() : session.currentSetup
        let initialSubSpot = hasSubSpotChange ? "" : session.currentSubSpot

        return segments(
            start: start, end: end,
            events: events, catches: catches,
            initialSetup: initialSetup, initialSubSpot: initialSubSpot
        )
    }

    private static func makeSegment(
        start: Date,
        end: Date,
        setup: Setup,
        subSpot: String,
        catches: [CatchPoint],
        bites: [EventPoint]
    ) -> CoverageSegment {
        // Half-open [start, end): an event exactly on the end boundary belongs
        // to the next segment.
        let segCatches = catches
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.id)
        let biteCount = bites.filter { $0.timestamp >= start && $0.timestamp < end }.count
        let outcome: SegmentOutcome = !segCatches.isEmpty ? .caught
            : biteCount > 0 ? .bites : .barren
        return CoverageSegment(
            start: start, end: end,
            setup: setup, subSpot: subSpot,
            catchIds: segCatches, biteCount: biteCount, outcome: outcome
        )
    }
}
