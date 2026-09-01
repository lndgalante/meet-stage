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
    /// Whether a key exists without reading Keychain secret data, so it never
    /// triggers an access prompt. A migration wrapper may inspect its legacy file.
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
    var legacyServices: [String] = []

    var key: String? {
        if let env = environmentOverride { return env }
        if let current = read(service: service) { return current }

        for legacyService in legacyServices {
            guard let legacy = read(service: legacyService) else { continue }
            if write(legacy) {
                _ = delete(service: legacyService)
            }
            return legacy
        }
        return nil
    }

    var hasKey: Bool {
        if environmentOverride != nil { return true }
        if itemExists(service: service) { return true }
        return legacyServices.contains { itemExists(service: $0) }
    }

    private func itemExists(service: String) -> Bool {
        var query = baseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let removedCurrent = delete(service: service)
            let removedLegacy = legacyServices.allSatisfy { delete(service: $0) }
            return removedCurrent && removedLegacy
        }

        guard write(trimmed) else { return false }
        return legacyServices.allSatisfy { delete(service: $0) }
    }

    private var environmentOverride: String? {
        let value = ProcessInfo.processInfo.environment[environmentVariable]
        return (value?.isEmpty ?? true) ? nil : value
    }

    // MARK: - Keychain primitives

    private func baseQuery(service: String? = nil) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: account
        ]
    }

    private func read(service: String) -> String? {
        var query = baseQuery(service: service)
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

        let updatedAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            updatedAttributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            logWriteFailure(updateStatus)
            return false
        }

        var attributes = baseQuery()
        for (key, value) in updatedAttributes {
            attributes[key] = value
        }
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logWriteFailure(addStatus)
            return false
        }
        return true
    }

    private func logWriteFailure(_ status: OSStatus) {
        AppLog.demoMode.error(
            "Could not save \(service, privacy: .public) key (status \(status, privacy: .public))"
        )
    }

    @discardableResult
    private func delete(service: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
