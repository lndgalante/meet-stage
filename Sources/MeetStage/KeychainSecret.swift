import Foundation
import Security

/// A stored API key for the conversational brain: read, written, and cleared, and
/// exposed as a value so each provider is one small instance instead of a
/// hand-copied Keychain store. The secret is a paid bearer credential, so it lives
/// in the login Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never in
/// the app bundle, UserDefaults, or a plaintext file.
protocol DemoKeyStore: Sendable {
    /// The stored secret, reading the Keychain data (which may prompt for access).
    var key: String? { get }
    /// Whether a key exists — attribute-only, so it never triggers an access prompt.
    var hasKey: Bool { get }
    /// Persists the key, or clears it when the value is empty.
    @discardableResult func save(_ value: String) -> Bool
}

/// One Keychain-stored secret, addressed by service + account, with an environment
/// variable override for local development. Owns every `Security.framework` call so
/// the CRUD lives in exactly one place.
struct KeychainSecret: DemoKeyStore {
    let service: String
    let account: String
    let environmentVariable: String

    var key: String? {
        if let env = environmentOverride { return env }
        return read()
    }

    var hasKey: Bool {
        if environmentOverride != nil { return true }
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? delete() : write(trimmed)
    }

    private var environmentOverride: String? {
        let value = ProcessInfo.processInfo.environment[environmentVariable]
        return (value?.isEmpty ?? true) ? nil : value
    }

    // MARK: - Keychain primitives

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func read() -> String? {
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
    private func write(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        _ = delete()

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.demoMode.error(
                "Could not save \(service, privacy: .public) key (status \(status, privacy: .public))"
            )
            return false
        }
        return true
    }

    @discardableResult
    private func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
