import Foundation
import SwiftData
import OSLog
import RealtimeAPI

/// A single entry the UI shows in the live "HEARD" feed.
struct AssistantToolEvent: Identifiable {
    let id = UUID()
    let summary: String
    let ok: Bool
    let timestamp: Date
}

/// Drives the hands-free voice assistant: connects to the OpenAI Realtime API
/// over WebRTC (gpt-realtime-mini), streams mic audio, plays responses, and
/// routes the model's tool calls to SwiftData mutations via `AssistantTools`.
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

    var isActive: Bool { conversation != nil }
    var isUserSpeaking: Bool { conversation?.isUserSpeaking ?? false }
    var isModelSpeaking: Bool { conversation?.isModelSpeaking ?? false }

    var muted: Bool = false {
        didSet { conversation?.muted = muted }
    }

    private var conversation: Conversation?
    private var tasks: [Task<Void, Never>] = []
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
        guard conversation == nil else { return }
        self.session = session
        self.context = context
        self.species = species
        lastTranscript = nil

        guard let key = await keychain.getApiKey(), !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .error("Add your OpenAI API key in Settings to use the assistant.")
            return
        }

        phase = .connecting

        let convo = Conversation(configuring: { [species] config in
            config.tools = AssistantTools.tools()
            config.toolChoice = .auto
            config.instructions = AssistantInstructions.instructions(for: session, species: species)
            config.audio.input.turnDetection = .semanticVad()
            config.audio.input.transcription = .init(model: .gpt4oMini)
        })
        conversation = convo
        muted = false

        do {
            try await convo.connect(ephemeralKey: key, model: .custom("gpt-realtime-mini"))
            phase = .listening
            startLoops(convo)
        } catch {
            log.error("Assistant connect failed: \(String(describing: error), privacy: .public)")
            phase = .error(friendlyMessage(for: error))
            conversation = nil
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        conversation = nil
        phase = .idle
    }

    // MARK: - Event loops

    private func startLoops(_ convo: Conversation) {
        tasks.append(Task { [weak self] in
            for await call in convo.functionCalls {
                guard let self else { break }
                await self.handle(call, convo: convo)
            }
        })
        tasks.append(Task { [weak self] in
            for await error in convo.errors {
                guard let self else { break }
                self.log.error("Realtime error: \(error.message, privacy: .public)")
                self.phase = .error(error.message)
            }
        })
        // Surface the user's last transcript for the UI as it arrives.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, let convo = self.conversation else { break }
                if let t = convo.messages.last(where: { $0.role == .user })?.content.last?.text, !t.isEmpty {
                    self.lastTranscript = t
                }
            }
        })
    }

    private func handle(_ call: Item.FunctionCall, convo: Conversation) async {
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

        // Return the result so the model can speak a confirmation.
        do {
            try convo.send(result: .init(id: UUID().uuidString, callId: call.callId, output: result.outputJSON))
            // Refresh instructions so the model's context stays current.
            try convo.updateSession { [species] config in
                config.instructions = AssistantInstructions.instructions(for: session, species: species)
            }
            try convo.send(event: .createResponse())
        } catch {
            log.error("Assistant reply failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let convoError = error as? ConversationError {
            switch convoError {
            case .invalidEphemeralKey: return "That API key was rejected. Check it in Settings."
            default: break
            }
        }
        return "Couldn't connect. Check your network and API key."
    }
}
