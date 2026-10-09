import Foundation
import Testing

@testable import MeetStage

@Suite("Demo model client")
struct DemoModelClientTests {
    private let request = ScoutTurnRequest(
        prompt: "Show Transactions", appName: "Ledger Wallet", engine: .electron, start: "native app", outline: [],
        facts: [], turn: 1, maxTurns: 24,
        screenshot: DemoWindowScreenshot.Capture(base64JPEG: "AA==", pixelSize: CGSize(width: 1, height: 1)),
        elements: "0 link \"Transactions\" 10,300,100,40", correction: nil)

    @Test("Scout requests use auto tool choice, strict tools without unsupported constraints, and stable bytes")
    func scoutRequestShape() throws {
        let body = DemoModelClient.scoutBody(request, effort: "medium")
        let data = try DemoModelClient.encode(body)
        #expect(data == (try DemoModelClient.encode(DemoModelClient.scoutBody(request, effort: "medium"))))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""model":"claude-opus-5-5""#))
        #expect(json.contains(#""tool_choice":{"disable_parallel_tool_use":true,"type":"auto"}"#))
        #expect(json.contains(#""fallbacks":"default""#))
        #expect(!json.contains("\"thinking\""))
        for keyword in ["minimum", "maximum", "maxItems", "minItems", "minLength", "maxLength", "uniqueItems"] {
            #expect(!json.contains("\"\(keyword)\""))
        }
        let tools = try #require(body["tools"] as? [[String: Any]])
        for tool in tools {
            #expect(tool["strict"] as? Bool == true)
            let schema = try #require(tool["input_schema"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false)
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(Set(schema["required"] as? [String] ?? []) == Set(properties.keys))
        }
    }

