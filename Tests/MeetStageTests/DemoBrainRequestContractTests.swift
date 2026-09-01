import CoreGraphics
import Foundation
import Testing
@testable import MeetStage

@Suite("Cloud brain request contracts")
struct DemoBrainRequestContractTests {
    private let request = DemoBrainRequest(
        apiKey: "test-key",
        transcript: "Show the Save button",
        history: [],
        controls: [DemoBrainControl(id: 7, label: "Save", role: "button")],
        imageJPEGBase64: nil,
        imagePixelSize: CGSize(width: 800, height: 600),
        allowsClicking: false
    )

    @Test("Anthropic request preserves the Messages API contract")
    func anthropicContract() throws {
        let urlRequest = try ClaudeDemoBrain(model: "claude-contract-test")
            .makeURLRequest(request)
        let decodedBody = try jsonBody(urlRequest)
        let body = try #require(decodedBody)

        #expect(urlRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(body["model"] as? String == "claude-contract-test")
        #expect(body["max_tokens"] as? Int == 300)
        #expect((body["system"] as? [[String: Any]])?.first?["type"] as? String == "text")
        #expect((body["messages"] as? [[String: Any]])?.last?["role"] as? String == "user")
    }

    @Test("OpenAI request preserves reasoning and structured-output fields")
    func openAIContract() throws {
        let urlRequest = try OpenAIDemoBrain(model: "gpt-contract-test")
            .makeURLRequest(request)
        let decodedBody = try jsonBody(urlRequest)
        let body = try #require(decodedBody)
        let responseFormat = try #require(body["response_format"] as? [String: Any])

        #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(body["model"] as? String == "gpt-contract-test")
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["max_completion_tokens"] as? Int == 700)
        #expect(responseFormat["type"] as? String == "json_schema")
        #expect((responseFormat["json_schema"] as? [String: Any])?["strict"] as? Bool == true)
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any]? {
        guard let data = request.httpBody else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
