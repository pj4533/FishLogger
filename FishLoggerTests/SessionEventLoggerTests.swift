import Testing
import Foundation
import SwiftData
@testable import FishLogger

/// Covers the timeline-editing additions to `SessionEventLogger`: keeping a
/// session's live `currentSetup` / `currentSubSpot` consistent with its event
/// chain after a manual edit or delete (the invariant `CoverageDerivation`
/// depends on).
@MainActor
struct SessionEventLoggerTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    /// Builds a session with the given setupChange events inserted, returns the
    /// container (RETAINED by the caller), context, session, and the events.
    private func makeSession(
        setupChanges: [(Double, Setup)] = [],
        subSpotChanges: [(Double, String)] = []
    ) throws -> (ModelContainer, ModelContext, Session, [SessionEvent]) {
        let container = try TestContainer.make()
        let context = container.mainContext
        let session = Session(startedAt: t(0), latitude: 1, longitude: 2)
        context.insert(session)

        var events: [SessionEvent] = []
        for (minutes, setup) in setupChanges {
            let e = SessionEvent(timestamp: t(minutes), kind: .setupChange,
                                 session: session, setupSnapshot: setup)
            context.insert(e)
            events.append(e)
        }
        for (minutes, name) in subSpotChanges {
            let e = SessionEvent(timestamp: t(minutes), kind: .subSpotChange,
                                 session: session, subSpot: name)
            context.insert(e)
            events.append(e)
        }
        return (container, context, session, events)
    }

    @Test
    func deletingLatestSetupChangeRollsBackToPrior() throws {
        let (container, context, session, events) = try makeSession(
            setupChanges: [(10, Setup(lure: "frog")), (20, Setup(lure: "spinnerbait"))]
        )
        _ = container
        session.currentSetup = Setup(lure: "spinnerbait")  // live state before edit

        SessionEventLogger.deleteEvent(events[1], from: session, context: context)

        #expect(session.currentSetup.lure == "frog")
    }

    @Test
    func deletingOnlySetupChangeEmptiesCurrentSetup() throws {
        let (container, context, session, events) = try makeSession(
            setupChanges: [(10, Setup(lure: "frog"))]
        )
        _ = container
        session.currentSetup = Setup(lure: "frog")

        SessionEventLogger.deleteEvent(events[0], from: session, context: context)

        #expect(session.currentSetup.isEmpty)
    }

    @Test
    func deletingMiddleSetupChangeKeepsLatest() throws {
        let (container, context, session, events) = try makeSession(
            setupChanges: [(10, Setup(lure: "frog")),
                           (20, Setup(lure: "worm")),
                           (30, Setup(lure: "jig"))]
        )
        _ = container
        session.currentSetup = Setup(lure: "jig")

        SessionEventLogger.deleteEvent(events[1], from: session, context: context)  // the "worm"

        #expect(session.currentSetup.lure == "jig")
    }

    @Test
    func deletingLatestSubSpotRollsBack() throws {
        let (container, context, session, events) = try makeSession(
            subSpotChanges: [(10, "by the dam"), (20, "north lily pads")]
        )
        _ = container
        session.currentSubSpot = "north lily pads"

        SessionEventLogger.deleteEvent(events[1], from: session, context: context)

        #expect(session.currentSubSpot == "by the dam")
    }

    @Test
    func recomputeAfterEditingLatestSnapshotUpdatesCurrentSetup() throws {
        let (container, _, session, events) = try makeSession(
            setupChanges: [(10, Setup(lure: "frog")), (20, Setup(lure: "spinnerbait"))]
        )
        _ = container

        // Simulate the editor mutating the latest event's snapshot.
        events[1].setupSnapshot = Setup(lure: "chatterbait", color: "white")
        SessionEventLogger.recomputeLiveState(for: session)

        #expect(session.currentSetup.lure == "chatterbait")
        #expect(session.currentSetup.color == "white")
    }

    @Test
    func recomputeIgnoresBiteAndNoteEvents() throws {
        let (container, context, session, events) = try makeSession(
            setupChanges: [(10, Setup(lure: "frog"))]
        )
        _ = container
        let bite = SessionEvent(timestamp: t(40), kind: .bite, session: session, outcome: .missed)
        let note = SessionEvent(timestamp: t(50), kind: .note, session: session, detail: "windy")
        context.insert(bite)
        context.insert(note)

        SessionEventLogger.recomputeLiveState(for: session)

        // Bite/note are later in time but must not clear the setup.
        #expect(session.currentSetup.lure == "frog")
        #expect(session.currentSubSpot.isEmpty)
        // Deleting a non-setup event leaves the setup untouched.
        SessionEventLogger.deleteEvent(events[0], from: session, context: context)
        #expect(session.currentSetup.isEmpty)
    }
}
