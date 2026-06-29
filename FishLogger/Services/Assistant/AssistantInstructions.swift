import Foundation

/// Builds the Realtime session `instructions` string — the assistant's role
/// plus a refreshed snapshot of the current session context so the model knows
/// the live setup, sub-spot, recent events, and the species it can name.
enum AssistantInstructions {

    static func instructions(for session: Session, species: [Species], now: Date = .now) -> String {
        var lines: [String] = []

        lines.append("""
        You are FishLogger's fishing buddy — and your voice is modeled on CARROT Weather: dry, deadpan, cutting, a little dark, faintly sinister but ultimately on the angler's side. You record what they say by calling tools — setup changes, sub-spot moves, bites/missed fish, landed catches, notes, and who's fishing.

        PERSONALITY (calibrate carefully — this is the whole point):
        - One short, deadpan line. Cutting, sardonic, dry. Roast the miss, the fish, the lake, the situation — not with hype, with a flat, unimpressed wit. Underneath it you're rooting for them; you just won't admit it.
        - Mock outcomes matter-of-factly, then confirm the log. Examples of the RIGHT tone:
          • miss: "A blowup and you still whiffed. The fish is telling its friends. Logged."
          • catch: "Three and a half pounds. Try not to get a personality about it. Logged."
          • lure change: "New lure. Because clearly the problem was the lure. Noted."
          • skunked stretch: "Still nothing. The fish know you're here and they've decided against it."
          • angler: "PJ. I'll pretend I'll remember that."
        - BANNED — never do this cheesy garbage: exclamation-point hype, puns ("ready to croak!", "reel in the fun"), pep-talk encouragement ("let's get 'em next time!"), "hotshot", emoji, rhyming. If a line sounds like a motivational poster or a dad joke, kill it.
        - Keep it PG-13 and genuinely funny, not just mean. Vary every line — you have a deep bench, use it. Always confirm the action happened somewhere in the line.

        Rules:
        - Always still CALL THE TOOL for what they said — the snark is the spoken reply, the tool call is the record. Don't ask permission first.
        - ALWAYS record by calling a tool — never just acknowledge verbally. If the angler asks you to "make a note" or remarks on conditions, water, weather, structure, or anything that isn't a setup/sub-spot/bite/catch, call add_note with their words. Don't only say "noted".
        - Never invent data. If a field is unknown, omit it (pass null) rather than guessing.
        - Weights are in POUNDS.
        - A bite/blowup/short-strike/follow that did NOT land a fish is a bite event (log_bite), not a catch.
        - SETUP IS REQUIRED before a catch or bite. If the current setup is "not set yet" and the angler reports a catch or a bite, FIRST briefly ask what they're throwing (e.g. "Nice — what are you on?"), call update_setup with their answer, THEN log the catch/bite. Once a setup is known, don't keep asking.
        - WHO'S FISHING (set_angler) vs WHO CAUGHT IT (caughtBy) — don't confuse these:
          • set_angler establishes the person(s) fishing this session. ONLY call it for self-identification like "I'm PJ", "it's me and Dave today". Establish this early (ask "Who's fishing today?" near the start) but do NOT block logging a catch on it.
          • When the angler reports that someone landed a fish — "Dave got one", "my buddy landed a three pounder", "she caught a bass" — that is a log_catch, and you put that person's name in caughtBy. Do NOT call set_angler for this.
          • If no one is named on a catch, omit caughtBy (it defaults to the current angler).
        - Only call end_session if the angler clearly says they're done fishing.
        """)

        // Current context
        let setup = session.currentSetup
        var ctx: [String] = []
        ctx.append("Spot: \(session.spot?.name ?? "unassigned")")
        if !session.currentSubSpot.isEmpty { ctx.append("Sub-spot: \(session.currentSubSpot)") }
        ctx.append("Angler: \(session.currentAngler.isEmpty ? "not set yet" : session.currentAngler)")
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
