import Testing
import Foundation
import SwiftData
@testable import FishLogger

@MainActor
struct AssistantToolDispatchTests {

    // Retain the container — a context whose container has deallocated crashes.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try TestContainer.make()
        return (container, container.mainContext)
    }

    private func makeSession(_ context: ModelContext) -> Session {
        let s = Session(latitude: 41.5, longitude: -73.9)
        context.insert(s)
        return s
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func updateSetupMergesAndEmitsEvent() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)

        let r1 = AssistantTools.dispatch(name: "update_setup",
            argsJSON: #"{"rod":null,"reel":null,"line":null,"lure":"hollow body frog","color":"black","technique":"topwater"}"#,
            session: session, context: context, now: now)
        #expect(r1.ok)
        #expect(session.currentSetup.lure == "hollow body frog")
        #expect(session.currentSetup.color == "black")

        // Incremental: only change lure, keep color.
        let r2 = AssistantTools.dispatch(name: "update_setup",
            argsJSON: #"{"rod":null,"reel":null,"line":null,"lure":"spinnerbait","color":null,"technique":null}"#,
            session: session, context: context, now: now)
        #expect(r2.ok)
        #expect(session.currentSetup.lure == "spinnerbait")
        #expect(session.currentSetup.color == "black")
        #expect(session.events.filter { $0.kind == .setupChange }.count == 2)
    }

    @Test
    func setSubSpotUpdatesAndEmits() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)
        let r = AssistantTools.dispatch(name: "set_sub_spot",
            argsJSON: #"{"location":"by the dam"}"#, session: session, context: context, now: now)
        #expect(r.ok)
        #expect(session.currentSubSpot == "by the dam")
        #expect(session.events.contains { $0.kind == .subSpotChange && $0.subSpot == "by the dam" })
    }

    @Test
    func logBiteCreatesBiteEventWithSetupSnapshot() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)
        session.currentSetup = Setup(lure: "frog")
        let r = AssistantTools.dispatch(name: "log_bite",
            argsJSON: #"{"kind":"missed","notes":"big blowup"}"#, session: session, context: context, now: now)
        #expect(r.ok)
        let bite = try #require(session.events.first { $0.kind == .bite })
        #expect(bite.outcome == .missed)
        #expect(bite.setupSnapshot?.lure == "frog")
        #expect(bite.detail == "big blowup")
    }

    @Test
    func logCatchCreatesCatchMatchedToSpeciesWithSetupSnapshot() throws {
        let (container, context) = try makeContext()
        _ = container
        let bass = Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides")
        context.insert(bass)
        let session = makeSession(context)
        session.currentSetup = Setup(rod: "baitcaster", lure: "frog")
        session.currentSubSpot = "by the dam"

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":3.2,"isMeasured":true,"notes":"chunk"}"#,
            session: session, context: context, now: now)
        #expect(r.ok)
        let entry = try #require(session.catches.first)
        #expect(entry.species?.commonName == "Largemouth Bass")
        #expect(entry.weight == 3.2)
        #expect(entry.isMeasured)
        #expect(entry.setupSnapshot?.lure == "frog")
        #expect(entry.rodUsed == "baitcaster")   // mirrored
        #expect(entry.baitUsed == "frog")         // mirrored
        #expect(entry.subSpotSnapshot == "by the dam")
    }

    @Test
    func endSessionSetsEndedAt() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)
        #expect(session.isOngoing)
        let r = AssistantTools.dispatch(name: "end_session", argsJSON: "{}", session: session, context: context, now: now)
        #expect(r.ok)
        #expect(session.endedAt == now)
        // Idempotent guard
        let r2 = AssistantTools.dispatch(name: "end_session", argsJSON: "{}", session: session, context: context, now: now)
        #expect(!r2.ok)
    }

    @Test
    func unknownToolFailsGracefully() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)
        let r = AssistantTools.dispatch(name: "nope", argsJSON: "{}", session: session, context: context, now: now)
        #expect(!r.ok)
    }

    @Test
    func toolSchemaEncodesNullableOptionalsAndRequiredKeys() throws {
        // The model must always receive every key (object forces required), with
        // optional params expressed as nullable unions.
        let tools = AssistantTools.tools()
        let encoder = JSONEncoder()
        let data = try encoder.encode(tools)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("update_setup"))
        #expect(json.contains("log_catch"))
        // additionalProperties:false is emitted for object schemas.
        #expect(json.contains("additionalProperties"))
        // A nullable union serializes an anyOf with a null branch.
        #expect(json.contains("anyOf"))
        #expect(json.contains("\"null\""))
        #expect(tools.count == 6)
    }
}
