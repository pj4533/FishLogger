import Foundation
import SwiftData
import RealtimeAPI

/// The tool schema the Realtime model is given, plus the dispatch that turns a
/// model tool call into SwiftData mutations via `SessionEventLogger`. The
/// dispatch core is factored out (`dispatch(name:argsJSON:session:context:)`)
/// so it can be unit-tested without a live `Conversation`.
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

    /// Optional params must be expressed as nullable unions: `JSONSchema.object`
    /// forces every property to be `required`, so the model always sends the
    /// key but may pass `null` for fields it isn't changing.
    private static func nullableString(_ description: String) -> JSONSchema {
        .anyOf([.string(description: description), .null()], description: description)
    }

    static func tools() -> [Tool] {
        [
            .function(.init(
                name: "update_setup",
                description: "Update what the angler is fishing with right now. Only set the fields that changed (e.g. 'switching to a frog' sets only lure). Pass null for anything unchanged.",
                parameters: .object(properties: [
                    "rod": nullableString("Rod, e.g. 'baitcaster' or 'Ugly Stik 6'6\"'"),
                    "reel": nullableString("Reel"),
                    "line": nullableString("Line type/weight, e.g. '15lb braid'"),
                    "lure": nullableString("Lure or bait, e.g. 'hollow body frog', 'whopper plopper', 'nightcrawler'"),
                    "color": nullableString("Color/pattern, e.g. 'chartreuse', 'black/blue'"),
                    "technique": nullableString("Technique/presentation, e.g. 'topwater', 'flipping', 'slow roll'")
                ], description: "Incremental update to the current setup.")
            )),
            .function(.init(
                name: "set_sub_spot",
                description: "Record where on the spot the angler is now fishing, e.g. 'by the dam', 'the lily pads on the north bank'.",
                parameters: .object(properties: [
                    "location": .string(description: "Free-text micro-location within the spot.")
                ], description: "Set the current sub-spot.")
            )),
            .function(.init(
                name: "log_bite",
                description: "Record a bite or missed fish — a blowup, short strike, follow, or a fish that bit but wasn't landed. Use this for action that did NOT result in a landed catch.",
                parameters: .object(properties: [
                    "kind": .enum(cases: ["bite", "missed", "blowup", "follow"], description: "bite = bit but not landed; missed = missed hookset; blowup = topwater explosion no hookup; follow = followed but didn't commit."),
                    "notes": nullableString("Optional detail.")
                ], description: "Log a bite/missed-fish event.")
            )),
            .function(.init(
                name: "log_catch",
                description: "Record a landed fish. Weight is in pounds. Match the species to one of the app's known species when possible.",
                parameters: .object(properties: [
                    "species": nullableString("Species common name, e.g. 'Largemouth Bass'."),
                    "weight": .anyOf([.number(description: "Weight in pounds."), .null()], description: "Weight in pounds, or null if unknown."),
                    "isMeasured": .anyOf([.boolean(description: "True if weighed/measured, false if estimated."), .null()], description: "Whether the weight was measured."),
                    "notes": nullableString("Optional detail.")
                ], description: "Log a landed catch.")
            )),
            .function(.init(
                name: "add_note",
                description: "Record a general free-text note about the session.",
                parameters: .object(properties: [
                    "text": .string(description: "The note text.")
                ], description: "Add a note.")
            )),
            .function(.init(
                name: "end_session",
                description: "End the current fishing session. This finalizes the timeline so no-catch coverage can be derived.",
                parameters: .object(properties: [:], description: "End the session.")
            ))
        ]
    }

    // MARK: - Dispatch

    /// Performs the SwiftData mutation for a tool call. Does NOT call
    /// `context.save()` — the caller saves once after dispatch.
    static func dispatch(name: String, argsJSON: String, session: Session, context: ModelContext, now: Date = .now) -> Result {
        let data = Data(argsJSON.utf8)
        do {
            switch name {
            case "update_setup":
                let a = try decode(UpdateSetupArgs.self, data)
                let partial = Setup(rod: a.rod, reel: a.reel, line: a.line, lure: a.lure, color: a.color, technique: a.technique)
                if partial.isEmpty { return Result(ok: false, summary: "No fields to update") }
                let summary = SessionEventLogger.changeSetup(partial, on: session, at: now, context: context)
                return Result(ok: true, summary: summary)

            case "set_sub_spot":
                let a = try decode(SetSubSpotArgs.self, data)
                let summary = SessionEventLogger.changeSubSpot(a.location, on: session, at: now, context: context)
                return Result(ok: true, summary: summary)

            case "log_bite":
                let a = try decode(LogBiteArgs.self, data)
                let outcome = BiteOutcome(rawValue: a.kind) ?? .bite
                let summary = SessionEventLogger.logBite(outcome, detail: a.notes, on: session, at: now, context: context)
                return Result(ok: true, summary: summary)

            case "log_catch":
                let a = try decode(LogCatchArgs.self, data)
                let species = matchSpecies(a.species, context: context)
                let entry = Catch(
                    timestamp: now,
                    latitude: session.latitude,
                    longitude: session.longitude,
                    weight: a.weight ?? 0,
                    isMeasured: a.isMeasured ?? false,
                    notes: a.notes ?? "",
                    species: species,
                    session: session
                )
                SessionEventLogger.stampSetup(on: entry, from: session)
                context.insert(entry)
                let name = species?.commonName ?? a.species ?? "fish"
                let wt = (a.weight ?? 0) > 0 ? String(format: " (%.1f lb)", a.weight ?? 0) : ""
                return Result(ok: true, summary: "Logged \(name)\(wt)")

            case "add_note":
                let a = try decode(AddNoteArgs.self, data)
                let summary = SessionEventLogger.logNote(a.text, on: session, at: now, context: context)
                return Result(ok: true, summary: summary)

            case "end_session":
                guard session.isOngoing else { return Result(ok: false, summary: "Session already ended") }
                session.endedAt = now
                return Result(ok: true, summary: "Session ended")

            default:
                return Result(ok: false, summary: "Unknown tool \(name)")
            }
        } catch {
            return Result(ok: false, summary: "Bad arguments: \(error.localizedDescription)")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
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

// MARK: - Arg structs (optional fields decode `null` -> nil)

private struct UpdateSetupArgs: Decodable {
    var rod: String?; var reel: String?; var line: String?
    var lure: String?; var color: String?; var technique: String?
}
private struct SetSubSpotArgs: Decodable { var location: String }
private struct LogBiteArgs: Decodable { var kind: String; var notes: String? }
private struct LogCatchArgs: Decodable {
    var species: String?; var weight: Double?; var isMeasured: Bool?; var notes: String?
}
private struct AddNoteArgs: Decodable { var text: String }
