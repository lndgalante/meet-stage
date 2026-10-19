import Foundation

/// The tokens a model call used, as the API reported them. Thinking tokens are
/// nil unless the response itemized them.
struct DemoTokenUsage: Equatable, Sendable {
    var input = 0
    var output = 0
    /// Part of `output`.
    var thinking: Int?
    var cacheRead = 0
    var cacheWrite = 0

    init() {}

    /// Reads a response's `usage`. With server-side fallbacks the top level covers
    /// only the attempt that answered, so every attempt in `iterations` is summed instead.
    init(usage: [String: Any]) {
        if let iterations = usage["iterations"] as? [[String: Any]], !iterations.isEmpty {
            self = iterations.reduce(DemoTokenUsage()) { total, iteration in
                total + DemoTokenUsage(usage: iteration.filter { $0.key != "iterations" })
            }
            return
        }
        func tokens(_ key: String) -> Int { usage[key] as? Int ?? 0 }
        input = tokens("input_tokens")
        output = tokens("output_tokens")
        cacheRead = tokens("cache_read_input_tokens")
        cacheWrite = tokens("cache_creation_input_tokens")
        thinking = (usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"] as? Int
    }

    static func + (lhs: DemoTokenUsage, rhs: DemoTokenUsage) -> DemoTokenUsage {
        var sum = DemoTokenUsage()
        sum.input = lhs.input + rhs.input
        sum.output = lhs.output + rhs.output
        sum.thinking = lhs.thinking.map { $0 + (rhs.thinking ?? 0) } ?? rhs.thinking
        sum.cacheRead = lhs.cacheRead + rhs.cacheRead
        sum.cacheWrite = lhs.cacheWrite + rhs.cacheWrite
        return sum
    }

    static func += (lhs: inout DemoTokenUsage, rhs: DemoTokenUsage) {
        lhs = lhs + rhs
    }

    /// “in=1200 out=340 think=120 cacheRead=9000 cacheWrite=0”, with no thinking count when there's none.
    var fields: String {
        [
            "in=\(input)", "out=\(output)", thinking.map { "think=\($0)" }, "cacheRead=\(cacheRead)",
            "cacheWrite=\(cacheWrite)"
        ]
        .compactMap { $0 }.joined(separator: " ")
    }
}

/// Where one scout turn or replay step spent its time, for the timings log. It
/// holds numbers and the names of routes only, never anything from the window,
/// so its lines can be logged in the clear.
struct DemoTurnTimings: Equatable, Sendable {
    /// Waiting for Claude, across every call the turn made.
    var model: Duration = .zero
    var modelCalls = 0
    var tokens = DemoTokenUsage()
    /// Reading the window through Accessibility to look and to settle, and how
    /// many elements the last read kept.
    var walk: Duration = .zero
    var walks = 0
    var nodes = 0
    /// The turn took the look the last action settled on instead of reading the window again.
    var reusedLook = false
    var screenshot: Duration = .zero
    /// Waiting for the app to settle after actions (a replay step: for its screen
    /// and targets, and for a click to show), and the looks that took.
    var settle: Duration = .zero
    var settlePolls = 0
    /// Waits that ran out of time before the app settled.
    var unsettled = 0
    /// Waiting for the person to pause before the screen could be borrowed.
    var pauseWait: Duration = .zero
    /// The route that carried each input, in order; nil when there was nothing to do.
    var routes: [DemoInputRoute?] = []
    var total: Duration = .zero

    /// One log line: `prefix`, then every number. Durations are in milliseconds.
    func line(_ prefix: String) -> String {
        let routeNames = routes.isEmpty ? "-" : routes.map(DemoInputRoute.logName).joined(separator: ",")
        return [
            prefix, "total=\(total.logMilliseconds)", "model=\(model.logMilliseconds)", "calls=\(modelCalls)",
            tokens.fields, "walk=\(walk.logMilliseconds)", "walks=\(walks)", "nodes=\(nodes)",
            "reused=\(reusedLook)", "screenshot=\(screenshot.logMilliseconds)", "settle=\(settle.logMilliseconds)",
            "polls=\(settlePolls)", "unsettled=\(unsettled)", "pauseWait=\(pauseWait.logMilliseconds)",
            "routes=\(routeNames)"
        ].joined(separator: " ")
    }
}

/// A build's or a replay's turns added up, for the one line logged when it ends.
struct DemoRunTimings: Equatable, Sendable {
    private(set) var turns = 0
    private(set) var model: Duration = .zero
    private(set) var modelCalls = 0
    private(set) var tokens = DemoTokenUsage()
    private(set) var settle: Duration = .zero
    private(set) var pauseWait: Duration = .zero
    private(set) var reusedLooks = 0
    /// How many inputs each route carried, by name, with “none” for nothing to do.
    private(set) var routes: [String: Int] = [:]

    mutating func add(_ turn: DemoTurnTimings) {
        turns += 1
        model += turn.model
        modelCalls += turn.modelCalls
        tokens += turn.tokens
        settle += turn.settle
        pauseWait += turn.pauseWait
        if turn.reusedLook { reusedLooks += 1 }
        for route in turn.routes { routes[DemoInputRoute.logName(route), default: 0] += 1 }
    }

    /// One log line: `prefix`, then the totals, with routes sorted by name so the
    /// line reads the same way every time.
    func summary(_ prefix: String) -> String {
        let counts = routes.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }
        let histogram = counts.isEmpty ? "-" : counts.joined(separator: ",")
        return [
            prefix, "turns=\(turns)", "model=\(model.logMilliseconds)", "calls=\(modelCalls)", tokens.fields,
            "settle=\(settle.logMilliseconds)", "pauseWait=\(pauseWait.logMilliseconds)", "reused=\(reusedLooks)",
            "routes=\(histogram)"
        ].joined(separator: " ")
    }
}

extension DemoInputRoute {
    /// The route's name in the timings log; “none” when there was nothing to do.
    static func logName(_ route: DemoInputRoute?) -> String {
        switch route {
        case .accessibility: "accessibility"
        case .browser: "browser"
        case .selectedText: "selectedText"
        case .borrowedScreen: "borrowedScreen"
        case .foreground: "foreground"
        case nil: "none"
        }
    }
}

extension DemoAction {
    /// The action's kind in the timings log, never its target or text.
    var logName: String {
        switch self {
        case .click: "click"
        case .typeText: "type"
        case .press: "press"
        case .navigate: "open"
        case .present: "present"
        }
    }
}

extension ScoutDecision {
    /// What Claude decided, in the timings log, never its target or text.
    var logName: String {
        switch self {
        case .click: "click"
        case .typeText: "type"
        case .press: "press"
        case .scroll: "scroll"
        case .openURL: "open"
        case .present: "present"
        case .finish: "finish"
        case .blocked: "blocked"
        }
    }
}

extension Duration {
    /// “1250ms”, rounded to the millisecond.
    var logMilliseconds: String {
        "\(Int((self / .milliseconds(1)).rounded()))ms"
    }
}
