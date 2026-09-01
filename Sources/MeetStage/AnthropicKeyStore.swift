import Foundation

/// The Anthropic API key store (Claude Haiku 4.5 brain). A `KeychainSecret` does
/// all the storage; this adds only the one-time migration that imports (and
/// deletes) any key left by the earlier `~/.config/bettermeets` plaintext file.
struct AnthropicKeyStore: DemoKeyStore {
    private let secret = KeychainSecret(
        service: "dev.poc.meetstage.anthropic",
        account: "conversational-brain",
        environmentVariable: "ANTHROPIC_API_KEY"
    )

    private var legacyFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bettermeets/anthropic-key")
    }

    var key: String? {
        if let stored = secret.key { return stored }
        // One-time migration from the deprecated plaintext file store.
        if let fileKey = try? String(contentsOf: legacyFileURL, encoding: .utf8) {
            let trimmed = fileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Delete the legacy plaintext only after Keychain persistence
                // succeeds; a transient Keychain failure must not lose the key.
                if secret.save(trimmed) {
                    try? FileManager.default.removeItem(at: legacyFileURL)
                }
                return trimmed
            }
        }
        return nil
    }

    var hasKey: Bool {
        secret.hasKey || FileManager.default.fileExists(atPath: legacyFileURL.path)
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        secret.save(value)
    }
}
