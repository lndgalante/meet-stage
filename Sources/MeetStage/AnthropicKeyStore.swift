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
        if let stored = secret.key {
            // A user may have saved a Keychain value before the lazy migration
            // ran. Still remove the obsolete plaintext copy when we encounter it.
            removeLegacyFileIfPresent()
            return stored
        }
        // One-time migration from the deprecated plaintext file store.
        if let fileKey = try? String(contentsOf: legacyFileURL, encoding: .utf8) {
            let trimmed = fileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Delete the legacy plaintext only after Keychain persistence
                // succeeds; a transient Keychain failure must not lose the key.
                if secret.save(trimmed) {
                    removeLegacyFileIfPresent()
                }
                return trimmed
            }
        }
        return nil
    }

    var hasKey: Bool {
        if secret.hasKey { return true }
        guard let legacyValue = try? String(contentsOf: legacyFileURL, encoding: .utf8) else {
            return false
        }
        return !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        guard secret.save(value) else { return false }
        // Saving a replacement or clearing the setting must also remove any
        // pre-Keychain file; otherwise clearing could silently resurrect it.
        return removeLegacyFileIfPresent()
    }

    @discardableResult
    private func removeLegacyFileIfPresent() -> Bool {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            return true
        }
        do {
            try FileManager.default.removeItem(at: legacyFileURL)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return true
        } catch {
            AppLog.demoMode.error(
                "Could not remove the legacy Anthropic key file: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
