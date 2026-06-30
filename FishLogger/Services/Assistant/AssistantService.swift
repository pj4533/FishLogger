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
        case idle          // not connected
        case connecting
        case recording     // mic live, capturing the angler's speech
        case processing    // audio sent, waiting for the model's reply
        case ready         // connected, mic off — tap to talk again
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastTranscript: String?
    private(set) var lastAssistantReply: String?
    private(set) var recentToolEvents: [AssistantToolEvent] = []
    private(set) var isModelSpeaking = false

    var isRecording: Bool { phase == .recording }

    var isActive: Bool { client != nil }

    var muted: Bool = false {
        didSet { audio.isMuted = muted }
    }

    private var client: RealtimeClient?
    private let audio = RealtimeAudioEngine()
    private weak var session: Session?
    private var context: ModelContext?
    private var species: [Species] = []

    // Push-to-talk turn state. Tapping Talk captures one exchange: once the
    // model has logged something and finished speaking its confirmation we
    // disconnect. A clarifying question (a rejected tool, or no tool at all)
    // instead leaves us connected in `.ready` so the angler can tap to answer.
    private var openResponseCount = 0
    private var pendingToolResponses = 0
    // Per-turn record (reset when a turn begins): did a tool succeed, and did one
    // get rejected for missing data? The round only ends when something was
    // logged AND nothing was rejected — a rejection means a clarifying follow-up
    // is coming, so we stay connected and wait for the angler's answer.
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
        isModelSpeaking = false
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
        isModelSpeaking = false
        if case .error = phase {} else { phase = .idle }
    }

    /// The angler tapped to send: close the mic, commit the captured audio, and
    /// ask the model to respond. Push-to-talk — no silence detection.
    func finishTurn() {
        guard phase == .recording else { return }
        phase = .processing
        audio.stopCapture()
        client?.commitInput()
    }

    /// The angler tapped to talk again after a clarifying question. Reopens the
    /// mic on the existing connection (no reconnect) and starts a fresh turn.
    func resumeRecording() {
        guard client != nil, phase == .ready else { return }
        turnHadSuccessfulTool = false
        turnHadRejectedTool = false
        audio.resumeCapture()
        phase = .recording
    }

    // MARK: - Event handling

    private func handle(_ event: RealtimeClient.Event) {
        switch event {
        case .connected:
            // Mic is already capturing (started right after connect); the angler
            // is now talking and will tap again to send.
            if case .error = phase {} else { phase = .recording }
        case let .userTranscript(text):
            lastTranscript = text
        case .assistantTranscript:
            break
        case let .assistantReply(text):
            lastAssistantReply = text
        case let .audioDelta(data):
            audio.enqueue(data)
        case .userSpeakingChanged:
            // Server-side VAD is disabled (push-to-talk), so these don't fire.
            break
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

    /// Decide what to do once every open response has finished and no
    /// tool-triggered confirmation is still pending. If something was logged and
    /// nothing was rejected, drain the audio (so the spoken confirmation finishes
    /// playing) and disconnect. Otherwise the model asked a clarifying question,
    /// so stay connected in `.ready` and let the angler tap to answer.
    private func endRoundIfComplete() {
        guard openResponseCount == 0, pendingToolResponses == 0 else { return }
        // Only act while we're mid-exchange; ignore stray completions once idle.
        guard phase == .processing || phase == .recording else { return }
        if turnHadSuccessfulTool && !turnHadRejectedTool {
            phase = .processing   // hold this state while the audio drains
            audio.notifyWhenDrained { [weak self] in self?.stop() }
        } else {
            phase = .ready
        }
    }
}
