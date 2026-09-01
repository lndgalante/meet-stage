import Foundation

/// The alternate Demo Mode brain, backed by OpenAI's GPT-5.6 Luna over the raw
/// Chat Completions API (Swift has no official OpenAI SDK). It exists so the
/// conversational grounding can be compared head-to-head with `ClaudeDemoBrain`:
/// both receive the identical system prompt (`DemoBrainPrompt`), the same
/// screenshot + control inventory + dialogue, and run their reply through the
/// same validation (`DemoBrainDecoding`). Only the wire format and model differ.
///
/// Luna is the low-cost, reasoning-capable tier; we pin `reasoning_effort` low and
/// request a strict `json_schema` so the structured action comes back deterministic
/// and fast enough for a live demo.
final class OpenAIDemoBrain: DemoBrain {
    private let model = "gpt-5.6-luna"
    private let endpointString = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        OpenAIKeyStore.hasKey
    }

    /// Max attempts on a 429 before giving up (one retry honoring Retry-After).
    private let maxRetries = 1

    func decide(_ request: DemoBrainRequest) async throws -> DemoBrainDecision? {
        guard !request.apiKey.isEmpty else { throw DemoBrainError.missingKey }
        guard let endpoint = URL(string: endpointString) else {
            throw DemoBrainError.transport("bad endpoint")
        }

        let httpBody: Data
        do {
            httpBody = try JSONSerialization.data(withJSONObject: makeRequestBody(request))
        } catch {
            throw DemoBrainError.transport("encode failed")
        }

        let modelName = model
        let hasImage = request.imageJPEGBase64 != nil ? "yes" : "no"
        AppLog.demoMode.notice(
            "OpenAI → model=\(modelName, privacy: .public) controls=\(request.controls.count, privacy: .public) image=\(hasImage, privacy: .public) history=\(request.history.count, privacy: .public)"
        )

        var attempt = 0
        while true {
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
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
                "OpenAI ← HTTP \(http.statusCode, privacy: .public) in \(elapsedMs, privacy: .public)ms"
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
            let text = choice?.message.content ?? ""
            let decision = DemoBrainDecoding.parse(from: text, allowsClicking: request.allowsClicking)
            if decision == nil {
                AppLog.demoMode.notice(
                    "OpenAI reply (unparsed/none): \(text.prefix(300), privacy: .private)"
                )
            }
            return decision
        }
    }

    // MARK: - Request assembly

    private func makeRequestBody(_ request: DemoBrainRequest) -> [String: Any] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": DemoBrainPrompt.system]
        ]
        for turn in request.history {
            messages.append(["role": "user", "content": turn.user])
            messages.append(["role": "assistant", "content": turn.assistant])
        }

        var parts: [[String: Any]] = []
        if let image = request.imageJPEGBase64 {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(image)"]
            ])
        }
        parts.append(["type": "text", "text": DemoBrainPrompt.userText(for: request)])
        messages.append(["role": "user", "content": parts])

        return [
            "model": model,
            // Reasoning tokens count against this budget, so leave headroom above
            // the small JSON answer; keep effort low for live-demo latency.
            "max_completion_tokens": 700,
            "reasoning_effort": "low",
            "messages": messages,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "demo_action",
                    "strict": true,
                    "schema": Self.responseSchema
                ]
            ]
        ]
    }

    /// Strict JSON schema matching `DemoBrainDecoding.RawBrainDecision`. Under
    /// `strict`, every property must be listed in `required` (nullable ones use a
    /// `[type, "null"]` union) and `additionalProperties` must be false.
    private static var responseSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["highlight", "click", "type", "circle", "spotlight", "zoom", "none"]
                ],
                "element_id": ["type": ["integer", "null"]],
                "point": ["type": ["array", "null"], "items": ["type": "number"]],
                "text": ["type": ["string", "null"]],
                "label": ["type": "string"]
            ],
            "required": ["action", "element_id", "point", "text", "label"],
            "additionalProperties": false
        ]
    }
}

// MARK: - Wire types

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
