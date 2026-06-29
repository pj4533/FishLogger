import Foundation
import SwiftData

/// The tool schema the Realtime model is given (as plain JSON for the
/// `session.update` event), plus the dispatch that turns a model tool call into
/// SwiftData mutations via `SessionEventLogger`. The dispatch core is factored
/// out (`dispatch(name:argsJSON:session:context:)`) so it can be unit-tested
/// without a live connection.
@MainActor
enum AssistantTools {

    struct Result {
        let ok: Bool
        let summary: String

        /// JSON the assistant returns to the model so it can speak a confirmation.
        var outputJSON: String {
            let obj: [String: Any] = ok ? ["ok": true, "summary": summary]
                                        : ["ok": false, "error": summary]
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    // MARK: - Schema

    /// The tool definitions sent in `session.update.session.tools`, as plain
    /// JSON objects. With the raw API we use ordinary JSON Schema — optional
    /// params are simply omitted from `required` (no nullable-union hack needed).
    static func tools() -> [[String: Any]] {
        func fn(_ name: String, _ description: String, properties: [String: Any], required: [String]) -> [String: Any] {
            ["type": "function", "name": name, "description": description,
             "parameters": ["type": "object", "properties": properties, "required": required]]
        }
        func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

        return [
            fn("update_setup",
               "Update what the angler is fishing with right now. Only include the fields that changed (e.g. 'switching to a frog' sets only lure). A COMPLETE setup (all six fields) is required before any catch or bite can be logged.",
               properties: [
                   "rod": str("Rod, e.g. 'baitcaster' or 'Ugly Stik 6'6\"'"),
                   "reel": str("Reel"),
                   "line": str("Line type/weight, e.g. '15lb braid'"),
                   "lure": str("Lure or bait, e.g. 'hollow body frog', 'whopper plopper', 'nightcrawler'"),
                   "color": str("Color/pattern, e.g. 'chartreuse', 'black/blue'"),
                   "technique": str("Technique/presentation, e.g. 'topwater', 'flipping', 'slow roll'")
               ], required: []),
            fn("set_sub_spot",
               "Record where on the spot the angler is now fishing, e.g. 'by the dam', 'the lily pads on the north bank'.",
               properties: ["location": str("Free-text micro-location within the spot.")],
               required: ["location"]),
            fn("set_angler",
               "Record who is fishing this session (the default person credited with catches). Call this when the angler says who they are or who's with them, e.g. 'it's me and Dave today'.",
               properties: ["name": str("The angler's name.")],
               required: ["name"]),
            fn("log_bite",
               "Record a bite or missed fish — a blowup, short strike, follow, or a fish that bit but wasn't landed. Use this for action that did NOT result in a landed catch. Requires a COMPLETE setup first (rod, reel, line, lure, color, technique); rejected with the missing fields otherwise.",
               properties: [
                   "kind": ["type": "string", "enum": ["bite", "missed", "blowup", "follow"],
                            "description": "bite = bit but not landed; missed = missed hookset; blowup = topwater explosion no hookup; follow = followed but didn't commit."],
                   "notes": str("Optional detail.")
               ], required: ["kind"]),
            fn("log_catch",
               "Record a landed fish. REQUIRED before this succeeds: a known species, a COMPLETE setup (rod, reel, line, lure, color, technique — set via update_setup), and who caught it (set_angler, or the caughtBy field). Weight (in pounds) is the ONLY optional field. If anything is missing the call is REJECTED with the list of missing fields — ask the angler for them, then call again.",
               properties: [
                   "species": str("Species common name, e.g. 'Largemouth Bass'. Must match one of the app's known species."),
                   "weight": ["type": "number", "description": "Weight in pounds (optional — omit if not weighed)."],
                   "isMeasured": ["type": "boolean", "description": "True if weighed/measured, false if estimated."],
                   "caughtBy": str("Who caught it, if named (e.g. 'Dave'). Omit to credit the current angler (who must already be set)."),
                   "notes": str("Optional detail.")
               ], required: []),
            fn("add_note",
               "Record a free-text note about anything that isn't a setup change, sub-spot, bite, or catch — water clarity, weather, structure, fish behavior, or an explicit 'make a note that…'. Call this rather than only replying verbally.",
               properties: ["text": str("The note text (the angler's words).")],
               required: ["text"]),
            fn("end_session",
               "End the current fishing session. This finalizes the timeline so no-catch coverage can be derived.",
               properties: [:], required: [])
        ]
    }

    // MARK: - Dispatch

    /// Performs the SwiftData mutation for a tool call. Does NOT call
    /// `context.save()` — the caller saves once after dispatch.
    static func dispatch(name: String, argsJSON: String, session: Session, context: ModelContext, now: Date = .now) -> Result {
        // Lenient parse: tolerate odd shapes / types from the model rather than
        // failing the whole call. Missing fields just read as nil.
        let args = (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8))) as? [String: Any] ?? [:]

