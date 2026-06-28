import Foundation
import Security
import OSLog

/// Stores the OpenAI Platform API key in the device keychain. Mirrors the
/// pattern from the sibling IdeaGen app. The key is a standard pay-as-you-go
/// `sk-...` Platform key (the ChatGPT/Codex subscription cannot pay for the
/// Realtime API), used by `AssistantService` to connect.
protocol KeychainManaging: Sendable {
    func saveApiKey(_ key: String) async -> Bool
    func getApiKey() async -> String?
    func deleteApiKey() async -> Bool
}

final class KeychainManager: KeychainManaging, @unchecked Sendable {
    static let shared = KeychainManager()

    let service: String
    let account: String

    nonisolated init(service: String = "com.saygoodnight.FishLogger", account: String = "OpenAIApiKey") {
        self.service = service
        self.account = account
    }

    func saveApiKey(_ key: String) async -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            return updateStatus == errSecSuccess
        } else if status == errSecItemNotFound {
            var newQuery = query
            newQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        } else {
            Logger.keychain.error("Unexpected keychain status: \(status)")
            return false
        }
    }

    func getApiKey() async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    func deleteApiKey() async -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.saygoodnight.FishLogger"
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let assistant = Logger(subsystem: subsystem, category: "assistant")
}
