import SwiftUI

/// Lets the angler store their OpenAI Platform API key (used by the voice
/// assistant). The key lives in the device keychain.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyField = ""
    @State private var hasStoredKey = false
    @State private var isWorking = false

    private let keychain: KeychainManaging = KeychainManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasStoredKey {
                        HStack {
                            Label("Key stored", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Color.moss)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                Task { await removeKey() }
                            }
                            .disabled(isWorking)
                        }
                    } else {
                        SecureField("sk-…", text: $keyField)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            Task { await saveKey() }
                        } label: {
                            Text("Save key")
                        }
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    }
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("Stored securely in the device keychain and used for the Realtime voice assistant. Use a pay-as-you-go OpenAI Platform key (sk-…) — a ChatGPT/Codex subscription cannot pay for the audio API. The key is sent directly from this device to OpenAI.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { hasStoredKey = await keychain.getApiKey() != nil }
        }
    }

    private func saveKey() async {
        isWorking = true
        defer { isWorking = false }
        let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        if await keychain.saveApiKey(trimmed) {
            keyField = ""
            hasStoredKey = true
        }
    }

    private func removeKey() async {
        isWorking = true
        defer { isWorking = false }
        if await keychain.deleteApiKey() {
            hasStoredKey = false
        }
    }
}
