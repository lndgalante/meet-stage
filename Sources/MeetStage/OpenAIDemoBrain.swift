import Foundation
import MeetStageCore

/// The alternate Demo Mode brain, backed by OpenAI's GPT-5.6 Luna over the raw
/// Chat Completions API (Swift has no official OpenAI SDK). It exists so the
/// conversational grounding can be compared head-to-head with `ClaudeDemoBrain`:
/// both receive the identical system prompt (`DemoBrainPrompt`), the same
/// screenshot + control inventory + dialogue, run the same transport
/// (`DemoBrainTransport`), and validate through the same `DemoBrainDecoding`. Only
/// the wire format and model differ.
///
/// Luna is the low-cost, reasoning-capable tier; we pin `reasoning_effort` low and
/// request a strict `json_schema` so the structured action comes back deterministic
/// and fast enough for a live demo.
final class OpenAIDemoBrain: DemoBrain {
    private let model: String
    private let endpointString = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession

    init(model: String = CloudModelConfiguration().openAIModelID) {
        self.model = model
        session = DemoBrainTransport.makeEphemeralSession()
    }

    /// Max attempts on a 429 before giving up (one retry honoring Retry-After).
    private let maxRetries = 1

    func decide(_ request: DemoBrainRequest) async throws -> DemoBrainDecision? {
        guard !request.apiKey.isEmpty else { throw DemoBrainError.missingKey }
        AppLog.demoMode.notice(
            "OpenAI → model=\(self.model, privacy: .public) controls=\(request.controls.count, privacy: .public) image=\(request.imageJPEGBase64 != nil ? "yes" : "no", privacy: .public) history=\(request.history.count, privacy: .public)"
        )
        let text = try await DemoBrainTransport.fetchReply(
            tag: "OpenAI",
            maxRetries: maxRetries,
            session: session,
            makeRequest: { try self.makeURLRequest(request) },
            extractText: Self.extractText(from:)
        )
        let decision = DemoBrainDecoding.parse(from: text, allowsClicking: request.allowsClicking)
        if decision == nil {
            AppLog.demoMode.notice(
                "OpenAI reply (unparsed/none): \(text.prefix(300), privacy: .private)"
            )
        }
        return decision
    }

    // MARK: - Request assembly

    func makeURLRequest(_ request: DemoBrainRequest) throws -> URLRequest {
        guard let endpoint = URL(string: endpointString) else {
            throw DemoBrainError.transport("bad endpoint")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(makeRequestBody(request))
        return urlRequest
    }

    private func makeRequestBody(_ request: DemoBrainRequest) -> OpenAIRequest {
        var messages: [OpenAIMessage] = [
            // Current reasoning models treat developer messages as the
            // application-instruction layer above untrusted user content.
            OpenAIMessage(role: "developer", content: .text(DemoBrainPrompt.system))
        ]
        for turn in request.history {
            messages.append(OpenAIMessage(role: "user", content: .text(turn.user)))
            messages.append(OpenAIMessage(role: "assistant", content: .text(turn.assistant)))
        }

        var parts: [OpenAIPart] = []
        if let image = request.imageJPEGBase64 {
            parts.append(.image(dataURL: "data:image/jpeg;base64,\(image)"))
        }
        parts.append(.text(DemoBrainPrompt.userText(for: request)))
        messages.append(OpenAIMessage(role: "user", content: .parts(parts)))

        return OpenAIRequest(
            model: model,
            // Reasoning tokens count against this budget, so leave headroom above
            // the small JSON answer; keep effort low for live-demo latency.
            maxCompletionTokens: 700,
            reasoningEffort: "low",
            messages: messages
        )
    }

    // MARK: - Response parsing

    private static func extractText(from data: Data) throws -> String {
        let decoded: OpenAIResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw DemoBrainError.transport("decode failed")
        }
        let choice = decoded.choices.first
        if choice?.finishReason == "length" {
            AppLog.demoMode.notice("OpenAI reply truncated (length)")
        }
        return choice?.message.content ?? ""
    }
}

// MARK: - Request wire types

private struct OpenAIRequest: Encodable {
    let model: String
    let maxCompletionTokens: Int
    let reasoningEffort: String
    let messages: [OpenAIMessage]
    let responseFormat = OpenAIResponseFormat()

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case responseFormat = "response_format"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: OpenAIContent
}

/// A message's content is either a bare string (developer/history turns) or an
/// array of typed parts (the final user turn, which carries the screenshot).
private enum OpenAIContent: Encodable {
    case text(String)
    case parts([OpenAIPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .parts(parts): try container.encode(parts)
        }
    }
}

private enum OpenAIPart: Encodable {
    case text(String)
    case image(dataURL: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case let .image(dataURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": dataURL], forKey: .imageURL)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

private struct OpenAIResponseFormat: Encodable {
    let type = "json_schema"
    let jsonSchema = DemoActionSchema()

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// Strict JSON schema matching `DemoBrainDecoding.RawBrainDecision`. Under
/// `strict`, every property must appear in `required` (nullable ones use a
/// `[type, "null"]` union) and `additionalProperties` must be false.
private struct DemoActionSchema: Encodable {
    let name = "demo_action"
    let strict = true
    let schema = Schema()

    struct Schema: Encodable {
        let type = "object"
        let properties = Properties()
        let required = ["action", "element_id", "point", "text", "label"]
        let additionalProperties = false

        struct Properties: Encodable {
            let action = SchemaProperty(
                type: .single("string"),
                enumValues: ["highlight", "click", "type", "circle", "spotlight", "zoom", "none"]
            )
            let elementID = SchemaProperty(type: .union(["integer", "null"]))
            let point = SchemaProperty(
                type: .union(["array", "null"]),
                items: .init(type: "number")
            )
            let text = SchemaProperty(type: .union(["string", "null"]))
            let label = SchemaProperty(type: .single("string"))

            enum CodingKeys: String, CodingKey {
                case action
                case elementID = "element_id"
                case point, text, label
            }
        }
    }
}

/// A JSON-schema property whose `type` is a single string or a `[type, "null"]`
/// nullable union. `enum`/`items` are omitted when nil (synthesized as optional).
private struct SchemaProperty: Encodable {
    let type: TypeField
    var enumValues: [String]?
    var items: Items?

    init(type: TypeField, enumValues: [String]? = nil, items: Items? = nil) {
        self.type = type
        self.enumValues = enumValues
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case type
        case enumValues = "enum"
        case items
    }

    struct Items: Encodable { let type: String }

    enum TypeField: Encodable {
        case single(String)
        case union([String])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .single(value): try container.encode(value)
            case let .union(values): try container.encode(values)
            }
        }
    }
}

// MARK: - Response wire types

private struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let content: String?
    }
}
