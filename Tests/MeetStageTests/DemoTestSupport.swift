import CoreGraphics
import Foundation

@testable import MeetStage

/// A small screen graph standing in for a real app.
struct FakeElement {
    var role: String
    var label: String
    var rect: NormRect
    var subrole: String?
    var placeholder: String?
    /// Help text, like an icon button's tooltip.
    var help: String?
    var container: String?
    var selected = false
    var toggle: Bool?
    var isContainer = false
    var isVisible = true
    /// Screen opened by clicking this element.
    var opens: String?
    /// Ignores Accessibility's press and the page's own click, like a popup that closes while unfocused.
    var pointerOnly = false
    /// Ignores only Accessibility's press; the page's own click works.
    var ignoresPress = false
    /// Stays put while the page scrolls, like a browser's toolbar.
    var fixed = false
    /// Page content that stays put while the page scrolls, like a sticky header or a fixed banner.
    var sticky = false
    /// The label is borrowed from help text, an image or a title element, as for an icon-only button.
    var borrowsLabel = false
    /// Sits in the screen's open dialog, like a sheet's Close button.
    var inDialog = false
}

struct FakeScreen {
    var url: String?
    var elements: [FakeElement]
    var dialogOpen = false
    /// Screen opened by typing into a field and pressing Return.
    var submitOpens: String?
    /// The page's scrollport in window fractions. Nil for a screen that doesn't
    /// scroll, whose elements' rects and visibility are taken as given.
    var viewport: NormRect?
    /// How far the page is scrolled, in window fractions; element rects are at no scroll.
    var scrollY = 0.0
    var maxScrollY = 3.0
    /// Screen a key opens, like Escape closing a dialog.
    var keyOpens: [DemoKey: String] = [:]
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
    /// Ignores `AXScrollToVisible`, like a custom scroller.
    var ignoresScrollToVisible = false
    /// How many looks after a scroll still show the page where it was, like Chromium's tree catching up.
    var scrollLag = 0
    /// Elements can't be followed across a scroll, like Chromium rebuilding a lazily rendered section.
    var forgetsElementsWhenScrolled = false
    /// The browser runs page scripts, so building and testing click, key, and scroll through them.
    var runsPageScripts = false
    /// Keys Accessibility can stand in for here, as in an app's own views.
    var accessibilityKeys: Set<DemoKey> = []
    /// Accessibility can stand in for scrolling here, through a native scroll bar.
    var accessibilityScrolls = false
    /// Accessibility's stand-ins act but the app shows nothing, so only the real key or wheel works.
    var ignoresStandIns = false
    /// What Accessibility's press and stand-ins report they delivered, like a scroll bar read back.
    var accessibilityDelivery = DemoDelivery.sent
    /// Accessibility's stand-ins deliver nothing after committing, so the input is handed
    /// back and the real key or wheel goes next, once this has run, as a borrowed one
    /// waits for a pause there. Throwing stands for the run pausing meanwhile.
    var whileHandedBack: (() throws -> Void)?
    private(set) var lastDelivery = DemoDelivery.sent
    /// How many more looks show a spinner, like a list still loading.
    var busyLooks = 0
    /// How many looks after a click still show the screen it left, like an app slow to respond.
    var opensAfterLooks = 0
    private var opening: (screen: String, looks: Int)?
    /// The window's global frame, which every look measures.
    var frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private var scrolledAfterGeneration = 0
    private var lagging: (scrollY: Double, looks: Int)?
    /// How many looks the app has given, each a new generation.
    private(set) var generation = 0
    private var screenOfGeneration: [Int: String] = [:]
    private var lastSnapshot: AXSnapshot?
    static let windowHeight = 800.0
    let demoSource = DemoSource(windowID: 42, bundleID: "com.example.app", name: "Example")

    init(screens: [String: FakeScreen], start: String) {
        self.screens = screens
        current = start
    }

    var selectedSource: DemoSource? { demoSource }
    var source: DemoSource? { demoSource }
    weak var inputObstruction: (any DemoInputObstruction)?
    var isStagePaused = false

    func appInfo(for source: DemoSource) throws -> DemoAppInfo {
        DemoAppInfo(
            pid: 4242, engine: engine, isBrowser: isBrowser, appVersion: "1.0", sizeClass: .regular,
            windowBucket: "12x8")
    }

