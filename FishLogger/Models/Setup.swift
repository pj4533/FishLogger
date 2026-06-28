import Foundation

/// What the angler is fishing with right now — rod, reel, line, lure/bait,
/// color, and technique. Every field is optional so the voice assistant can
/// update it incrementally ("switch to a frog" touches only `lure`).
///
/// Stored by SwiftData as a single Codable attribute on `Session`,
/// `SessionEvent`, and `Catch`, and embedded directly in the export DTOs.
struct Setup: Codable, Equatable, Hashable, Sendable {
    var rod: String?
    var reel: String?
    var line: String?
    var lure: String?
    var color: String?
    var technique: String?

    init(
        rod: String? = nil,
        reel: String? = nil,
        line: String? = nil,
        lure: String? = nil,
        color: String? = nil,
        technique: String? = nil
    ) {
        self.rod = rod
        self.reel = reel
        self.line = line
        self.lure = lure
        self.color = color
        self.technique = technique
    }

    var isEmpty: Bool {
        rod == nil && reel == nil && line == nil
            && lure == nil && color == nil && technique == nil
    }

    /// Returns a copy where each non-nil field of `partial` overrides this one.
    /// This is the incremental-update primitive the assistant tooling calls:
    /// passing a `Setup` with only `lure` set changes only the lure.
    func merging(_ partial: Setup) -> Setup {
        Setup(
            rod: partial.rod ?? rod,
            reel: partial.reel ?? reel,
            line: partial.line ?? line,
            lure: partial.lure ?? lure,
            color: partial.color ?? color,
            technique: partial.technique ?? technique
        )
    }
}

// MARK: - SwiftData persistence

/// SwiftData composite (struct) attributes are not used in this codebase — the
/// house style stores everything flat (see `pressureTrendRaw`, `conditionSymbol`).
/// `Setup` follows suit by persisting as a JSON string column, with computed
/// `Setup` accessors on the models for ergonomics.
extension Setup {
    /// JSON encoding, or `nil` when empty (so an unset setup stays `nil`).
    var jsonString: String? {
        guard !isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes from a stored JSON string; `nil` if missing or unparsable.
    init?(jsonString: String?) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Setup.self, from: data)
        else { return nil }
        self = decoded
    }
}
