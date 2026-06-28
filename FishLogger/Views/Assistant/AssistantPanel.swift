import SwiftUI
import SwiftData

/// The hands-free "fishing buddy" panel shown on an ongoing session. Owns the
/// `AssistantService`, drives the Talk button, and shows a live feed of what
/// the assistant logged.
struct AssistantPanel: View {
    let session: Session

    @Environment(\.modelContext) private var context
    @Query(sort: \Species.sortOrder) private var species: [Species]

    @State private var assistant = AssistantService()
    @State private var showingSettings = false

    #if DEBUG
    private struct DebugPhrase { let id = UUID(); let tool: String; let text: String }
    private static let debugPhrases: [DebugPhrase] = [
        .init(tool: "set_angler", text: "It's just me fishing today, I'm PJ."),
        .init(tool: "update_setup", text: "Switching to a black hollow body frog, fishing topwater."),
        .init(tool: "set_sub_spot", text: "I'm fishing over by the dam now."),
        .init(tool: "log_bite", text: "Had a big blowup on the frog but I missed him."),
        .init(tool: "log_catch", text: "Just landed a three and a half pound largemouth bass."),
        .init(tool: "log_catch+caughtBy", text: "Dave just landed a four pound largemouth."),
        .init(tool: "add_note", text: "Make a note that the water is really muddy today."),
        .init(tool: "end_session", text: "Alright, I'm all done fishing for the day.")
    ]
    #endif

    var body: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("FISHING BUDDY", systemImage: "waveform.circle.fill")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    Spacer()
                    if assistant.isActive {
                        Button {
                            assistant.muted.toggle()
                        } label: {
                            Image(systemName: assistant.muted ? "mic.slash.fill" : "mic.fill")
                                .foregroundStyle(assistant.muted ? Color.inkFaded : Color.sunset)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 14) {
                    TalkButton(
                        isActive: assistant.isActive,
                        isUserSpeaking: assistant.isUserSpeaking,
                        isModelSpeaking: assistant.isModelSpeaking,
                        isConnecting: assistant.phase == .connecting
                    ) {
                        Task { await toggle() }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.cozyBody.weight(.medium))
                            .foregroundStyle(Color.ink)
                        if let reply = assistant.lastAssistantReply, assistant.isActive {
                            Text(reply)
                                .font(.cozyCaption.italic())
                                .foregroundStyle(Color.sunset)
                                .lineLimit(3)
                                .accessibilityIdentifier("assistantReply")
                        } else if let transcript = assistant.lastTranscript, assistant.isActive {
                            Text("“\(transcript)”")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                                .lineLimit(2)
                        } else {
                            Text(hintText)
                                .font(.cozyCaption)
                                .foregroundStyle(Color.inkFaded)
                        }
                    }
                    Spacer()
                }

                if case let .error(message) = assistant.phase {
                    errorRow(message)
                }

                if !assistant.recentToolEvents.isEmpty {
                    Divider()
                    heardFeed
                }

                #if DEBUG
                Divider()
                if assistant.isActive {
                    Text("DEBUG: SEND LIVE PHRASE")
                        .font(.fieldLabel)
                        .foregroundStyle(Color.inkFaded)
                    ForEach(Self.debugPhrases, id: \.id) { phrase in
                        Button {
                            assistant.debugSendTextTurn(phrase.text)
                        } label: {
                            Label("\(phrase.tool): “\(phrase.text)”", systemImage: "text.bubble.fill")
                                .font(.cozyCaption)
                                .foregroundStyle(Color.sunset)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dbg_\(phrase.tool)")
                    }
                } else {
                    Button {
                        Task { await assistant.debugConnectTextOnly(session: session, context: context, species: species) }
                    } label: {
                        Label("Connect text-only (no mic, debug)", systemImage: "keyboard")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.sunset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("debugConnectTextOnly")
                    Button {
                        assistant.debugRunCannedSequence(session: session, context: context, species: species)
                    } label: {
                        Label("Simulate tool calls (offline debug)", systemImage: "ladybug.fill")
                            .font(.cozyCaption)
                            .foregroundStyle(Color.inkFaded)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("debugSimulateToolCalls")
                }
                #endif
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onDisappear { assistant.stop() }
    }

    private func toggle() async {
        if assistant.isActive {
            assistant.stop()
        } else {
            await assistant.start(session: session, context: context, species: species)
        }
    }

    private var statusText: String {
        switch assistant.phase {
        case .idle:       return "Tap to talk"
        case .connecting: return "Connecting…"
        case .listening:
            if assistant.isModelSpeaking { return "Replying…" }
            if assistant.isUserSpeaking { return "Listening…" }
            return "Listening"
        case .error:      return "Tap to retry"
        }
    }

    private var hintText: String {
        assistant.isActive
            ? "Say things like “switching to a frog” or “missed one on a blowup.”"
            : "Narrate your setup, bites, and catches — I'll log them."
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.cozyCaption)
                .foregroundStyle(Color.ink)
            Spacer()
            if message.localizedCaseInsensitiveContains("settings") {
                Button("Settings") { showingSettings = true }
                    .font(.cozyCaption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.sunset)
            }
        }
    }

    private var heardFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEARD")
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
            ForEach(assistant.recentToolEvents.suffix(6).reversed()) { event in
                HStack(spacing: 8) {
                    Image(systemName: event.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(event.ok ? Color.moss : .orange)
                    Text(event.summary)
                        .font(.cozyCaption)
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
            }
        }
    }
}

/// Circular push-to-talk control with a listening/replying pulse.
private struct TalkButton: View {
    let isActive: Bool
    let isUserSpeaking: Bool
    let isModelSpeaking: Bool
    let isConnecting: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.sunset : Color.waterDeep)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.sunset.opacity(0.5), lineWidth: 3)
                            .scaleEffect(pulse && (isUserSpeaking || isModelSpeaking) ? 1.35 : 1.0)
                            .opacity(pulse && (isUserSpeaking || isModelSpeaking) ? 0 : 1)
                    )
                if isConnecting {
                    ProgressView().tint(Color.paper)
                } else {
                    Image(systemName: isActive ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(Color.paper)
                }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isUserSpeaking || isModelSpeaking) { _, speaking in
            pulse = speaking
        }
        .animation(.easeOut(duration: 0.8).repeatForever(autoreverses: false), value: pulse)
    }
}
