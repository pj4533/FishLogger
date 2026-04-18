import Foundation

/// Output of a dictation parsing pass. Every field is optional so a partial
/// transcript produces a partial result.
struct DictationParseResult {
    var timestamp: Date?
    var species: Species?
    var weight: Double?
    var isMeasured: Bool?
    var bait: String?
    var rod: String?
    var notes: String?
}

/// Implementations (cloud LLM, regex, on-device) all plug in here.
protocol CatchParser: Sendable {
    func parse(_ transcript: String) async throws -> DictationParseResult
}
