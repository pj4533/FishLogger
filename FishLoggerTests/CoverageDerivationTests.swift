import Testing
import Foundation
import SwiftData
@testable import FishLogger

struct CoverageDerivationTests {

    // Base time + minute offsets for readable timelines.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func setupChange(_ minutes: Double, _ setup: Setup) -> CoverageDerivation.EventPoint {
        .init(timestamp: t(minutes), kind: .setupChange, setupSnapshot: setup, subSpot: nil)
    }
    private func subSpotChange(_ minutes: Double, _ name: String) -> CoverageDerivation.EventPoint {
        .init(timestamp: t(minutes), kind: .subSpotChange, setupSnapshot: nil, subSpot: name)
    }
    private func bite(_ minutes: Double) -> CoverageDerivation.EventPoint {
        .init(timestamp: t(minutes), kind: .bite, setupSnapshot: nil, subSpot: nil)
    }
    private func catchAt(_ minutes: Double) -> CoverageDerivation.CatchPoint {
        .init(id: UUID(), timestamp: t(minutes))
    }

    private func segs(
        _ end: Double,
        events: [CoverageDerivation.EventPoint] = [],
        catches: [CoverageDerivation.CatchPoint] = [],
        initialSetup: Setup = Setup(),
        initialSubSpot: String = ""
    ) -> [CoverageSegment] {
        CoverageDerivation.segments(
            start: t(0), end: t(end),
            events: events, catches: catches,
            initialSetup: initialSetup, initialSubSpot: initialSubSpot
        )
    }

    @Test
    func noEventsProducesSingleFullSpanSegment() {
        let c = catchAt(30)
        let result = segs(60, catches: [c], initialSetup: Setup(lure: "frog"))
        #expect(result.count == 1)
        #expect(result[0].start == t(0))
        #expect(result[0].end == t(60))
        #expect(result[0].setup.lure == "frog")
        #expect(result[0].catchIds == [c.id])
        #expect(result[0].outcome == .caught)
    }

    @Test
    func singleSetupChangeSplitsAndAttributesCatchesToCorrectSetup() {
        let early = catchAt(10)   // before change → frog
        let late = catchAt(40)    // after change → spinnerbait
        let result = segs(
            60,
            events: [setupChange(30, Setup(lure: "spinnerbait"))],
            catches: [early, late],
            initialSetup: Setup(lure: "frog")
        )
        #expect(result.count == 2)
        #expect(result[0].setup.lure == "frog")
        #expect(result[0].catchIds == [early.id])
        #expect(result[1].setup.lure == "spinnerbait")
        #expect(result[1].catchIds == [late.id])
    }

    @Test
    func setupChangeWithNoActionIsBarren() {
        let result = segs(
            60,
            events: [setupChange(30, Setup(lure: "spinnerbait"))],
            initialSetup: Setup(lure: "frog")
        )
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.outcome == .barren })
    }

    @Test
    func biteOnlySegmentIsBites() {
        let result = segs(60, events: [bite(20)], initialSetup: Setup(lure: "frog"))
        #expect(result.count == 1)
        #expect(result[0].outcome == .bites)
        #expect(result[0].biteCount == 1)
    }

    @Test
    func coincidentSetupAndSubSpotChangeFormOneBoundary() {
        let result = segs(
            60,
            events: [setupChange(30, Setup(lure: "jig")), subSpotChange(30, "by the dam")],
            initialSetup: Setup(lure: "frog"),
            initialSubSpot: "north bank"
        )
        #expect(result.count == 2)
        #expect(result[0].subSpot == "north bank")
        #expect(result[1].setup.lure == "jig")
        #expect(result[1].subSpot == "by the dam")
        // No zero-length segment.
        #expect(result.allSatisfy { $0.durationSeconds > 0 })
    }

    @Test
    func changeExactlyAtStartHasNoLeadingEmptySegment() {
        let result = segs(
            60,
            events: [setupChange(0, Setup(lure: "frog"))],
            initialSetup: Setup()
        )
        #expect(result.count == 1)
        #expect(result[0].setup.lure == "frog")
        #expect(result[0].start == t(0))
    }

    @Test
    func catchExactlyOnBoundaryAttributedToNewSegment() {
        let onBoundary = catchAt(30)
        let result = segs(
            60,
            events: [setupChange(30, Setup(lure: "spinnerbait"))],
            catches: [onBoundary],
            initialSetup: Setup(lure: "frog")
        )
        #expect(result[0].catchIds.isEmpty)             // frog segment empty
        #expect(result[1].catchIds == [onBoundary.id])  // spinnerbait segment
    }

    @Test
    func multipleChangesProduceNPlusOneSegmentsAndDurationsSum() {
        let result = segs(
            90,
            events: [
                setupChange(30, Setup(lure: "a")),
                setupChange(60, Setup(lure: "b"))
            ],
            initialSetup: Setup(lure: "start")
        )
        #expect(result.count == 3)
        let total = result.reduce(0.0) { $0 + $1.durationSeconds }
        #expect(total == 90 * 60)
    }

    @Test
    func emptyWhenEndNotAfterStart() {
        let result = segs(0)
        #expect(result.isEmpty)
    }

    // MARK: - Session bridge

    @MainActor
    @Test
    func sessionBridgeWithNoSetupChangeUsesCurrentSetupForWholeSpan() throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        let session = Session(startedAt: t(0), endedAt: t(60), latitude: 0, longitude: 0)
        session.currentSetup = Setup(lure: "frog")
        context.insert(session)

        let result = CoverageDerivation.segments(for: session, now: t(60))
        #expect(result.count == 1)
        #expect(result[0].setup.lure == "frog")
        #expect(result[0].outcome == .barren)
    }

    @MainActor
    @Test
    func sessionBridgeOngoingUsesInjectedNowForFinalSegment() throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        let session = Session(startedAt: t(0), endedAt: nil, latitude: 0, longitude: 0)
        context.insert(session)
        SessionEventLogger.changeSetup(Setup(lure: "frog"), on: session, at: t(20), context: context)

        let result = CoverageDerivation.segments(for: session, now: t(50))
        #expect(result.count == 2)
        #expect(result.last?.end == t(50))
        // Pre-first-change segment is unknown (empty) setup, not the current one.
        #expect(result[0].setup.isEmpty)
        #expect(result[1].setup.lure == "frog")
    }
}
