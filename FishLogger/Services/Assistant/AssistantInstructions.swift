import Foundation

/// Builds the Realtime session `instructions` string — the assistant's role
/// plus a refreshed snapshot of the current session context so the model knows
/// the live setup, sub-spot, recent events, and the species it can name.
enum AssistantInstructions {

    static func instructions(for session: Session, species: [Species], now: Date = .now) -> String {
        var lines: [String] = []

        lines.append("""
        You are FishLogger's hands-free fishing companion. The angler is actively fishing and talking to you. Your job is to record what they say by calling tools — setup changes, sub-spot moves, bites/missed fish, landed catches, and notes.

        Rules:
        - Keep spoken replies to a short confirmation, one sentence or less. Don't chit-chat.
        - Call a tool whenever the angler states something loggable. Don't ask permission first.
        - ALWAYS record by calling a tool — never just acknowledge verbally. If the angler asks you to "make a note" or remarks on conditions, water, weather, structure, or anything that isn't a setup/sub-spot/bite/catch, call add_note with their words. Don't only say "noted".
        - Never invent data. If a field is unknown, omit it (pass null) rather than guessing.
        - Weights are in POUNDS.
        - A bite/blowup/short-strike/follow that did NOT land a fish is a bite event (log_bite), not a catch.
        - Only call end_session if the angler clearly says they're done fishing.
        """)

        // Current context
        let setup = session.currentSetup
        var ctx: [String] = []
        ctx.append("Spot: \(session.spot?.name ?? "unassigned")")
        if !session.currentSubSpot.isEmpty { ctx.append("Sub-spot: \(session.currentSubSpot)") }
        let setupDesc = describe(setup)
        ctx.append("Current setup: \(setupDesc.isEmpty ? "not set yet" : setupDesc)")
        lines.append("\nCurrent context:\n" + ctx.map { "- \($0)" }.joined(separator: "\n"))

        // Recent events (last 6)
        let recent = session.events
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(6)
        if !recent.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            let evLines = recent.map { e -> String in
                "- \(f.string(from: e.timestamp)) \(summarize(e))"
            }
            lines.append("\nRecent events:\n" + evLines.joined(separator: "\n"))
        }

        // Species the model can map spoken names to
        if !species.isEmpty {
            let names = species.sorted { $0.sortOrder < $1.sortOrder }.map(\.commonName)
            lines.append("\nKnown species (map spoken names to these canonical names): \(names.joined(separator: ", ")).")
        }

        return lines.joined(separator: "\n")
    }

    private static func describe(_ s: Setup) -> String {
        var parts: [String] = []
        if let color = s.color { parts.append(color) }
        if let lure = s.lure { parts.append(lure) }
        if let technique = s.technique { parts.append("(\(technique))") }
        if let rod = s.rod { parts.append("on \(rod)") }
        if let line = s.line { parts.append("with \(line)") }
        return parts.joined(separator: " ")
    }

    private static func summarize(_ e: SessionEvent) -> String {
        switch e.kind {
        case .setupChange:  return "switched setup → \(describe(e.setupSnapshot ?? Setup()))"
        case .subSpotChange: return "moved to \(e.subSpot ?? "")"
        case .bite:         return "\(e.outcome?.display ?? "bite")\(e.detail.map { " — \($0)" } ?? "")"
        case .note:         return "note: \(e.detail ?? "")"
        }
    }
}
