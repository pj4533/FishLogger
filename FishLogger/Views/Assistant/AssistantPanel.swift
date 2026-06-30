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
                        isRecording: assistant.isRecording,
                        isModelSpeaking: assistant.isModelSpeaking,
                        isBusy: assistant.phase == .connecting || assistant.phase == .processing
                    ) {
                        Task { await tap() }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.cozyBody.weight(.medium))
                            .foregroundStyle(Color.ink)
                        if let reply = assistant.lastAssistantReply {
                            // Stays visible after a single round ends so the
                            // angler can read the confirmation, not just hear it.
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
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onDisappear { assistant.stop() }
    }

    private func tap() async {
        switch assistant.phase {
        case .idle, .error:
            await assistant.start(session: session, context: context, species: species)
        case .recording:
            assistant.finishTurn()
        case .ready:
            assistant.resumeRecording()
        case .connecting, .processing:
            break   // busy — ignore taps
        }
    }

    private var statusText: String {
        switch assistant.phase {
        case .idle:       return "Tap to talk"
        case .connecting: return "Connecting…"
        case .recording:  return "Listening — tap to send"
        case .processing: return assistant.isModelSpeaking ? "Replying…" : "Thinking…"
        case .ready:      return "Tap to answer"
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

/// Circular push-to-talk control: tap to start talking (mic), tap again to send
/// (stop). Pulses while recording or while the model replies.
private struct TalkButton: View {
    let isRecording: Bool
    let isModelSpeaking: Bool
    let isBusy: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.sunset : Color.waterDeep)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.sunset.opacity(0.5), lineWidth: 3)
                            .scaleEffect(pulse && (isRecording || isModelSpeaking) ? 1.35 : 1.0)
                            .opacity(pulse && (isRecording || isModelSpeaking) ? 0 : 1)
                    )
                if isBusy {
                    ProgressView().tint(Color.paper)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(Color.paper)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onChange(of: isRecording || isModelSpeaking) { _, active in
            pulse = active
        }
        .animation(.easeOut(duration: 0.8).repeatForever(autoreverses: false), value: pulse)
    }
}
