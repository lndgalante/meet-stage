import Foundation

/// The OpenAI API key store (GPT-5.6 Luna brain). A plain `KeychainSecret` — no
/// legacy migration — kept as a named type so `DemoBrainProvider.keyStore` and the
/// brain can refer to it directly.
struct OpenAIKeyStore: DemoKeyStore {
    private let secret = KeychainSecret(
        service: "com.lndgalante.bettermeets.openai",
        account: "conversational-brain",
        environmentVariable: "OPENAI_API_KEY",
        legacyServices: ["dev.poc.meetstage.openai"]
    )

    var key: String? { secret.key }
    var hasKey: Bool { secret.hasKey }

    @discardableResult
    func save(_ value: String) -> Bool {
        secret.save(value)
    }
}
