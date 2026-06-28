import Foundation
import OSLog

/// Minimal OpenAI Realtime API client over a plain WebSocket
/// (`URLSessionWebSocketTask`) — no third-party dependencies. Speaks the GA
/// `session.type = "realtime"` event schema. Audio is PCM16 mono @ 24 kHz,
/// base64-encoded both directions.
///
/// Security note: for this single-user personal app we connect directly with
/// the standing `sk-` Platform key. A public build would mint an ephemeral key
/// from a tiny backend and pass that instead — only the token source changes.
@MainActor
final class RealtimeClient {
    /// Realtime model. `gpt-realtime-mini` is enabled for this account and tuned
    /// for tool calling; swap to `gpt-realtime-2` once that model is granted
    /// runtime access (it's in the catalog but not yet runnable here).
    static let model = "gpt-realtime-mini"
    /// PCM16 mono sample rate used both directions.
    static let sampleRate = 24_000

    struct FunctionCall: Equatable {
        let callId: String
        let name: String
        let arguments: String
    }

    enum Event {
        case connected
        case userTranscript(String)
        case assistantTranscript(String)
        case assistantReply(String)          // the model's finished spoken reply
        case audioDelta(Data)                 // PCM16 24 kHz mono
        case userSpeakingChanged(Bool)
        case assistantSpeakingChanged(Bool)
        case functionCall(FunctionCall)
        case failed(String)
        case closed
    }

    var onEvent: ((Event) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var assistantSpeaking = false
    private let log = Logger.assistant

    // MARK: - Lifecycle

    func connect(apiKey: String, instructions: String, tools: [[String: Any]]) {
        var comps = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        comps.queryItems = [URLQueryItem(name: "model", value: Self.model)]
        var request = URLRequest(url: comps.url!)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        self.pendingInstructions = instructions
        self.pendingTools = tools
        task.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
    }

    private var pendingInstructions = ""
    private var pendingTools: [[String: Any]] = []

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        assistantSpeaking = false
    }

    // MARK: - Sending

    /// Sends the session configuration (instructions, tools, audio format,
    /// turn detection, transcription).
    func configure(instructions: String, tools: [[String: Any]]) {
        let session: [String: Any] = [
            "type": "realtime",
            "instructions": instructions,
            "output_modalities": ["audio"],
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": Self.sampleRate],
                    "turn_detection": ["type": "semantic_vad"],
                    "transcription": ["model": "gpt-4o-mini-transcribe"]
                ],
                "output": [
                    "format": ["type": "audio/pcm", "rate": Self.sampleRate],
                    "voice": "marin"
                ]
            ],
            "tools": tools,
            "tool_choice": "auto"
        ]
        send(["type": "session.update", "session": session])
    }

    func updateInstructions(_ instructions: String) {
        send(["type": "session.update", "session": ["type": "realtime", "instructions": instructions]])
    }

    /// Returns the function-call result and asks the model to respond (speak a
    /// confirmation).
    func sendFunctionResult(callId: String, output: String) {
        send(["type": "conversation.item.create",
              "item": ["type": "function_call_output", "call_id": callId, "output": output]])
        send(["type": "response.create"])
    }

    /// A `Sendable` sink the audio engine calls from its capture thread to
    /// stream microphone PCM16 to the server, in order, without actor hops.
    func makeAudioSink() -> (@Sendable (Data) -> Void)? {
        guard let task else { return nil }
        return { data in
            let payload: [String: Any] = ["type": "input_audio_buffer.append",
                                          "audio": data.base64EncodedString()]
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            task.send(.string(text)) { _ in }
        }
    }

    #if DEBUG
    /// Test hook: inject a text user turn and request a response, to exercise
    /// the live model + tool calling without a microphone.
    func sendTextTurn(_ text: String) {
        send(["type": "conversation.item.create",
              "item": ["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": text]]]])
        send(["type": "response.create"])
    }
    #endif

    private func send(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if let error { Task { @MainActor in self?.log.error("WS send error: \(error.localizedDescription, privacy: .public)") } }
        }
    }

    // MARK: - Receiving

    private func receiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .string(text): handle(text)
                case let .data(data): handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                if !Task.isCancelled { onEvent?(.closed) }
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created":
            configure(instructions: pendingInstructions, tools: pendingTools)
            onEvent?(.connected)

        case "error":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "Realtime error"
            log.error("Realtime error: \(message, privacy: .public)")
            onEvent?(.failed(message))

        case "input_audio_buffer.speech_started":
            onEvent?(.userSpeakingChanged(true))
        case "input_audio_buffer.speech_stopped":
            onEvent?(.userSpeakingChanged(false))

        case "conversation.item.input_audio_transcription.completed":
            if let t = obj["transcript"] as? String { onEvent?(.userTranscript(t)) }

        case "response.output_audio_transcript.delta":
            if let d = obj["delta"] as? String { onEvent?(.assistantTranscript(d)) }

        case "response.output_audio_transcript.done", "response.output_text.done":
            if let t = obj["transcript"] as? String ?? obj["text"] as? String, !t.isEmpty {
                onEvent?(.assistantReply(t))
            }

        case "response.output_audio.delta":
            if !assistantSpeaking { assistantSpeaking = true; onEvent?(.assistantSpeakingChanged(true)) }
            if let b64 = obj["delta"] as? String, let audio = Data(base64Encoded: b64) {
                onEvent?(.audioDelta(audio))
            }

        case "response.output_audio.done", "response.done":
            if assistantSpeaking { assistantSpeaking = false; onEvent?(.assistantSpeakingChanged(false)) }

        case "response.function_call_arguments.done":
            if let callId = obj["call_id"] as? String,
               let name = obj["name"] as? String {
                let args = obj["arguments"] as? String ?? "{}"
                onEvent?(.functionCall(FunctionCall(callId: callId, name: name, arguments: args)))
            }

        default:
            break
        }
    }
}
