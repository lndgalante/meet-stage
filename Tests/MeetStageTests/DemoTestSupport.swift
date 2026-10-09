import Foundation

@testable import MeetStage

/// A small screen graph standing in for a real app.
struct FakeElement {
    var role: String
    var label: String
    var rect: NormRect
    var subrole: String?
    var placeholder: String?
    var container: String?
    var selected = false
    var toggle: Bool?
    var isContainer = false
    var isVisible = true
    /// Screen opened by clicking this element.
    var opens: String?
    /// Ignores Accessibility's press, like a popup that closes while unfocused.
    var pointerOnly = false
}

struct FakeScreen {
    var url: String?
    var elements: [FakeElement]
    var dialogOpen = false
    /// Screen opened by typing into a field and pressing Return.
    var submitOpens: String?
}

@MainActor
final class FakeApp: DemoDriving {
    var screens: [String: FakeScreen]
    var current: String
    var log: [String] = []
    var cues: [DemoCue?] = []
    var fieldText = ""
    var isBrowser = true
    var engine: AppEngine = .chromium
    var failNextInput: DemoError?
    /// The next click opens a separate window of the app.
    var nextClickOpensWindow = false
    private(set) var openWindows = 0
    /// Element index → index of its clickable ancestor on the same screen.
    var interactiveParents: [Int: Int] = [:]
    /// Runs right before an input is dispatched, after its checks.
    var beforeInput: ((DemoInput) -> Void)?
    private var generation = 0
    private var lastSnapshot: AXSnapshot?
    let demoSource = DemoSource(windowID: 42, bundleID: "com.example.app", name: "Example")

    init(screens: [String: FakeScreen], start: String) {
        self.screens = screens
        current = start
    }

    var selectedSource: DemoSource? { demoSource }
    var source: DemoSource? { demoSource }

    func appInfo(for source: DemoSource) throws -> DemoAppInfo {
        DemoAppInfo(
            pid: 4242, engine: engine, isBrowser: isBrowser, appVersion: "1.0", sizeClass: .regular,
            windowBucket: "12x8")
    }

    func snapshot(_ source: DemoSource, waitForContent: Bool) async throws -> AXSnapshot {
        await Task.yield()
        let screen = screens[current]!
        generation += 1
        var nodes: [AXNode] = []
        var containerIDs: [String: Int] = [:]
        for element in screen.elements {
            let id = nodes.count
            if element.isContainer { containerIDs[element.label] = id }
            let roleClass = AXRoleClass(role: element.role, subrole: element.subrole)
            nodes.append(
                AXNode(
                    id: id, role: element.role, subrole: element.subrole, roleClass: roleClass,
                    label: element.label, identifier: nil, placeholder: element.placeholder, help: nil,
                    rect: element.rect, isVisible: element.isVisible, isSelected: element.selected, isFocused: false,
                    isEnabled: true, isSecure: element.subrole == "AXSecureTextField",
                    textLength: roleClass == .field ? fieldText.count : nil, toggleValue: element.toggle,
                    containerID: element.container.flatMap { containerIDs[$0] }, isContainer: element.isContainer,
                    inWebArea: true, url: nil, interactiveAncestorID: interactiveParents[id]))
        }
        let snapshot = AXSnapshot(
            generation: generation, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: nodes,
            webURL: screen.url.flatMap(URL.init(string:)), dialogOpen: screen.dialogOpen,
            webContent: WebContentState(hasChildren: true, loaded: true, progress: 1, busy: false))
        lastSnapshot = snapshot
        return snapshot
    }

    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture {
        DemoWindowScreenshot.Capture(base64JPEG: "AA==", pixelSize: CGSize(width: 10, height: 10))
    }

    func perform(
        _ input: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        await Task.yield()
        if let error = failNextInput {
            failNextInput = nil
            throw error
        }
        try Task.checkCancellation()
        beforeInput?(input)
        switch input {
        case .click(let handle, _, let pointer):
            let element = try element(for: handle)
            try commit()
            if element.pointerOnly, !pointer {
                log.append("press \(element.label) (ignored)")
                return
            }
            log.append("click \(element.label)")
            if nextClickOpensWindow {
                nextClickOpensWindow = false
                openWindows += 1
                return
            }
            if let toggle = element.toggle,
                let index = screens[current]!.elements.firstIndex(where: { $0.label == element.label })
            {
                screens[current]!.elements[index].toggle = !toggle
            }
            if let next = element.opens { current = next }
        case .type(let handle, _, let text, let submit):
            _ = try element(for: handle)
            fieldText = text
            try commit()
            log.append("type \(text)\(submit ? " ⏎" : "")")
            if submit, let next = screens[current]!.submitOpens { current = next }
        case .press(let key):
            try commit()
            log.append("press \(key.rawValue)")
        case .navigate(let url):
            try commit()
            log.append("open \(url.absoluteString)")
            if let match = screens.first(where: { $0.value.url == url.absoluteString })?.key { current = match }
        case .wheel(_, let down, _):
            try commit()
            log.append("scroll \(down ? "down" : "up")")
        case .scrollToVisible:
            try commit()
            log.append("scroll into view")
        }
    }

