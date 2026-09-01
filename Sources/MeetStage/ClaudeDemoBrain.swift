import CoreGraphics
import Foundation

/// Demo Mode's conversational brain, backed by Claude Haiku 4.5 over the raw
/// Messages API (Swift has no official Anthropic SDK). It receives a screenshot
/// of the source window, the list of known controls, and the recent dialogue,
/// and returns a structured action — resolving pronouns and paraphrases the
/// deterministic policy cannot ("now click it", "go back to the home page").
///
/// Hybrid grounding: it prefers to return an `element_id` from the provided list
/// (the coordinator snaps to that element's exact rect), falling back to image
/// coordinates only for on-screen targets that are not in the list.
final class ClaudeDemoBrain: DemoBrain {
    private let model = "claude-haiku-4-5"
    private let endpointString = "https://api.anthropic.com/v1/messages"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        AnthropicKeyStore.hasKey
    }

    /// Max attempts on a 429 before giving up (one retry honoring Retry-After).
    private let maxRetries = 1

    func decide(_ request: DemoBrainRequest) async throws -> DemoBrainDecision? {
        guard !request.apiKey.isEmpty else { throw DemoBrainError.missingKey }
        guard let endpoint = URL(string: endpointString) else {
            throw DemoBrainError.transport("bad endpoint")
        }

        let body = makeRequestBody(request)
        let httpBody = try JSONEncoder().encode(body)

        let modelName = model
        let hasImage = request.imageJPEGBase64 != nil ? "yes" : "no"
        AppLog.demoMode.notice(
            "Anthropic → model=\(modelName, privacy: .public) controls=\(request.controls.count, privacy: .public) image=\(hasImage, privacy: .public) history=\(request.history.count, privacy: .public)"
        )

        var attempt = 0
        while true {
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            urlRequest.httpBody = httpBody

            let started = ContinuousClock.now
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                throw DemoBrainError.transport(error.localizedDescription)
            }
            let elapsedMs = Int((ContinuousClock.now - started) / .milliseconds(1))
            guard let http = response as? HTTPURLResponse else {
                throw DemoBrainError.transport("no HTTP response")
            }
            AppLog.demoMode.notice(
                "Anthropic ← HTTP \(http.statusCode, privacy: .public) in \(elapsedMs, privacy: .public)ms"
            )

            if http.statusCode == 429 {
                let body = String(data: data, encoding: .utf8) ?? ""
                // Out-of-credit/quota won't clear on retry — fail fast so the UI
                // can show a billing message instead of spending another call.
                let isQuota = body.localizedCaseInsensitiveContains("quota")
                if !isQuota, attempt < maxRetries, !Task.isCancelled {
                    attempt += 1
                    let retryAfter = (http.value(forHTTPHeaderField: "retry-after")).flatMap(
                        Double.init)
                    let delay = min(max(retryAfter ?? 2, 0.5), 8)
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw DemoBrainError.http(status: 429, detail: String(body.prefix(300)))
            }
            guard http.statusCode == 200 else {
                let detail = String(data: data, encoding: .utf8)?.prefix(300).description ?? ""
                throw DemoBrainError.http(status: http.statusCode, detail: detail)
            }

            let decoded: AnthropicResponse
            do {
                decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            } catch {
                throw DemoBrainError.transport("decode failed")
            }
            if decoded.stopReason == "max_tokens" {
                AppLog.demoMode.notice("Anthropic reply truncated (max_tokens)")
            }
            let text = decoded.content.compactMap(\.text).joined()
            let decision = DemoBrainDecoding.parse(from: text, allowsClicking: request.allowsClicking)
            if decision == nil {
                AppLog.demoMode.notice(
                    "Anthropic reply (unparsed/none): \(text.prefix(300), privacy: .private)"
                )
            }
            return decision
        }
    }

    // MARK: - Request assembly

    private func makeRequestBody(_ request: DemoBrainRequest) -> AnthropicRequest {
        var messages: [AnthropicMessage] = []
        for turn in request.history {
            messages.append(AnthropicMessage(role: "user", content: [.text(turn.user)]))
            messages.append(AnthropicMessage(role: "assistant", content: [.text(turn.assistant)]))
        }

        var content: [AnthropicContentBlock] = []
        if let image = request.imageJPEGBase64 {
            content.append(.image(base64: image))
        }
        content.append(.text(DemoBrainPrompt.userText(for: request)))
        messages.append(AnthropicMessage(role: "user", content: content))

        return AnthropicRequest(
            model: model,
            maxTokens: 300,
            system: [SystemBlock(text: DemoBrainPrompt.system)],
            messages: messages
        )
    }
}

// MARK: - Wire types

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: [SystemBlock]
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

/// The system prompt is static, so it carries a cache_control breakpoint —
/// Anthropic caches it and re-uses it across calls instead of re-billing it.
private struct SystemBlock: Encodable {
    let text: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("text", forKey: .type)
        try container.encode(text, forKey: .text)
        var cache = container.nestedContainer(keyedBy: CacheKeys.self, forKey: .cacheControl)
        try cache.encode("ephemeral", forKey: .type)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case cacheControl = "cache_control"
    }
    enum CacheKeys: String, CodingKey { case type }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: [AnthropicContentBlock]
}

private enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(base64: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case let .image(base64):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode("image/jpeg", forKey: .mediaType)
            try source.encode(base64, forKey: .data)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct AnthropicResponse: Decodable {
    let content: [AnthropicResponseBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct AnthropicResponseBlock: Decodable {
    let type: String
    let text: String?
}
