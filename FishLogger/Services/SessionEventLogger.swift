import Foundation
import SwiftData

/// The single place that mutates a session's live setup/sub-spot and appends
/// the matching `SessionEvent`, so the manual UI and the voice assistant can't
/// drift. Stateless and `@MainActor` (all SwiftData mutation happens here).
@MainActor
enum SessionEventLogger {

    /// A short human summary of what was logged, for the UI feed and the
    /// assistant's tool-result confirmation.
    @discardableResult
    static func changeSetup(
        _ partial: Setup,
        on session: Session,
        at timestamp: Date = .now,
        context: ModelContext
    ) -> String {
        let merged = session.currentSetup.merging(partial)
        guard merged != session.currentSetup else {
            return "No setup change"
        }
        session.currentSetup = merged
        let event = SessionEvent(
            timestamp: timestamp, kind: .setupChange,
            session: session, setupSnapshot: merged
        )
        context.insert(event)
        return "Setup → \(summary(of: merged))"
    }

    @discardableResult
    static func changeSubSpot(
        _ location: String,
        on session: Session,
        at timestamp: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        context: ModelContext
    ) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        session.currentSubSpot = trimmed
        let event = SessionEvent(
            timestamp: timestamp, kind: .subSpotChange,
            session: session, subSpot: trimmed,
            latitude: latitude, longitude: longitude
        )
        context.insert(event)
        return "Now at \(trimmed)"
    }

    @discardableResult
    static func logBite(
        _ outcome: BiteOutcome,
        detail: String? = nil,
        on session: Session,
        at timestamp: Date = .now,
        context: ModelContext
    ) -> String {
        let event = SessionEvent(
            timestamp: timestamp, kind: .bite,
            session: session,
            setupSnapshot: session.currentSetup.isEmpty ? nil : session.currentSetup,
            subSpot: session.currentSubSpot.isEmpty ? nil : session.currentSubSpot,
            outcome: outcome, detail: detail
        )
        context.insert(event)
        return "\(outcome.display) logged"
    }

    @discardableResult
    static func logNote(
        _ text: String,
        on session: Session,
        at timestamp: Date = .now,
        context: ModelContext
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = SessionEvent(
            timestamp: timestamp, kind: .note,
            session: session, detail: trimmed
        )
        context.insert(event)
        return "Note added"
    }

    @discardableResult
    static func changeAngler(
        _ name: String,
        on session: Session,
        context: ModelContext
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.currentAngler = trimmed
        return trimmed.isEmpty ? "Angler cleared" : "Angler: \(trimmed)"
    }

    /// Stamps a newly created catch with the session's live setup/sub-spot,
    /// defaults `caughtBy` to the session angler, and mirrors `rod`/`lure` onto
    /// the legacy `rodUsed`/`baitUsed` fields. Call before inserting the catch.
    static func stampSetup(on entry: Catch, from session: Session) {
        let setup = session.currentSetup
        if !setup.isEmpty {
            entry.setupSnapshot = setup
            if entry.rodUsed.isEmpty, let rod = setup.rod { entry.rodUsed = rod }
            if entry.baitUsed.isEmpty, let lure = setup.lure { entry.baitUsed = lure }
        }
        if !session.currentSubSpot.isEmpty {
            entry.subSpotSnapshot = session.currentSubSpot
        }
        if entry.caughtBy.isEmpty, !session.currentAngler.isEmpty {
            entry.caughtBy = session.currentAngler
        }
    }

    private static func summary(of setup: Setup) -> String {
        [setup.color, setup.lure, setup.technique]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
            ?? [setup.rod, setup.reel, setup.line].compactMap { $0 }.joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
