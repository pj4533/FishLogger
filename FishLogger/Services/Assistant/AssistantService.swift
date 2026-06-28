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

    private let keychain: KeychainManaging
    private let log = Logger.assistant

    init(keychain: KeychainManaging = KeychainManager.shared) {
        self.keychain = keychain
    }

    // MARK: - Lifecycle

    func start(session: Session, context: ModelContext, species: [Species]) async {
        await connect(session: session, context: context, species: species, captureAudio: true)
    }

    private func connect(session: Session, context: ModelContext, species: [Species], captureAudio: Bool) async {
        guard client == nil else { return }
        self.session = session
        self.context = context
        self.species = species
        lastTranscript = nil
        isUserSpeaking = false
        isModelSpeaking = false

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

        guard captureAudio else { return }   // text-only debug path skips the mic

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

    #if DEBUG
    /// Connects WITHOUT starting the microphone — for deterministic text-turn
    /// testing in the simulator, where the Mac mic otherwise feeds ambient audio
    /// to the live model.
    func debugConnectTextOnly(session: Session, context: ModelContext, species: [Species]) async {
        await connect(session: session, context: context, species: species, captureAudio: false)
    }
    #endif

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
        case let .audioDelta(data):
            audio.enqueue(data)
        case let .userSpeakingChanged(speaking):
            isUserSpeaking = speaking
        case let .assistantSpeakingChanged(speaking):
            isModelSpeaking = speaking
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
            do { try context.save() }
            catch { log.error("Assistant save failed: \(String(describing: error), privacy: .public)") }
        }

        recentToolEvents.append(AssistantToolEvent(summary: result.summary, ok: result.ok, timestamp: .now))
        if recentToolEvents.count > 30 { recentToolEvents.removeFirst(recentToolEvents.count - 30) }

        client?.sendFunctionResult(callId: call.callId, output: result.outputJSON)
        client?.updateInstructions(AssistantInstructions.instructions(for: session, species: species))
    }

    #if DEBUG
    /// Test hook: send a text turn over the LIVE connection so the real model
    /// processes it and (hopefully) calls a tool — verifies the end-to-end
    /// network + model + dispatch path without a microphone.
    func debugSendTextTurn(_ text: String) {
        client?.sendTextTurn(text)
    }

    /// Test hook: run a canned sequence of tool calls through the full dispatch
    /// + save + feed path without a live connection, to verify the data flow in
    /// the simulator (where we can't actually speak).
    func debugRunCannedSequence(session: Session, context: ModelContext, species: [Species]) {
        self.session = session
        self.context = context
        self.species = species
        let calls: [(String, String)] = [
            ("update_setup", #"{"lure":"hollow body frog","color":"black","technique":"topwater"}"#),
            ("set_sub_spot", #"{"location":"by the dam"}"#),
            ("log_bite", #"{"kind":"blowup","notes":"huge blowup, missed him"}"#),
            ("log_catch", #"{"species":"Largemouth Bass","weight":3.4,"isMeasured":true}"#)
        ]
        for (name, args) in calls {
            handleFunctionCall(RealtimeClient.FunctionCall(callId: "debug", name: name, arguments: args))
        }
    }
    #endif
}
