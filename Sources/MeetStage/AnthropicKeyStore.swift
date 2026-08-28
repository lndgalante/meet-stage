import Foundation

/// Local, out-of-binary storage for the Anthropic API key used by the Demo Mode
/// conversational brain. The key lives in `~/.config/bettermeets/anthropic-key`
/// (or the `ANTHROPIC_API_KEY` environment variable), never in the app bundle or
/// UserDefaults — mirroring how Clicky/OpenClicky keep keys in a local secrets
/// file. This is a PoC-grade store; a shipping build should use the Keychain.
enum AnthropicKeyStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bettermeets/anthropic-key")
    }

    static var key: String? {
        if let fileKey = try? String(contentsOf: fileURL, encoding: .utf8) {
            let trimmed = fileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
            !envKey.isEmpty
        {
            return envKey
        }
        return nil
    }

    static var hasKey: Bool {
        key != nil
    }

    /// Persists (or clears, when empty) the key to the local secrets file.
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if trimmed.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: fileURL.path
                )
            }
            return true
        } catch {
            AppLog.demoMode.error(
                "Could not save Anthropic key: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