    private func response(_ content: [[String: Any]], stop: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": "claude-opus-5-5", "stop_reason": stop, "content": content,
            "usage": ["input_tokens": 1_000, "output_tokens": 100, "cache_read_input_tokens": 2_000],
        ])
    }

    private func client(_ responses: [(Int, Data)]) -> DemoModelClient {
        let queue = ResponseQueue(responses)
        return DemoModelClient(
            send: { request in
                let (status, data) = queue.next()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (data, response)
            },
            sleep: { _ in })
    }

    @Test("Reads the tool call after thinking blocks and accounts for its cost")
    func decodesToolUse() async throws {
        let data = try response(
            [
                ["type": "thinking", "thinking": ""],
                [
                    "type": "tool_use", "id": "t", "name": "click",
                    "input": ["elementID": 0, "title": "Open Transactions", "script": "", "outline": ["A", "B", "C"]],
                ],
            ], stop: "tool_use")
        let reply = try await client([(200, data)]).scoutTurn(request, key: "k")
        #expect(reply.decision == .click(elementID: 0, title: "Open Transactions", script: ""))
        #expect(reply.outline == ["A", "B", "C"])
        #expect(reply.costMicroUSD == 1_000 * 4 + 100 * 20 + 400)
    }

    @Test("Prose without a tool call, refusals and overloads are handled")
    func responseMatrix() async throws {
        let prose = try response([["type": "text", "text": "I think we should click it."]], stop: "end_turn")
        do {
            _ = try await client([(200, prose)]).scoutTurn(request, key: "k")
            Issue.record("Expected a failure")
        } catch let failure as DemoModelFailure {
            #expect(failure.underlying as? DemoModelError == .noToolCall("I think we should click it."))
            // A failed call still costs money and counts toward the build limit.
            #expect(failure.costMicroUSD == 6_400)
        }
        let refusal = try response([], stop: "refusal")
        do {
            _ = try await client([(200, refusal)]).scoutTurn(request, key: "k")
            Issue.record("Expected a failure")
        } catch let failure as DemoModelFailure {
            #expect(failure.underlying as? DemoError == .modelDeclined)
        }

        let ok = try response(
            [["type": "tool_use", "id": "t", "name": "blocked", "input": ["reason": "No such page", "closestAlternative": ""]]],
            stop: "tool_use")
        let reply = try await client([(529, Data("{}".utf8)), (200, ok)]).scoutTurn(request, key: "k")
        #expect(reply.decision == .blocked(reason: "No such page", alternative: ""))
    }

    @Test("The script language reaches the build, the rewrite and the ideas; automatic follows the request")
    func scriptLanguage() throws {
        func text(_ body: [String: Any]) throws -> String {
            try #require(String(data: try DemoModelClient.encode(body), encoding: .utf8))
        }
        var scout = request
        scout.language = .spanish
        #expect(try text(DemoModelClient.scoutBody(scout, effort: "medium")).contains("in Spanish, as a native speaker"))
        #expect(try text(DemoModelClient.scoutBody(request, effort: "medium")).contains("language of the presenter's request"))

        var script = ScriptRequest(
            prompt: "Show Transactions", appName: "Ledger Wallet", start: "Home", outline: [],
            steps: [.init(kind: "Click", target: "Transactions", title: "Open Transactions", script: "", isNavigation: true)],
            tone: .conversational, audience: "")
        #expect(try text(DemoModelClient.scriptBody(script)).contains("language of the presenter's request"))
        script.language = .spanish
        #expect(try text(DemoModelClient.scriptBody(script)).contains("in Spanish, as a native speaker"))
        #expect(ScriptLanguage.spanish.label == "Español")
    }

    @Test("Script requests list every step and accept only a complete answer")
    func scriptRequests() throws {
        let request = ScriptRequest(
            prompt: "Show Transactions", appName: "Ledger Wallet", start: "Home", outline: ["Open", "Explain"],
            steps: [
                .init(kind: "Click", target: "Transactions", title: "Open Transactions", script: "", isNavigation: true),
                .init(kind: "Spotlight", target: "row 1 in operations", title: "Show a row", script: "A row.", isNavigation: false),
            ], tone: .concise, audience: "investors")
        let json = try #require(String(data: try DemoModelClient.encode(DemoModelClient.scriptBody(request)), encoding: .utf8))
        #expect(json.contains(#""tool_choice":{"disable_parallel_tool_use":true,"type":"auto"}"#))
        #expect(json.contains("exactly 2 steps"))
        #expect(json.contains("investors"))
        let draft = try DemoModelClient.decodeScript(
            ["opening": "Hi", "closing": "Bye", "steps": [["title": "Open", "script": "Let's go."], ["title": "Row", "script": "This row."]]],
            stepCount: 2)
        #expect(draft.scripts == ["Let's go.", "This row."])
        #expect(draft.startLabel.isEmpty)
        let schema = try #require(
            (DemoModelClient.scriptBody(request)["tools"] as? [[String: Any]])?.first?["input_schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("startLabel") == true)
        let labelled = try DemoModelClient.decodeScript(
            [
                "opening": "Hi", "closing": "Bye", "startLabel": "  the   Scheduled page ",
                "steps": [["title": "Open", "script": ""], ["title": "Row", "script": ""]],
            ], stepCount: 2)
        #expect(labelled.startLabel == "the Scheduled page")
        #expect(throws: DemoError.invalidResponse) {
            try DemoModelClient.decodeScript(["opening": "", "closing": "", "steps": []], stepCount: 2)
        }
    }

    @Test("Finish carries a start label, and an answer without one still finishes")
    func decodesFinishStartLabel() throws {
        var input: [String: Any] = [
            "title": "Schedule a daily summary", "startDescription": "ChatGPT on the Scheduled page",
            "startLabel": " the Scheduled page ", "closingScript": "That's it.",
        ]
        let finish = try DemoModelClient.decodeScout("finish", input)
        #expect(
            finish.decision
                == .finish(
                    title: "Schedule a daily summary", startDescription: "ChatGPT on the Scheduled page",
                    startLabel: "the Scheduled page", closingScript: "That's it."))
        input["startLabel"] = nil
        guard case .finish(_, _, let startLabel, _) = try DemoModelClient.decodeScout("finish", input).decision else {
            Issue.record("Expected finish")
            return
        }
        #expect(startLabel.isEmpty)
        let finishTool = try #require(DemoModelClient.scoutTools.first { $0["name"] as? String == "finish" })
        let schema = try #require(finishTool["input_schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("startLabel") == true)
    }

    @Test("Fallback attempts are each billed at their own model's rates")
    func fallbackCost() {
        let usage: [String: Any] = [
            "iterations": [
                ["type": "message", "model": "claude-opus-5-5", "input_tokens": 1_000, "output_tokens": 10],
                ["type": "fallback_message", "model": "claude-opus-4-8", "input_tokens": 1_000, "output_tokens": 100],
            ]
        ]
        #expect(DemoModelClient.cost(model: "claude-opus-4-8", usage: usage) == 4_000 + 200 + 5_000 + 2_500)
    }
}

private final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    init(_ responses: [(Int, Data)]) { self.responses = responses }
    func next() -> (Int, Data) {
        lock.withLock { responses.isEmpty ? (500, Data()) : responses.removeFirst() }
    }
}
