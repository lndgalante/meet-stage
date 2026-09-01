import Foundation

/// The request/retry/error loop shared by every cloud `DemoBrain`. Providers
/// supply only how to build their request and how to pull the reply text out of a
/// 200 body; this owns timing, the response-status log, the 429/quota/retry rule,
/// and the mapping to `DemoBrainError`. One loop instead of one per provider.
enum DemoBrainTransport {
    static func fetchReply(
        tag: String,
        maxRetries: Int,
        session: URLSession,
        makeRequest: () throws -> URLRequest,
        extractText: (Data) throws -> String
    ) async throws -> String {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest()
        } catch {
            throw DemoBrainError.transport("request build failed")
        }

        var attempt = 0
        while true {
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
                "\(tag, privacy: .public) ← HTTP \(http.statusCode, privacy: .public) in \(elapsedMs, privacy: .public)ms"
            )

            if http.statusCode == 429 {
                let body = String(data: data, encoding: .utf8) ?? ""
                // Out-of-credit/quota won't clear on retry — fail fast so the UI
                // can show a billing message instead of spending another call.
                let isQuota = body.localizedCaseInsensitiveContains("quota")
                if !isQuota, attempt < maxRetries, !Task.isCancelled {
                    attempt += 1
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
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

            return try extractText(data)
        }
    }
}
