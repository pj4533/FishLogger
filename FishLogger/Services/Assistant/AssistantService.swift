import Foundation
import SwiftData
import OSLog

/// A single entry the UI shows in the live "HEARD" feed.
struct AssistantToolEvent: Identifiable {
    let id = UUID()
    let summary: String
    let ok: Bool
    let timestamp: Date
}

/// Drives the hands-free voice assistant: connects to the OpenAI Realtime API
/// over a plain WebSocket (gpt-realtime-2), streams mic audio, plays responses,
/// and routes the model's tool calls to SwiftData mutations via `AssistantTools`.
@MainActor
@Observable
final class AssistantService {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastTranscript: String?
    private(set) var lastAssistantReply: String?
    private(set) var recentToolEvents: [AssistantToolEvent] = []
    private(set) var isUserSpeaking = false
    private(set) var isModelSpeaking = false

    var isActive: Bool { client != nil }

    var muted: Bool = false {
        didSet { audio.isMuted = muted }
    }

    private var client: RealtimeClient?
    private let audio = RealtimeAudioEngine()
    private weak var session: Session?
    private var context: ModelContext?
    private var species: [Species] = []

    // Single-round state: tapping Talk captures one exchange, then disconnects
    // (rather than looping back to listening). We end the round once the turn is
    // fully resolved *and* something was actually recorded — a clarifying
    // question with no tool call keeps the mic open so the angler can answer.
    private var singleRound = false
    private var openResponseCount = 0
    private var pendingToolResponses = 0
    // Per-turn record (reset each time the angler starts a new utterance): did a
    // tool succeed, and did one get rejected for missing data? The round only
    // ends when something was logged AND nothing was rejected — a rejection
    // means a clarifying follow-up is coming, so we keep the mic open.
    private var turnHadSuccessfulTool = false
    private var turnHadRejectedTool = false

    private let keychain: KeychainManaging
    private let log = Logger.assistant

    init(keychain: KeychainManaging = KeychainManager.shared) {
        self.keychain = keychain
    }

    // MARK: - Lifecycle

    func start(session: Session, context: ModelContext, species: [Species]) async {
        guard client == nil else { return }
        self.session = session
        self.context = context
        self.species = species
        lastTranscript = nil
        lastAssistantReply = nil
        isUserSpeaking = false
        isModelSpeaking = false
        // Tapping Talk captures a single exchange, then disconnects.
        singleRound = true
        openResponseCount = 0
        pendingToolResponses = 0
        turnHadSuccessfulTool = false
        turnHadRejectedTool = false

        guard let key = await keychain.getApiKey(), !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .error("Add your OpenAI API key in Settings to use the assistant.")
            return
        }

        phase = .connecting

        let instructions = AssistantInstructions.instructions(for: session, species: species)
        let client = RealtimeClient()
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.connect(apiKey: key, instructions: instructions, tools: AssistantTools.tools())
        self.client = client
        muted = false

        guard let sink = client.makeAudioSink() else {
            phase = .error("Couldn't open the audio connection.")
            stop()
            return
        }
        do {
            try await audio.start(sink: sink)
        } catch RealtimeAudioEngine.AudioError.micPermissionDenied {
            phase = .error("Microphone access is off. Enable it in Settings.")
            stop()
        } catch {
            log.error("Audio start failed: \(String(describing: error), privacy: .public)")
            phase = .error("Couldn't start the microphone.")
            stop()
        }
    }

    func stop() {
        audio.stop()
        client?.disconnect()
        client = nil
        isUserSpeaking = false
        isModelSpeaking = false
        if case .error = phase {} else { phase = .idle }
    }

    // MARK: - Event handling

    private func handle(_ event: RealtimeClient.Event) {
        switch event {
        case .connected:
            if case .error = phase {} else { phase = .listening }
        case let .userTranscript(text):
            lastTranscript = text
        case .assistantTranscript:
            break
        case let .assistantReply(text):
            lastAssistantReply = text
        case let .audioDelta(data):
            audio.enqueue(data)
        case let .userSpeakingChanged(speaking):
            isUserSpeaking = speaking
            // A new utterance begins a fresh turn — clear the per-turn record.
            if speaking { turnHadSuccessfulTool = false; turnHadRejectedTool = false }
        case let .assistantSpeakingChanged(speaking):
            isModelSpeaking = speaking
        case .responseStarted:
            openResponseCount += 1
            if pendingToolResponses > 0 { pendingToolResponses -= 1 }
        case .responseFinished:
            if openResponseCount > 0 { openResponseCount -= 1 }
            endRoundIfComplete()
        case let .functionCall(call):
            handleFunctionCall(call)
        case let .failed(message):
            phase = .error(message)
        case .closed:
            if case .error = phase {} else { phase = .idle }
            audio.stop()
            client = nil
        }
    }

    private func handleFunctionCall(_ call: RealtimeClient.FunctionCall) {
        guard let session, let context else { return }

        let result = AssistantTools.dispatch(
            name: call.name, argsJSON: call.arguments,
            session: session, context: context
        )
        if result.ok {
            turnHadSuccessfulTool = true
            do { try context.save() }
            catch { log.error("Assistant save failed: \(String(describing: error), privacy: .public)") }
        } else {
            // A rejected call (e.g. a catch missing required data) means the
            // model is about to ask a follow-up — keep the round open.
            turnHadRejectedTool = true
        }

        recentToolEvents.append(AssistantToolEvent(summary: result.summary, ok: result.ok, timestamp: .now))
        if recentToolEvents.count > 30 { recentToolEvents.removeFirst(recentToolEvents.count - 30) }

        client?.sendFunctionResult(callId: call.callId, output: result.outputJSON)
        client?.updateInstructions(AssistantInstructions.instructions(for: session, species: species))
        // sendFunctionResult asks the model to speak a confirmation — a new
        // response is coming, so don't end the round on the function-call
        // response's completion.
        pendingToolResponses += 1
    }

    /// In single-round mode, end the exchange once every open response has
    /// finished, no tool-triggered confirmation is still pending, something was
    /// successfully logged this turn, and nothing was rejected (a rejection
    /// means a follow-up question is coming, so we stay listening). We drain the
    /// audio first so the spoken confirmation finishes playing before we
    /// disconnect.
    private func endRoundIfComplete() {
        guard singleRound,
              turnHadSuccessfulTool,
              !turnHadRejectedTool,
              openResponseCount == 0,
              pendingToolResponses == 0 else { return }
        singleRound = false   // don't fire twice while audio drains
        audio.notifyWhenDrained { [weak self] in self?.stop() }
    }
}
