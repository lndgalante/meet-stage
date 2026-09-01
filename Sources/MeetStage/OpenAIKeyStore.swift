import Foundation
import Security

/// Keychain-backed storage for the OpenAI API key used by the alternate Demo Mode
/// brain (`OpenAIDemoBrain`, GPT-5.6 Luna). Mirrors `AnthropicKeyStore`: the key
/// is a paid bearer credential, so it lives in the login Keychain
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in the bundle,
/// UserDefaults, or a plaintext file. `OPENAI_API_KEY` is a dev override.
enum OpenAIKeyStore {
    private static let service = "dev.poc.meetstage.openai"
    private static let account = "conversational-brain"

    static var key: String? {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            !envKey.isEmpty
        {
            return envKey
        }
        return readKeychain()
    }

    /// Whether a key exists — an attribute-only check that does NOT read the
    /// secret, so it never triggers a Keychain access prompt.
    static var hasKey: Bool {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return true
        }
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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
            AppLog.demoMode.error("Could not save OpenAI key (status \(status, privacy: .public))")
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