        switch name {
        case "update_setup":
            let partial = Setup(
                rod: str(args["rod"]), reel: str(args["reel"]), line: str(args["line"]),
                lure: str(args["lure"]), color: str(args["color"]), technique: str(args["technique"])
            )
            if partial.isEmpty { return Result(ok: false, summary: "No fields to update") }
            return Result(ok: true, summary: SessionEventLogger.changeSetup(partial, on: session, at: now, context: context))

        case "set_sub_spot":
            guard let location = str(args["location"]) ?? str(args["sub_spot"]), !location.isEmpty else {
                return Result(ok: false, summary: "No location given")
            }
            return Result(ok: true, summary: SessionEventLogger.changeSubSpot(location, on: session, at: now, context: context))

        case "log_bite":
            let missing = missingSetupFields(session.currentSetup)
            if !missing.isEmpty {
                return Result(ok: false, summary: "Can't log that yet — still need the setup: \(missing.joined(separator: ", ")). Ask the angler, then log the bite.")
            }
            let outcome = BiteOutcome(rawValue: (str(args["kind"]) ?? "bite").lowercased()) ?? .bite
            return Result(ok: true, summary: SessionEventLogger.logBite(outcome, detail: str(args["notes"]), on: session, at: now, context: context))

        case "set_angler":
            guard let name = str(args["name"]) else { return Result(ok: false, summary: "No name given") }
            return Result(ok: true, summary: SessionEventLogger.changeAngler(name, on: session, context: context))

        case "log_catch":
            let speciesName = str(args["species"])
            let species = matchSpecies(speciesName, context: context)
            let caughtBy = str(args["caughtBy"]) ?? ""

            // Enforce complete data — the model can't skip the follow-ups. Weight
            // is the only optional field; everything else must be present.
            var missing: [String] = []
            if species == nil {
                if let name = speciesName, !name.isEmpty {
                    missing.append("species (didn't recognize “\(name)” — which species is it?)")
                } else {
                    missing.append("species")
                }
            }
            missing.append(contentsOf: missingSetupFields(session.currentSetup))
            if caughtBy.isEmpty && session.currentAngler.isEmpty {
                missing.append("who caught it")
            }
            if !missing.isEmpty {
                return Result(ok: false, summary: "Can't log the catch yet — still need: \(missing.joined(separator: ", ")). Ask the angler for these, then call log_catch again.")
            }

            let weight = num(args["weight"]) ?? 0
            let entry = Catch(
                timestamp: now, latitude: session.latitude, longitude: session.longitude,
                weight: weight, isMeasured: bool(args["isMeasured"]) ?? false,
                caughtBy: caughtBy,
                notes: str(args["notes"]) ?? "", species: species, session: session
            )
            SessionEventLogger.stampSetup(on: entry, from: session)   // defaults caughtBy to the session angler if blank
            context.insert(entry)
            let label = species?.commonName ?? speciesName ?? "fish"
            let wt = weight > 0 ? String(format: " (%.1f lb)", weight) : ""
            let by = entry.caughtBy.isEmpty ? "" : " — \(entry.caughtBy)"
            return Result(ok: true, summary: "Logged \(label)\(wt)\(by)")

        case "add_note":
            // Accept any of a few plausible keys, or fall back to the whole blob.
            let text = str(args["text"]) ?? str(args["note"]) ?? str(args["content"]) ?? argsJSON
            guard !text.isEmpty else { return Result(ok: false, summary: "Empty note") }
            return Result(ok: true, summary: SessionEventLogger.logNote(text, on: session, at: now, context: context))

        case "end_session":
            guard session.isOngoing else { return Result(ok: false, summary: "Session already ended") }
            session.endedAt = now
            return Result(ok: true, summary: "Session ended")

        default:
            return Result(ok: false, summary: "Unknown tool \(name)")
        }
    }

    /// Setup fields still missing — every field is required before a catch or
    /// bite can be logged. Returned in form order so the spoken follow-up reads
    /// naturally. Shared with `AssistantInstructions` so the prompt context and
    /// the enforcement agree on what's required.
    static func missingSetupFields(_ s: Setup) -> [String] {
        var m: [String] = []
        if s.rod == nil       { m.append("rod") }
        if s.reel == nil      { m.append("reel") }
        if s.line == nil      { m.append("line") }
        if s.lure == nil      { m.append("lure") }
        if s.color == nil     { m.append("color") }
        if s.technique == nil { m.append("technique") }
        return m
    }

    // Lenient coercion helpers (models sometimes send numbers as strings, etc.).
    private static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    private static func bool(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return (s as NSString).boolValue }
        return nil
    }

    /// Case-insensitive match of a spoken species name against known species —
    /// exact common-name first, then substring either direction.
    private static func matchSpecies(_ name: String?, context: ModelContext) -> Species? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let all = try? context.fetch(FetchDescriptor<Species>()) else { return nil }
        let needle = name.lowercased()
        if let exact = all.first(where: { $0.commonName.lowercased() == needle }) { return exact }
        return all.first { $0.commonName.lowercased().contains(needle) || needle.contains($0.commonName.lowercased()) }
    }
}
