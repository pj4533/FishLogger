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

    /// A complete setup — every field set, which is what catches/bites now
    /// require. Tests that don't care about the specific gear use this.
    private func completeSetup(rod: String = "baitcaster", lure: String = "frog") -> Setup {
        Setup(rod: rod, reel: "200 series", line: "30lb braid",
              lure: lure, color: "black", technique: "topwater")
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
        session.currentSetup = completeSetup()
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
        session.currentSetup = completeSetup(rod: "baitcaster", lure: "frog")
        session.currentAngler = "PJ"
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
    func setAnglerStoresOnSessionAndDefaultsCatchCredit() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentSetup = completeSetup()

        let r = AssistantTools.dispatch(name: "set_angler", argsJSON: #"{"name":"PJ"}"#, session: session, context: context, now: now)
        #expect(r.ok)
        #expect(session.currentAngler == "PJ")

        // A catch with no explicit caughtBy defaults to the session angler.
        _ = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":2.0}"#, session: session, context: context, now: now)
        #expect(session.catches.first?.caughtBy == "PJ")
    }

    @Test
    func logCatchCaughtByOverridesSessionAngler() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentSetup = completeSetup()
        session.currentAngler = "PJ"

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":4.0,"caughtBy":"Dave"}"#,
            session: session, context: context, now: now)
        #expect(r.ok)
        #expect(session.catches.first?.caughtBy == "Dave")
    }

    // MARK: - Required-data enforcement

    @Test
    func logCatchRejectedWhenSetupIncomplete() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentAngler = "PJ"
        session.currentSetup = Setup(rod: "baitcaster", lure: "frog")  // missing reel/line/color/technique

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":3.0}"#,
            session: session, context: context, now: now)
        #expect(!r.ok)
        #expect(r.summary.contains("reel"))
        #expect(r.summary.contains("line"))
        #expect(r.summary.contains("color"))
        #expect(r.summary.contains("technique"))
        #expect(session.catches.isEmpty)   // nothing logged
    }

    @Test
    func logCatchRejectedWhenAnglerMissing() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentSetup = completeSetup()   // setup complete, but no angler and no caughtBy

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":3.0}"#,
            session: session, context: context, now: now)
        #expect(!r.ok)
        #expect(r.summary.localizedCaseInsensitiveContains("who"))
        #expect(session.catches.isEmpty)
    }

    @Test
    func logCatchAcceptedWithCaughtByEvenWithoutSessionAngler() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentSetup = completeSetup()   // no currentAngler, but caughtBy names someone

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"largemouth","weight":3.0,"caughtBy":"Dave"}"#,
            session: session, context: context, now: now)
        #expect(r.ok)
        #expect(session.catches.first?.caughtBy == "Dave")
    }

    @Test
    func logCatchRejectedWhenSpeciesUnknown() throws {
        let (container, context) = try makeContext()
        _ = container
        context.insert(Species(commonName: "Largemouth Bass", scientificName: "Micropterus salmoides"))
        let session = makeSession(context)
        session.currentSetup = completeSetup()
        session.currentAngler = "PJ"

        let r = AssistantTools.dispatch(name: "log_catch",
            argsJSON: #"{"species":"unicornfish","weight":3.0}"#,
            session: session, context: context, now: now)
        #expect(!r.ok)
        #expect(r.summary.localizedCaseInsensitiveContains("species"))
        #expect(session.catches.isEmpty)
    }

    @Test
    func logBiteRejectedWhenSetupIncomplete() throws {
        let (container, context) = try makeContext()
        _ = container
        let session = makeSession(context)
        session.currentSetup = Setup(lure: "frog")   // only lure

        let r = AssistantTools.dispatch(name: "log_bite",
            argsJSON: #"{"kind":"missed"}"#, session: session, context: context, now: now)
        #expect(!r.ok)
        #expect(r.summary.contains("rod"))
        #expect(session.events.contains { $0.kind == .bite } == false)
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
    func toolSchemaIsValidFunctionJSON() throws {
        let tools = AssistantTools.tools()
        #expect(tools.count == 7)

        // Each tool is a function with a name and an object-typed parameters schema.
        for tool in tools {
            #expect(tool["type"] as? String == "function")
            #expect((tool["name"] as? String)?.isEmpty == false)
            let params = try #require(tool["parameters"] as? [String: Any])
            #expect(params["type"] as? String == "object")
            #expect(params["properties"] is [String: Any])
            #expect(params["required"] is [String])
        }

        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"] as! String, $0) })
        // Optional params are simply absent from `required` (no nullable-union hack).
        let updateReq = ((byName["update_setup"]!["parameters"] as! [String: Any])["required"] as! [String])
        #expect(updateReq.isEmpty)
        // Required params are listed.
        let subReq = ((byName["set_sub_spot"]!["parameters"] as! [String: Any])["required"] as! [String])
        #expect(subReq == ["location"])

        // The whole thing serializes to JSON (what we send in session.update).
        #expect(JSONSerialization.isValidJSONObject(["tools": tools]))
        _ = try JSONSerialization.data(withJSONObject: ["tools": tools])
    }
}