    func scopeBaseline(_ source: DemoSource) -> DemoScopeBaseline { DemoScopeBaseline(windowNumbers: []) }
    func scopeViolation(_ source: DemoSource, since baseline: DemoScopeBaseline) -> String? {
        openWindows > 0 ? "Example opened a new window." : nil
    }
    func closeWindows(_ source: DemoSource, openedSince baseline: DemoScopeBaseline) async -> Bool {
        log.append("close \(openWindows) window")
        openWindows = 0
        return true
    }
    func show(_ cue: DemoCue?) { cues.append(cue) }
    func fadeOutCue() { cues.append(nil) }
    private(set) var broughtToFront = 0
    func bringToFront(_ source: DemoSource) async { broughtToFront += 1 }
    func movePointer(to point: NormalizedWindowPoint?, duration: Double) {}

    private func element(for handle: ElementHandle) throws -> FakeElement {
        guard handle.generation == lastSnapshot?.generation, let screen = screens[current],
            screen.elements.indices.contains(handle.id)
        else { throw DemoError.targetNotFound("stale") }
        return screen.elements[handle.id]
    }

    /// The ID the next snapshot gives the element with `label` on the current screen.
    func id(of label: String) -> Int {
        screens[current]!.elements.firstIndex { $0.label == label }!
    }
}

/// Returns queued replies in order and records what it was asked.
final class ScriptedModel: DemoModeling, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<ScoutReply, Error>]
    private var relocations: [[Int]?]
    private(set) var requests: [ScoutTurnRequest] = []
    private(set) var scriptRequests: [ScriptRequest] = []
    var scriptDelay = Duration.zero

    init(_ replies: [Result<ScoutReply, Error>], relocations: [[Int]?] = []) {
        self.replies = replies
        self.relocations = relocations
    }

    func writeScript(_ request: ScriptRequest, key: String) async throws -> ScriptDraft {
        lock.withLock { scriptRequests.append(request) }
        try await Task.sleep(for: scriptDelay)
        return ScriptDraft(
            opening: "Let's find a movie.", closing: "That's the whole flow.",
            titles: request.steps.map { "Polished \($0.title)" },
            scripts: request.steps.map { "Line for \($0.title)." }, startLabel: "the search page")
    }

    func scoutTurn(_ request: ScoutTurnRequest, key: String) async throws -> ScoutReply {
        let reply: Result<ScoutReply, Error> = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? .failure(DemoError.invalidResponse) : replies.removeFirst()
        }
        return try reply.get()
    }

    func ideas(_ request: IdeasRequest, key: String) async throws -> [DemoIdea] {
        [
            DemoIdea(label: "Movie search", prompt: "Search for a movie and open its page"),
            DemoIdea(label: "Subtitle download", prompt: "Show where to download a movie's subtitle"),
            DemoIdea(label: "Latest releases", prompt: "Open the latest releases and highlight the newest one")
        ]
    }

    func relocate(_ request: RelocateRequest, key: String) async throws -> (ids: [Int]?, costMicroUSD: Int) {
        lock.withLock { (relocations.isEmpty ? nil : relocations.removeFirst(), 0) }
    }

    var facts: [[String]] { lock.withLock { requests.map(\.facts) } }
}

func reply(_ decision: ScoutDecision, outline: [String] = []) -> Result<ScoutReply, Error> {
    .success(ScoutReply(decision: decision, outline: outline, costMicroUSD: 1_000))
}

func rect(_ x: Double, _ y: Double, _ w: Double = 0.1, _ h: Double = 0.04) -> NormRect {
    NormRect(x: x, y: y, w: w, h: h)
}

/// A movie search site in Spanish: search, results list, movie page.
@MainActor
func subtisApp() -> FakeApp {
    let home = FakeScreen(
        url: "https://subtis.io/",
        elements: [
            FakeElement(role: "AXHeading", label: "Subtis", rect: rect(0.1, 0.05)),
            FakeElement(
                role: "AXTextField", label: "Buscar película", rect: rect(0.3, 0.2, 0.4), placeholder: "Buscar película"
            ),
            FakeElement(role: "AXButton", label: "Buscar", rect: rect(0.72, 0.2))
        ],
        submitOpens: "results")
    let results = FakeScreen(
        url: "https://subtis.io/search/the-matrix",
        elements: [
            FakeElement(role: "AXHeading", label: "Resultados", rect: rect(0.1, 0.05)),
            FakeElement(role: "AXList", label: "Resultados", rect: rect(0.1, 0.15, 0.8, 0.6), isContainer: true),
            FakeElement(
                role: "AXLink", label: "The Matrix (1999)", rect: rect(0.1, 0.2, 0.6), container: "Resultados",
                opens: "movie"),
            FakeElement(
                role: "AXLink", label: "The Matrix Reloaded (2003)", rect: rect(0.1, 0.3, 0.6), container: "Resultados",
                opens: "movie")
        ])
    let movie = FakeScreen(
        url: "https://subtis.io/movie/603",
        elements: [
            FakeElement(role: "AXHeading", label: "The Matrix", rect: rect(0.1, 0.05, 0.4)),
            FakeElement(role: "AXStaticText", label: "1999 · 136 min", rect: rect(0.1, 0.12, 0.3)),
            FakeElement(role: "AXButton", label: "Descargar subtítulo", rect: rect(0.1, 0.3, 0.3))
        ])
    return FakeApp(screens: ["home": home, "results": results, "movie": movie], start: "home")
}

func fastScoutLimits() -> DemoScout.Limits {
    var limits = DemoScout.Limits()
    limits.settleMinimum = .milliseconds(1)
    limits.settlePoll = .milliseconds(1)
    return limits
}
