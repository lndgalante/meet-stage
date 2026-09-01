import Testing
@testable import MeetStageCore

@Suite("Cloud model configuration")
struct CloudModelConfigurationTests {
    @Test("Uses validated environment overrides ahead of bundle values")
    func environmentOverridesBundle() {
        let configuration = CloudModelConfiguration(
            environment: [
                "BETTERMEETS_ANTHROPIC_MODEL": "claude-next",
                "BETTERMEETS_OPENAI_MODEL": "gpt-next"
            ],
            infoDictionary: [
                "BetterMeetsAnthropicModel": "claude-bundled",
                "BetterMeetsOpenAIModel": "gpt-bundled"
            ]
        )

        #expect(configuration.anthropicModelID == "claude-next")
        #expect(configuration.openAIModelID == "gpt-next")
    }

    @Test("Rejects malformed overrides")
    func rejectsMalformedOverrides() {
        let configuration = CloudModelConfiguration(
            environment: [
                "BETTERMEETS_ANTHROPIC_MODEL": "bad model id",
                "BETTERMEETS_OPENAI_MODEL": ""
            ],
            infoDictionary: [:]
        )

        #expect(configuration.anthropicModelID == CloudModelConfiguration.defaultAnthropicModelID)
        #expect(configuration.openAIModelID == CloudModelConfiguration.defaultOpenAIModelID)
    }
}