    func snapshot(_ source: DemoSource, waitForContent: Bool) async throws -> AXSnapshot {
        await Task.yield()
        if let pending = opening {
            if pending.looks > 0 {
                opening = (pending.screen, pending.looks - 1)
            } else {
                current = pending.screen
                opening = nil
            }
        }
        guard let screen = screens[current] else { throw DemoError.missingSource }
        generation += 1
        screenOfGeneration[generation] = current
        var scrollY = screen.scrollY
        if let lag = lagging {
            scrollY = lag.scrollY
            lagging = lag.looks > 1 ? (lag.scrollY, lag.looks - 1) : nil
        }
        var nodes: [AXNode] = []
        var containerIDs: [String: Int] = [:]
        for element in screen.elements {
            let id = nodes.count
            if element.isContainer { containerIDs[element.label] = id }
            let roleClass = AXRoleClass(role: element.role, subrole: element.subrole)
            var rect = element.rect
            var visible = element.isVisible
            var viewport: NormRect?
            if let page = screen.viewport, !element.fixed {
                if !element.sticky { rect.y -= scrollY }
                if engine == .chromium || engine == .electron { rect = Self.clip(rect, to: page) }
                let slack = 1 / Self.windowHeight
                visible = visible && rect.midY >= page.y - slack && rect.midY <= page.maxY + slack
                viewport = page
            }
            nodes.append(
                AXNode(
                    id: id, role: element.role, subrole: element.subrole, roleClass: roleClass,
                    label: element.label, identifier: nil, placeholder: element.placeholder, help: element.help,
                    rect: rect, isVisible: visible, isSelected: element.selected, isFocused: false,
                    isEnabled: true, isSecure: element.subrole == "AXSecureTextField",
                    textLength: roleClass == .field ? fieldText.count : nil, toggleValue: element.toggle,
                    containerID: element.container.flatMap { containerIDs[$0] }, isContainer: element.isContainer,
                    inWebArea: true, url: nil, dialog: element.inDialog ? 0 : nil,
                    interactiveAncestorID: interactiveParents[id], viewport: viewport,
                    labelIsBorrowed: element.borrowsLabel))
        }
        let busy = busyLooks > 0
        if busy { busyLooks -= 1 }
        let snapshot = AXSnapshot(
            generation: generation, windowFrame: frame, nodes: nodes,
            webURL: screen.url.flatMap(URL.init(string:)), dialogOpen: screen.dialogOpen,
            webContent: WebContentState(hasChildren: true, loaded: true, progress: 1, busy: false),
            busyIndicators: busy ? 1 : 0)
        lastSnapshot = snapshot
        return snapshot
    }

    func windowFrame(_ source: DemoSource) -> CGRect? { frame }

    /// Elements keep their index on a screen, so they're followed by it, from looks
    /// no more than two older, like `AccessibilityService`.
    func follow(_ handles: [ElementHandle], into snapshot: AXSnapshot) async -> [Int?] {
        handles.map { handle in
            if forgetsElementsWhenScrolled, handle.generation <= scrolledAfterGeneration,
                snapshot.generation > scrolledAfterGeneration
            {
                return nil
            }
            guard let screen = screenOfGeneration[handle.generation], screen == screenOfGeneration[snapshot.generation],
                snapshot.generation - handle.generation <= 2,
                screens[screen]?.elements.indices.contains(handle.id) == true
            else { return nil }
            return handle.id
        }
    }

    /// Chromium's frames: clipped to the viewport, or a one-point strip at its
    /// nearest edge when wholly outside it.
    static func clip(_ rect: NormRect, to page: NormRect) -> NormRect {
        let top = max(rect.y, page.y)
        let bottom = min(rect.maxY, page.maxY)
        if bottom > top { return NormRect(x: rect.x, y: top, w: rect.w, h: bottom - top) }
        let strip = 1 / windowHeight
        return NormRect(x: rect.x, y: rect.y >= page.maxY ? page.maxY - strip : page.y, w: rect.w, h: strip)
    }

    /// `AXScrollToVisible` as each engine does it: Chromium and Gecko center a target
    /// that isn't wholly in view, WebKit stops a partly visible one at the nearest
    /// edge, and AppKit scrolls as little as it can.
    private func scrollIntoView(_ element: FakeElement) {
        guard !ignoresScrollToVisible, let screen = screens[current], let page = screen.viewport, !element.fixed
        else { return }
        var live = element.rect
        if !element.sticky { live.y -= screen.scrollY }
        let fully = live.y >= page.y && live.maxY <= page.maxY
        let covers = live.y <= page.y && live.maxY >= page.maxY
        guard !fully, !covers else { return }
        let hidden = live.maxY <= page.y || live.y >= page.maxY
        let nearest = live.h > page.h || live.y < page.y ? live.y - page.y : live.maxY - page.maxY
        let dy: Double =
            switch engine {
            case .chromium, .electron, .gecko: live.midY - page.midY
            case .webkit: hidden ? live.midY - page.midY : nearest
            case .native: nearest
            }
        scroll(by: dy * Self.windowHeight)
    }

