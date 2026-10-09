import Foundation

struct DemoRequestFailure: Sendable {
    let status: Int
    let reason: String?
    let type: String?
    let requestID: String?
    let operation: String
    let model: String

    init(response: HTTPURLResponse, data: Data, operation: String, model: String, key: String) {
        status = response.statusCode
        self.operation = operation
        self.model = model
        let body =
            data.count <= 65_536
            ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
        let error = body?["error"] as? [String: Any]
        type = Self.identifier(error?["type"] as? String)
        requestID =
            Self.identifier(response.value(forHTTPHeaderField: "request-id"))
            ?? Self.identifier(body?["request_id"] as? String)
        if var message = error?["message"] as? String {
            if !key.isEmpty { message = message.replacingOccurrences(of: key, with: "[redacted]") }
            message = message.replacingOccurrences(
                of: #"sk-ant-[A-Za-z0-9_-]+|[A-Za-z0-9+/=]{80,}"#,
                with: "[redacted]", options: .regularExpression
            )
            let text = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            reason = text.isEmpty ? nil : String(text.prefix(2_000))
        } else {
            reason = nil
        }
    }

    var message: String {
        if let reason { return "Anthropic (\(status)): \(reason)" }
        switch status {
        case 401: return "Anthropic didn’t accept the API key (401). Check Settings › Demos."
        case 403: return "The API key doesn’t have permission for this request (403). Check your Anthropic account."
        case 429: return "Anthropic’s request limit was reached (429). Try again shortly or check your account limits."
        default: return "Anthropic returned HTTP \(status) without an error message. Copy Details to investigate."
        }
    }

    var details: String {
        """
        BetterMeets real-time demo
        Service: Anthropic Messages API
        Operation: \(operation)
        Model: \(model)
        HTTP status: \(status)
        Error type: \(type ?? "not provided")
        Request ID: \(requestID ?? "not provided")
        Reason: \(reason ?? "No error message in the response.")
        """
    }

    private static func identifier(_ value: String?) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard let value, !value.isEmpty, value.count <= 128,
            value.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return value
    }
}
