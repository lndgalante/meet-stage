import Foundation

/// Central model identifiers with validated deployment overrides. Keeping model
/// lifecycle configuration outside provider clients makes migrations a config
/// change instead of a networking-code edit.
public struct CloudModelConfiguration: Equatable, Sendable {
    public static let defaultAnthropicModelID = "claude-haiku-4-5"
    public static let defaultOpenAIModelID = "gpt-5.6-luna"

    public let anthropicModelID: String
    public let openAIModelID: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        anthropicModelID = Self.resolvedModelID(
            environmentValue: environment["BETTERMEETS_ANTHROPIC_MODEL"],
            bundledValue: infoDictionary["BetterMeetsAnthropicModel"] as? String,
            fallback: Self.defaultAnthropicModelID
        )
        openAIModelID = Self.resolvedModelID(
            environmentValue: environment["BETTERMEETS_OPENAI_MODEL"],
            bundledValue: infoDictionary["BetterMeetsOpenAIModel"] as? String,
            fallback: Self.defaultOpenAIModelID
        )
    }

    private static func resolvedModelID(
        environmentValue: String?,
        bundledValue: String?,
        fallback: String
    ) -> String {
        for candidate in [environmentValue, bundledValue] {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidModelID(trimmed) { return trimmed }
        }
        return fallback
    }

    private static func isValidModelID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
        }
    }
}
