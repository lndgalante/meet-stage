import Foundation
import Security

/// Keychain-backed storage for the Anthropic API key used by the Demo Mode
/// conversational brain. The key is a paid bearer credential, so it lives in the
/// login Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in the
/// app bundle, UserDefaults, or a plaintext file. A one-time migration imports
/// (and deletes) any key left by the earlier `~/.config/bettermeets` file store,
/// and `ANTHROPIC_API_KEY` remains an override for local development.
enum AnthropicKeyStore {
    private static let service = "dev.poc.meetstage.anthropic"
    private static let account = "conversational-brain"

    private static var legacyFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bettermeets/anthropic-key")
    }

    static var key: String? {
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
            !envKey.isEmpty
        {
            return envKey
        }
        if let stored = readKeychain() {
            return stored
        }
        // One-time migration from the deprecated plaintext file store.
        if let fileKey = try? String(contentsOf: legacyFileURL, encoding: .utf8) {
            let trimmed = fileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = writeKeychain(trimmed)
                try? FileManager.default.removeItem(at: legacyFileURL)
                return trimmed
            }
        }
        return nil
    }

    /// Whether a key exists — an attribute-only check that does NOT read the
    /// secret, so it never triggers a Keychain access prompt (the prompt is
    /// reserved for an actual brain call via `key`). Also true for the env var
    /// and a not-yet-migrated legacy file.
    static var hasKey: Bool {
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return true
        }
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return true
        }
        return FileManager.default.fileExists(atPath: legacyFileURL.path)
    }

    /// Persists (or clears, when empty) the key in the Keychain.
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return deleteKeychain()
        }
        return writeKeychain(trimmed)
    }

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    private static func writeKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        _ = deleteKeychain()

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.demoMode.error("Could not save Anthropic key (status \(status, privacy: .public))")
            return false
        }
        return true
    }

    @discardableResult
    private static func deleteKeychain() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