    private func scroll(by points: Double) {
        guard var screen = screens[current], screen.viewport != nil else { return }
        let old = screen.scrollY
        screen.scrollY = min(max(old + points / Self.windowHeight, 0), screen.maxScrollY)
        screens[current] = screen
        scrolledAfterGeneration = generation
        if scrollLag > 0 { lagging = (old, scrollLag) }
    }

    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture {
        DemoWindowScreenshot.Capture(base64JPEG: "AA==", pixelSize: CGSize(width: 10, height: 10))
    }

    /// Follows the driver's routes: Accessibility, the page's script, or real input,
    /// in the background unless presenting, from the route a step recorded.
    func perform(
        _ input: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void,
        uncommit: @escaping @MainActor () -> Void
    ) async throws -> DemoInputRoute? {
        lastDelivery = .sent
        await Task.yield()
        if let error = failNextInput {
            failNextInput = nil
            throw error
        }
        try Task.checkCancellation()
        beforeInput?(input)
        let access = runsPageScripts ? Self.pageScripts : .none
        func routes(_ input: DemoInputRoute.Input, from recorded: DemoStepRoute) -> [DemoInputRoute] {
            DemoInputRoute.routes(
                for: input, background: pace != .present, inWebArea: isBrowser, browser: access, from: recorded)
        }
        switch input {
        case .click(let handle, _, let recorded):
            let element = try element(for: handle)
            try commit()
            guard let route = routes(.click, from: recorded).first(where: { $0 != .selectedText }) else { return nil }
            switch route {
            case .accessibility where element.pointerOnly || element.ignoresPress:
                log.append("press \(element.label) (ignored)")
                lastDelivery = accessibilityDelivery
                return route
            case .browser where element.pointerOnly:
                log.append("page click \(element.label) (ignored)")
                return route
            case .browser:
                log.append("page click \(element.label)")
            default:
                log.append("click \(element.label)")
            }
            if nextClickOpensWindow {
                nextClickOpensWindow = false
                openWindows += 1
                return route
            }
            if let toggle = element.toggle,
                let index = screens[current]?.elements.firstIndex(where: { $0.label == element.label })
            {
                screens[current]?.elements[index].toggle = !toggle
            }
            if let next = element.opens {
                if opensAfterLooks > 0 { opening = (next, opensAfterLooks) } else { current = next }
            }
            return route
        case .type(let handle, _, let text, let submit):
            _ = try element(for: handle)
            fieldText = text
            try commit()
            log.append("type \(text)\(submit ? " ⏎" : "")")
            if submit, let next = screens[current]?.submitOpens { current = next }
            return .accessibility
        case .press(let key, let recorded):
            try commit()
            let route = routes(.key(key), from: recorded).first {
                $0 != .accessibility || accessibilityKeys.contains(key)
            }
            switch route {
            case .accessibility where whileHandedBack != nil:
                log.append("press \(key.rawValue) (accessibility, unavailable)")
                try handBack(uncommit, then: commit)
                log.append("press \(key.rawValue)")
                if let next = screens[current]?.keyOpens[key] { current = next }
                return .borrowedScreen
            case .accessibility:
                log.append("press \(key.rawValue) (accessibility\(ignoresStandIns ? ", ignored" : ""))")
                lastDelivery = accessibilityDelivery
                if ignoresStandIns { return route }
            case .browser:
                log.append("press \(key.rawValue) (page)")
            default:
                log.append("press \(key.rawValue)")
            }
            if let next = screens[current]?.keyOpens[key] { current = next }
            return route
        case .navigate(let url):
            try commit()
            log.append("open \(url.absoluteString)")
            if let match = screens.first(where: { $0.value.url == url.absoluteString })?.key { current = match }
            return .browser
        case .wheel(_, let down, let increments, let recorded):
            try commit()
            let route = routes(.scroll, from: recorded).first { $0 != .accessibility || accessibilityScrolls }
            switch route {
            case .accessibility:
                log.append("scroll \(down ? "down" : "up") (accessibility\(ignoresStandIns ? ", ignored" : ""))")
                lastDelivery = accessibilityDelivery
                if ignoresStandIns { return route }
            case .browser:
                log.append("scroll \(down ? "down" : "up") (page)")
            default:
                log.append("scroll \(down ? "down" : "up")")
            }
            scroll(by: (down ? 160 : -160) * Double(increments))
            return route
        case .scrollBy(_, let points):
            try commit()
            log.append("scroll by \(Int(points.rounded()))")
            scroll(by: points)
            return .borrowedScreen
        case .scrollToVisible(let handle):
            let element = try element(for: handle)
            try commit()
            log.append("scroll into view \(element.label)")
            scrollIntoView(element)
            return .accessibility
        }
    }

