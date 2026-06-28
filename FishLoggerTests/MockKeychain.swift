import Foundation
@testable import FishLogger

/// In-memory keychain for tests (avoids real keychain entitlement flakiness).
final class MockKeychain: KeychainManaging, @unchecked Sendable {
    private var stored: String?

    init(initial: String? = nil) { stored = initial }

    func saveApiKey(_ key: String) async -> Bool { stored = key; return true }
    func getApiKey() async -> String? { stored }
    func deleteApiKey() async -> Bool { stored = nil; return true }
}