    private static let pageScripts = DemoBrowserAccess(scriptable: true, automation: .granted, javaScript: .on)

    /// A stand-in that committed and delivered nothing: hands the input back, waits
    /// as a borrowed real input does, and commits again before that goes out.
    private func handBack(_ uncommit: () -> Void, then commit: () throws -> Void) throws {
        uncommit()
        try whileHandedBack?()
        try Task.checkCancellation()
        try commit()
    }

    /// Separate windows count from 1, so a baseline holds the ones open when it was taken.
    func scopeBaseline(_ source: DemoSource) -> DemoScopeBaseline {
        DemoScopeBaseline(windowNumbers: Set((0..<openWindows).map { CGWindowID($0 + 1) }))
    }
    func scopeViolation(_ source: DemoSource, since baseline: DemoScopeBaseline) -> String? {
        openWindows > baseline.windowNumbers.count ? "Example opened a new window." : nil
    }
    func closeWindows(_ source: DemoSource, openedSince baseline: DemoScopeBaseline) async -> Bool {
        log.append("close \(openWindows - baseline.windowNumbers.count) window")
        openWindows = baseline.windowNumbers.count
        return true
    }
    func show(_ cue: DemoCue?) { cues.append(cue) }
    func fadeOutCue() { cues.append(nil) }
    private(set) var broughtToFront = 0
    func bringToFront(_ source: DemoSource) async { broughtToFront += 1 }
    func movePointer(to point: NormalizedWindowPoint?, duration: Double) {}
    /// Each change of how runs drive the app, nil when one ends.
    private(set) var driveModes: [DemoDriveMode?] = []
    func setDriveMode(_ mode: DemoDriveMode?, for source: DemoSource?) {
        if driveModes.last.map({ $0 != mode }) ?? (mode != nil) { driveModes.append(mode) }
    }
    var isBorrowingScreen = false
    var waitedForPause = Duration.zero
    var onWaitingForPause: (@MainActor (Bool) -> Void)?
    var onBrowserTip: (@MainActor (DemoBrowserTip) -> Void)?

    private func element(for handle: ElementHandle) throws -> FakeElement {
        guard handle.generation == lastSnapshot?.generation, let screen = screens[current],
            screen.elements.indices.contains(handle.id)
        else { throw DemoError.targetNotFound("stale") }
        return screen.elements[handle.id]
    }

    /// The ID the next snapshot gives the element with `label` on the current screen, or -1 if there's none.
    func id(of label: String) -> Int {
        screens[current]?.elements.firstIndex { $0.label == label } ?? -1
    }
}

/// Returns queued replies in order and records what it was asked.
final class ScriptedModel: DemoModeling, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<ScoutReply, Error>]
    private var relocations: [[Int]?]
    private var relocated = 0
    private(set) var requests: [ScoutTurnRequest] = []
    private(set) var relocateRequests: [RelocateRequest] = []
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

    func relocate(_ request: RelocateRequest, key: String) async throws
        -> (ids: [Int]?, costMicroUSD: Int, tokens: DemoTokenUsage)
    {
        lock.withLock {
            relocated += 1
            relocateRequests.append(request)
            return (relocations.isEmpty ? nil : relocations.removeFirst(), 0, DemoTokenUsage())
        }
    }

    /// How many times replay asked Claude to find a target.
    var relocateCount: Int { lock.withLock { relocated } }

    var facts: [[String]] { lock.withLock { requests.map(\.facts) } }
}

func reply(
    _ decision: ScoutDecision, outline: [String] = [], expect: String = "", target: String = "",
    previous: ScoutJudgement? = nil, coverage: [ScoutBeatCoverage]? = nil
) -> Result<ScoutReply, Error> {
    .success(
        ScoutReply(
            decision: decision, outline: outline, costMicroUSD: 1_000, expect: expect, target: target,
            previous: previous, coverage: coverage))
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
    limits.effectWindow = .milliseconds(1)
    limits.framing = .instant
    return limits
}
