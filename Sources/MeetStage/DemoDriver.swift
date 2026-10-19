import AppKit
import ApplicationServices
import Carbon
import MeetStageCore

struct DemoSource: Equatable, Sendable {
    let windowID: CGWindowID
    let bundleID: String
    let name: String
}

struct DemoAppInfo: Equatable, Sendable {
    var pid: pid_t
    var engine: AppEngine
    var isBrowser: Bool
    var appVersion: String
    var sizeClass: DemoSizeClass
    /// The window size in 100-point steps; positions are only trusted at the checked size.
    var windowBucket = ""
}

struct DemoScopeBaseline: Equatable, Sendable {
    var windowNumbers: Set<CGWindowID>

    /// Whether a window of the app counts toward the demo's scope. A strip under 48
    /// points across, like the small toolbar window ChatGPT keeps at its window's
    /// corner, a tooltip, or a full-screen title strip, holds nothing a demo could
    /// go to, so it never reads as a window the demo opened. One without bounds counts.
    static func counts(_ frame: CGRect) -> Bool {
        frame.isNull || min(frame.width, frame.height) >= 48
    }
}

/// One real input to the source app, already resolved to a live element.
enum DemoInput: Sendable {
    /// `from` is the route that worked while building, which a background click
    /// starts from: the page's own click or a real one, for controls that ignore
    /// Accessibility's press while their window is in the background.
    case click(ElementHandle, name: String, from: DemoStepRoute = .accessibility)
    case type(ElementHandle, name: String, text: String, submit: Bool)
    /// `from: .realKey` goes straight to the real key.
    case press(DemoKey, from: DemoStepRoute = .accessibility)
    case navigate(URL)
    case scrollToVisible(ElementHandle)
    /// Scroll-wheel steps over a region: a page's script, or a native scroll bar's
    /// value through Accessibility, before real scrolling. `from: .realWheel` goes
    /// straight to real scrolling.
    case wheel(around: NormRect?, down: Bool, increments: Int, from: DemoStepRoute = .accessibility)
    /// Scrolls the content over a region by an exact distance in points; positive
    /// moves it up. Real scrolling needs the app in front, so framing uses it last.
    case scrollBy(around: NormRect?, points: Double)
}

/// A BetterMeets window that floats over the source app, like the teleprompter,
/// and must not catch the real clicks and scrolls a demo posts.
@MainActor
protocol DemoInputObstruction: AnyObject {
    /// Gets out of the way of a real click or scroll at `point` (global CG coordinates). Returns a
    /// restore to call once the input is delivered, or nil when nothing was in the way.
    func stepAside(at point: CGPoint) async -> (@MainActor () -> Void)?
}

/// Several floating windows, like the teleprompter and the demo notice, each
/// stepping aside for the same input.
@MainActor
final class DemoInputObstructions: DemoInputObstruction {
    private let obstructions: [any DemoInputObstruction]

    init(_ obstructions: [any DemoInputObstruction]) {
        self.obstructions = obstructions
    }

    func stepAside(at point: CGPoint) async -> (@MainActor () -> Void)? {
        var restores: [@MainActor () -> Void] = []
        for obstruction in obstructions {
            if let restore = await obstruction.stepAside(at: point) { restores.append(restore) }
        }
        guard !restores.isEmpty else { return nil }
        return { for restore in restores { restore() } }
    }
}

/// The seam between demo logic and the real app. Tests drive the scout and
/// replay engine through a fake app that implements this.
@MainActor
protocol DemoDriving: AnyObject {
    var selectedSource: DemoSource? { get }
    var source: DemoSource? { get }
    /// Steps aside for real pointer input, so it lands on the app and not on a floating window.
    var inputObstruction: (any DemoInputObstruction)? { get set }
    /// The presenter paused the stage, so nothing is live.
    var isStagePaused: Bool { get }
    func appInfo(for source: DemoSource) throws -> DemoAppInfo
    func snapshot(_ source: DemoSource, waitForContent: Bool) async throws -> AXSnapshot
    /// The source window's global frame (top-left origin) now, as snapshots measure
    /// it; nil when it's gone.
    func windowFrame(_ source: DemoSource) -> CGRect?
    /// The IDs elements of an earlier snapshot have in `snapshot`, matched by
    /// identity rather than description, so scrolling never loses them. Nil for an
    /// element that's gone or whose snapshot is too old.
    func follow(_ handles: [ElementHandle], into snapshot: AXSnapshot) async -> [Int?]
    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture
    /// Performs `input` and returns the route that carried it (for typing, the
    /// text's), or nil when there was nothing to do, as for a list already
    /// scrolled to the end it would scroll toward. `commit` runs, and may veto by
    /// throwing, immediately before the input becomes irreversible, so a cancelled
    /// run never repeats it. While building and testing, `uncommit` hands that back
    /// when the route that committed delivered nothing after all (the app refused
    /// Accessibility's press, or ignored its stand-in or the page's script) and
    /// another route is about to try, so a run paused while that one waits for the
    /// person never counts the input as sent. `DemoError.inputNotDelivered` means
    /// nothing reached the app.
    @discardableResult
    func perform(
        _ input: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void,
        uncommit: @escaping @MainActor () -> Void
    ) async throws -> DemoInputRoute?
    /// What the last `perform` is known to have done, beyond its route: read right after it returns.
    var lastDelivery: DemoDelivery { get }
    func scopeBaseline(_ source: DemoSource) -> DemoScopeBaseline
    func scopeViolation(_ source: DemoSource, since baseline: DemoScopeBaseline) -> String?
    /// Closes windows the app opened since `baseline`; true once none remain.
    func closeWindows(_ source: DemoSource, openedSince baseline: DemoScopeBaseline) async -> Bool
    func show(_ cue: DemoCue?)
    /// Fades out the last highlight and the virtual cursor once a run has ended.
    func fadeOutCue()
    /// Puts the demo's window in front, so the presenter presents from the app itself.
    func bringToFront(_ source: DemoSource) async
    /// Moves the stage's demo cursor; nil hides it.
    func movePointer(to point: NormalizedWindowPoint?, duration: Double)
    /// A run starts driving `source`, or changes how; nil ends it. Building and
    /// testing drive it in the background, presenting in front.
    func setDriveMode(_ mode: DemoDriveMode?, for source: DemoSource?)
    /// The source window is borrowed for a step right now, or was a moment ago,
    /// so the person's input then went to it by accident.
    var isBorrowingScreen: Bool { get }
    /// True while a background step waits for the person to pause, false once it goes on.
    var onWaitingForPause: (@MainActor (Bool) -> Void)? { get set }
    /// How long background steps have waited for the person to pause, in all, so
    /// a run can tell how much of a step went to waiting.
    var waitedForPause: Duration { get }
    /// A web step had to borrow the screen, and this setting would have kept it in the background.
    var onBrowserTip: (@MainActor (DemoBrowserTip) -> Void)? { get set }
}

extension DemoDriving {
    /// Performs `input` for a caller with nothing to hand back if a route delivers nothing.
    @discardableResult
    func perform(
        _ input: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws -> DemoInputRoute? {
        try await perform(input, on: source, pace: pace, commit: commit, uncommit: {})
    }
}

/// Drives the source app in the background through Accessibility, so the
/// presenter stays in BetterMeets and watches on the stage. Clicks use the
/// element's own press action, typing sets the field's value, and scrolling
/// asks the element to scroll itself into view. While building and testing,
/// browsers open addresses and run web steps through their own scripting,
/// keys and scrolling in an app's own views use Accessibility's stand-ins, and
/// input only the frontmost app gets waits for the person to pause, borrows the
/// window for a moment, and puts their app and pointer back. Presenting brings
/// the app forward for that input instead.
@MainActor
final class DemoDriver: DemoDriving {
    private weak var manager: CaptureManager?
    private let input = DemoInputSynthesizer()
    private let ax = AccessibilityService.shared
    private let browsers = BrowserScripting.shared
    private var engines: [URL: AppEngine] = [:]
    weak var inputObstruction: (any DemoInputObstruction)?
    var onWaitingForPause: (@MainActor (Bool) -> Void)?
    var onBrowserTip: (@MainActor (DemoBrowserTip) -> Void)?

    /// The run in progress.
    private var drive: (source: DemoSource, mode: DemoDriveMode)?
    private var browserRun = BrowserRun()
    private var isBorrowing = false
    private var borrowEnded: ContinuousClock.Instant?
    private(set) var lastDelivery = DemoDelivery.sent

    private lazy var lease: DemoScreenLease = {
        let lease = DemoScreenLease()
        lease.onWaitingChanged = { [weak self] waiting in
            self?.overlay.setWaiting(waiting)
            self?.onWaitingForPause?(waiting)
        }
        lease.onBorrowingChanged = { [weak self] borrowing in self?.borrowingChanged(borrowing) }
        return lease
    }()

    /// The badge and cursor on the window while building and testing.
    private lazy var overlay: DemoWindowOverlay = {
        let overlay = DemoWindowOverlay()
        overlay.onBadgeClick = { BetterMeetsWindowActions.showStage() }
        return overlay
    }()

    init(manager: CaptureManager) { self.manager = manager }

    var isStagePaused: Bool { manager?.state == .paused }

    var selectedSource: DemoSource? {
        guard let manager,
            let source = manager.windows.first(where: { $0.id == manager.pendingWindowID }) ?? manager.selectedSource
        else { return nil }
        return DemoSource(windowID: source.id, bundleID: source.bundleIdentifier, name: source.applicationName)
    }

    var source: DemoSource? {
        guard let manager, manager.state == .capturing, let source = manager.activeCaptureSource else { return nil }
        return DemoSource(windowID: source.id, bundleID: source.bundleIdentifier, name: source.applicationName)
    }

    func appInfo(for source: DemoSource) throws -> DemoAppInfo {
        let window = try window(for: source)
        let application = NSRunningApplication(processIdentifier: window.processIdentifier)
        let bundleURL = application?.bundleURL
        let engine: AppEngine
        if let bundleURL, let cached = engines[bundleURL] {
            engine = cached
        } else {
            engine = AppEngine.detect(bundleURL: bundleURL)
            if let bundleURL { engines[bundleURL] = engine }
        }
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        let schemes =
            (bundle?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        let version = [
            bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ].compactMap { $0 }.joined(separator: " ")
        let frame = WindowFrameResolver.currentFrame(for: window.id, fallback: window.window.frame)
        return DemoAppInfo(
            pid: window.processIdentifier, engine: engine,
            isBrowser: engine.rendersWebContent && engine != .electron && schemes.contains("https"),
            appVersion: version, sizeClass: DemoSizeClass(windowWidth: frame.width),
            windowBucket: "\(Int((frame.width / 100).rounded()))x\(Int((frame.height / 100).rounded()))")
    }

    func snapshot(_ source: DemoSource, waitForContent: Bool) async throws -> AXSnapshot {
        let window = try window(for: source)
        guard let frame = WindowFrameResolver.currentSnapshot(for: window.id)?.frame else {
            throw DemoError.missingSource
        }
        let info = try appInfo(for: source)
        let snapshot =
            waitForContent
            ? try await ax.readySnapshot(pid: info.pid, windowFrame: frame, engine: info.engine)
            : try await ax.snapshot(pid: info.pid, windowFrame: frame, engine: info.engine)
        try Task.checkCancellation()
        _ = try self.window(for: source)
        return snapshot
    }

    func windowFrame(_ source: DemoSource) -> CGRect? {
        guard let window = try? window(for: source) else { return nil }
        return WindowFrameResolver.currentSnapshot(for: window.id)?.frame
    }

    func follow(_ handles: [ElementHandle], into snapshot: AXSnapshot) async -> [Int?] {
        await ax.follow(handles, into: snapshot.generation)
    }

    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture {
        let window = try window(for: source)
        guard let capture = await DemoWindowScreenshot.capture(source: window) else { throw DemoError.screenshot }
        try Task.checkCancellation()
        _ = try self.window(for: source)
        return capture
    }

    @discardableResult
    func perform(
        _ action: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void,
        uncommit: @escaping @MainActor () -> Void
    ) async throws -> DemoInputRoute? {
        lastDelivery = .sent
        let window = try window(for: source)
        let step = Step(window: window, source: source, background: drivesInBackground(pace))
        // Presenting never waits between routes, so it has nothing to hand back.
        let routeCommit = RouteCommit(commit, uncommit: uncommit, handsBack: step.background)
        switch action {
        case .click(let handle, let name, let recorded):
            return try await click(handle, name: name, from: recorded, step, pace: pace, commit: routeCommit)
        case .type(let handle, let name, let text, let submit):
            return try await type(
                text, into: handle, name: name, submit: submit, step, pace: pace, commit: routeCommit)
        case .press(let key, let recorded):
            show(DemoCue(key: key.badge))
            return try await press(key, from: recorded, step, commit: routeCommit)
        case .navigate(let url):
            return try await navigate(to: url, step, commit: commit)
        case .scrollToVisible(let handle):
            try commit()
            try await ax.scrollToVisible(handle)
            return .accessibility
        case .wheel(let around, let down, let increments, let recorded):
            let points = Double(increments) * DemoInputSynthesizer.wheelIncrement * (down ? 1 : -1)
            return try await scroll(around: around, points: points, from: recorded, step, commit: routeCommit) {
                point, turn in
                try await self.input.scroll(at: point, down: down, increments: increments) {
                    try self.checkFrontmost(source)
                    try turn.check()
                }
            }
        case .scrollBy(let around, let points):
            return try await scroll(around: around, points: points, from: .accessibility, step, commit: routeCommit) {
                point, turn in
                try await self.input.scroll(at: point, points: points) {
                    try self.checkFrontmost(source)
                    try turn.check()
                }
            }
        }
    }

    /// Scrolls the content over a region while building and testing: a page script
    /// in the page under its center, or the scroll bar of the native scroll area
    /// there through Accessibility, else real scroll-wheel input there. Nil when
    /// that scroll area is already at the edge it would scroll toward.
    private func scroll(
        around: NormRect?, points: Double, from recorded: DemoStepRoute, _ step: Step, commit: RouteCommit,
        wheel: @MainActor (CGPoint, DemoFrontTurn) async throws -> Void
    ) async throws -> DemoInputRoute? {
        let access = await browserAccess(step)
        let center = regionCenter(around, in: step)
        let area =
            if access.scriptable {
                await ax.webArea(pid: step.pid, windowFrame: step.frame, at: center)
            } else {
                WebAreaInfo?.none
            }
        let routes = DemoInputRoute.routes(
            for: .scroll, background: step.background, inWebArea: area != nil, browser: access, from: recorded)
        for route in routes {
            commit.handBack()
            switch route {
            case .browser:
                guard let area else { continue }
                let operation = BrowserPageOperation.scroll(
                    at: PagePoint(center, in: area.frame), points: points, webAreaWidth: Double(area.frame.width))
                if ran(try await runPageScript(operation, in: area, step, commit: commit.run)) { return route }
            case .accessibility:
                switch try await standIn(.scroll(points: points, at: center), step, commit: commit.run) {
                case .performed, .confirmed, .uncertain: return route
                case .atEdge: return nil
                case .unavailable: continue
                }
            case .borrowedScreen, .foreground:
                if area != nil { offerTip(access, step, needsJavaScript: true) }
                try await withAppInFront(step, borrowing: route == .borrowedScreen) { turn in
                    let point = self.regionCenter(around, in: step)
                    let restore = await self.inputObstruction?.stepAside(at: point)
                    defer { restore?() }
                    try await self.input.moveCursor(to: point, duration: .milliseconds(80)) {
                        try self.checkFrontmost(step.source)
                        try turn.check()
                    }
                    try turn.commit(commit.run)
                    try await wheel(point, turn)
                }
                return route
            case .selectedText:
                continue
            }
        }
        return nil
    }

    /// Accessibility's stand-in for a key or a scroll in the demo window's own views,
    /// committed only once there is one. Unavailable when it can't act there or the
    /// app refused, so the real key or wheel may try; once it acted, or found nothing
    /// to do, nothing tries again, so the input never lands twice. One that read its
    /// effect back, or may have acted, is noted in `lastDelivery`.
    private func standIn(
        _ input: AXStandIn, _ step: Step, commit: @escaping @MainActor () throws -> Void
    ) async throws -> AXStandInResult {
        guard try await ax.canStandIn(for: input, pid: step.pid, windowFrame: step.frame) else { return .unavailable }
        try commit()
        let result = try await ax.standIn(for: input, pid: step.pid, windowFrame: step.frame)
        switch result {
        case .confirmed: lastDelivery = .confirmed
        case .uncertain: lastDelivery = .uncertain
        case .performed, .atEdge, .unavailable: break
        }
        return result
    }

    /// Whether a page script ran, so no other route tries: it did what it was asked,
    /// or touched the page before failing, which `lastDelivery` notes as uncertain.
    private func ran(_ result: BrowserPageResult?) -> Bool {
        guard let result, result.touchedPage else { return false }
        if !result.ok { lastDelivery = .uncertain }
        return true
    }

    /// A region's center in global coordinates, or a point just below the window's middle.
    private func regionCenter(_ region: NormRect?, in step: Step) -> CGPoint {
        let frame = step.frame
        let center = region?.clampedToWindow.center ?? NormalizedWindowPoint(x: 0.5, y: 0.55)
        return CGPoint(x: frame.minX + center.x * frame.width, y: frame.minY + center.y * frame.height)
    }

    func scopeBaseline(_ source: DemoSource) -> DemoScopeBaseline {
        guard let window = try? window(for: source) else { return DemoScopeBaseline(windowNumbers: []) }
        return DemoScopeBaseline(windowNumbers: windowNumbers(of: window.processIdentifier))
    }

    func scopeViolation(_ source: DemoSource, since baseline: DemoScopeBaseline) -> String? {
        guard let window = try? window(for: source) else { return "The demo window closed." }
        if !windowNumbers(of: window.processIdentifier).subtracting(baseline.windowNumbers).isEmpty {
            return "\(source.name) opened a new window."
        }
        return nil
    }

    func closeWindows(_ source: DemoSource, openedSince baseline: DemoScopeBaseline) async -> Bool {
        guard let window = try? window(for: source) else { return false }
        let pid = window.processIdentifier
        let opened = windowFrames(of: pid).filter { !baseline.windowNumbers.contains($0.key) }
        guard !opened.isEmpty, await ax.closeWindows(pid: pid, frames: Array(opened.values)) else { return false }
        for _ in 0..<10 {
            if windowNumbers(of: pid).isSubset(of: baseline.windowNumbers) { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    func fadeOutCue() {
        manager?.fadeOutDemoCue()
    }

    func show(_ cue: DemoCue?) {
        guard manager?.demoCue != cue else { return }
        manager?.demoCue = cue
    }

    func movePointer(to point: NormalizedWindowPoint?, duration: Double) {
        manager?.demoPointer = point.map { DemoPointer(location: $0, travel: duration) }
        if drive?.mode.isBackground == true { overlay.movePointer(to: point, travel: duration) }
    }

    // MARK: Runs

    func setDriveMode(_ mode: DemoDriveMode?, for source: DemoSource?) {
        guard let mode, let source, let window = try? window(for: source) else {
            drive = nil
            overlay.detach()
            return
        }
        let starts = drive?.source != source || drive?.mode.isBackground != mode.isBackground
        drive = (source, mode)
        guard case .background(let activity) = mode else {
            overlay.detach()
            return
        }
        overlay.activity = activity
        overlay.attach(windowID: window.id, pid: window.processIdentifier)
        if starts { startBrowserRun(window, source: source) }
    }

    var waitedForPause: Duration { lease.waited }

    var isBorrowingScreen: Bool {
        // Input monitors deliver a moment late, so input just after a borrowed moment still counts.
        isBorrowing || borrowEnded.map { ContinuousClock.now - $0 < .milliseconds(300) } == true
    }

    private func drivesInBackground(_ pace: DemoPace) -> Bool {
        pace != .present && drive?.mode.isBackground == true
    }

    private func borrowingChanged(_ borrowing: Bool) {
        isBorrowing = borrowing
        if !borrowing { borrowEnded = .now }
        overlay.setSuspended(borrowing)
    }

    // MARK: Click

    private func click(
        _ handle: ElementHandle, name: String, from recorded: DemoStepRoute, _ step: Step, pace: DemoPace,
        commit: RouteCommit
    ) async throws -> DemoInputRoute {
        let point = try await aimPoint(for: handle, window: step.window, name: name)
        let hit = try await ax.hitTest(pid: step.pid, point: point, target: handle)
        if !hit.isTarget, AXRoleClass(role: hit.role, subrole: hit.subrole).isInteractive {
            // Another control of the app (a menu, toast or dialog) sits on top.
            throw DemoError.occluded(name)
        }
        try Self.denyDestructive(hit)
        try await glide(to: point, window: step.window, pace: pace)

        try Task.checkCancellation()
        // A step that needs a real click goes straight to it, so it skips asking the browser.
        let access = if recorded.allows(.browser) { await browserAccess(step) } else { DemoBrowserAccess.none }
        let area = if access.scriptable { try await ax.webArea(containing: handle) } else { WebAreaInfo?.none }
        let routes = DemoInputRoute.routes(
            for: .click, background: step.background, inWebArea: area != nil, browser: access, from: recorded)
        for route in routes {
            commit.handBack()
            switch route {
            case .accessibility:
                try commit.run()
                let pressed = try await ax.press(handle)
                guard pressed != .refused else { continue }
                if pressed == .uncertain { lastDelivery = .uncertain }
                ripple(at: point, window: step.window)
                return route
            case .browser:
                guard let area,
                    let clicked = try await pageClick(handle, name: name, in: area, step, commit: commit.run)
                else { continue }
                ripple(at: clicked, window: step.window)
                return route
            case .borrowedScreen, .foreground:
                if area != nil { offerTip(access, step, needsJavaScript: true) }
                try await pointerClick(
                    handle, name: name, step, borrowing: route == .borrowedScreen, commit: commit.run)
                return route
            case .selectedText:
                continue
            }
        }
        throw DemoError.inputNotDelivered(name)
    }

    /// Clicks through the page's script at the target's point as it is now, and only
    /// while the target itself is there. It reads the control at the point first, so
    /// the policy judges what the page has there, then clicks only while that control
    /// is still there. Returns the point it clicked, or nil when the click didn't run,
    /// so another route may try.
    private func pageClick(
        _ handle: ElementHandle, name: String, in area: WebAreaInfo, _ step: Step,
        commit: @escaping @MainActor () throws -> Void
    ) async throws -> CGPoint? {
        guard let aimed = try await aimAtTarget(handle, name: name, step) else { return nil }
        let at = PagePoint(aimed.point, in: area.frame)
        guard let control = try await runPageScript(.inspect(at: at), in: area, step, commit: {}), control.ok,
            try DemoInputRoute.pageClickAllowed(
                webRole: control.role, label: control.label ?? "",
                fallback: Self.policyKind(role: aimed.hit.role, subrole: aimed.hit.subrole),
                inDialog: try await ax.isInDialog(handle))
        else { return nil }
        let click = BrowserPageOperation.click(at: at, expecting: control.label ?? "")
        return ran(try await runPageScript(click, in: area, step, commit: commit)) ? aimed.point : nil
    }

    /// The target's point as it is now, while Accessibility finds the target itself
    /// there, for a page script that acts on whatever is at a point. Nil when
    /// something else is there, as when the page moved since the step aimed.
    private func aimAtTarget(_ handle: ElementHandle, name: String, _ step: Step) async throws
        -> (point: CGPoint, hit: HitTestResult)?
    {
        let point = try await aimPoint(for: handle, window: step.window, name: name)
        let hit = try await ax.hitTest(pid: step.pid, point: point, target: handle)
        return hit.isTarget ? (point, hit) : nil
    }

    /// A real mouse click with the app in front. Some controls only react to a
    /// pointer, or close at once when their window isn't focused.
    private func pointerClick(
        _ handle: ElementHandle, name: String, _ step: Step, borrowing: Bool,
        commit: @escaping @MainActor () throws -> Void
    ) async throws {
        try await withAppInFront(step, borrowing: borrowing) { turn in
            let point = try await self.aimPoint(for: handle, window: step.window, name: name)
            // The hit test is system-wide, so a floating window over the point would fail it.
            let restore = await self.inputObstruction?.stepAside(at: point)
            defer { restore?() }
            try await self.input.moveCursor(to: point, duration: .milliseconds(120)) {
                try self.checkFrontmost(step.source)
                try turn.check()
            }
            try turn.check()
            let hit = try await self.ax.systemHitTest(pid: step.pid, point: point, target: handle)
            guard hit.isTarget else { throw DemoError.inputNotDelivered(name) }
            // The wait for a pause has no end, and the control's label can change meanwhile.
            try Self.denyDestructive(hit)
            try self.checkFrontmost(step.source)
            try await self.input.click(at: point) { try turn.commit(commit) }
            self.ripple(at: point, window: step.window)
        }
    }

    private static func denyDestructive(_ hit: HitTestResult) throws {
        guard let kind = policyKind(role: hit.role, subrole: hit.subrole), !hit.label.isEmpty else { return }
        let element = DemoPolicyElement(kind: kind, label: hit.label, labelIsData: kind == .row || kind == .cell)
        if case .deny(let reason) = DemoActionPolicy.evaluate(
            .click(element), prompt: "", startHost: nil, approved: false)
        {
            throw DemoError.policyDenied(reason)
        }
    }

    // MARK: Type

    private func type(
        _ text: String, into handle: ElementHandle, name: String, submit: Bool, _ step: Step, pace: DemoPace,
        commit: RouteCommit
    ) async throws -> DemoInputRoute {
        guard !DemoActionPolicy.containsControlCharacters(text) else { throw DemoError.typingFailed(name) }
        let (window, source, pid) = (step.window, step.source, step.pid)
        let access = await browserAccess(step)
        // A field in a page, in any app, never takes Accessibility's confirm in place of Return.
        let area = if step.background { try await ax.webArea(containing: handle) } else { WebAreaInfo?.none }
        var carried = DemoInputRoute.accessibility
        if try await ax.stringValue(of: handle) != text {
            let point = try await aimPoint(for: handle, window: window, name: name)
            try await glide(to: point, window: window, pace: pace)
            ripple(at: point, window: window)
            _ = try await ax.focus(handle)
            var delivered = false
            if pace == .present {
                // Fill the field a character at a time so it reads as typing on the stage.
                var typed = ""
                delivered = true
                for (index, character) in text.enumerated() {
                    try Task.checkCancellation()
                    typed.append(character)
                    guard try await ax.setValue(typed, of: handle) else {
                        delivered = false
                        break
                    }
                    try await Task.sleep(for: pace.typingDelay(index: index))
                }
            } else {
                delivered = try await ax.setValue(text, of: handle)
            }
            if delivered { delivered = matches(try await settledValue(of: handle), text) }
            // Some fields ignore Accessibility values: a page's field takes the text from
            // the page's script, a field may take it as its selected text, and any
            // other gets real keys with the app in front.
            let routes = DemoInputRoute.routes(
                for: .type, background: step.background, inWebArea: area != nil, browser: access)
            for route in routes where !delivered {
                carried = route
                switch route {
                case .accessibility:
                    continue
                case .browser:
                    // The field may have moved while its value settled; type only into the field itself.
                    guard let area, let aimed = try await aimAtTarget(handle, name: name, step),
                        let result = try await runPageScript(
                            .insertText(text, at: PagePoint(aimed.point, in: area.frame)), in: area, step, commit: {})
                    else { continue }
                    if result.reason == .sensitiveField { throw DemoError.policyDenied(Self.sensitiveFieldReason) }
                    if result.ok { delivered = matches(try await settledValue(of: handle), text) }
                case .selectedText:
                    // Never a secure field, which the service refuses like real typing does.
                    guard try await ax.replaceText(with: text, in: handle) else { continue }
                    delivered = matches(try await settledValue(of: handle), text)
                case .borrowedScreen, .foreground:
                    if area != nil { offerTip(access, step, needsJavaScript: true) }
                    try await withAppInFront(step, borrowing: route == .borrowedScreen) { turn in
                        _ = try await self.ax.focus(handle)
                        try await Task.sleep(for: .milliseconds(80))
                        guard let focused = try await self.ax.focusedElement(pid: pid, target: handle),
                            focused.matchesTarget, !focused.isSecure
                        else { throw DemoError.typingFailed(name) }
                        try turn.check()
                        if try await !self.ax.selectAllText(in: handle) {
                            guard let code = KeyLayout.keyCode(for: "a") else { throw DemoError.typingFailed(name) }
                            self.input.press(keyCode: code, flags: .maskCommand, to: pid)
                            try await Task.sleep(for: .milliseconds(60))
                        }
                        try await self.input.type(text, to: pid, pace: pace) {
                            try self.checkFrontmost(source)
                            try turn.check()
                            guard try await self.ax.focusedElement(pid: pid, target: handle)?.matchesTarget == true
                            else { throw DemoError.focusChanged }
                        }
                    }
                    delivered = true
                }
            }
            guard matches(try await settledValue(of: handle), text) else { throw DemoError.typingFailed(name) }
        }
        try Task.checkCancellation()
        try commit.run()
        guard submit else { return carried }
        show(DemoCue(key: "⏎"))
        try await submitField(handle, name: name, text: text, area: area, access: access, step, commit: commit)
        return carried
    }

    private static let sensitiveFieldReason = "BetterMeets never types into password, code, or payment fields."

    /// Return in the field the step just typed into, and only there: Accessibility's
    /// confirm for a native field, the page's own submission for a page's field,
    /// or a real Return with the app in front. The step isn't done until Return is,
    /// so a route that reached nothing hands back the typing's commit too.
    private func submitField(
        _ handle: ElementHandle, name: String, text: String, area: WebAreaInfo?, access: DemoBrowserAccess,
        _ step: Step, commit: RouteCommit
    ) async throws {
        let pid = step.pid
        let routes = DemoInputRoute.routes(
            for: .submit, background: step.background, inWebArea: area != nil, browser: access)
        for (offset, route) in routes.enumerated() {
            if offset > 0 { commit.handBack() }
            switch route {
            case .accessibility:
                guard try await ax.canConfirm(handle) else { continue }
                try commit.run()
                switch try await ax.confirm(handle) {
                case .performed: return
                case .uncertain:
                    lastDelivery = .uncertain
                    return
                case .refused: continue
                }
            case .browser:
                guard let area else { continue }
                let point = try await aimPoint(for: handle, window: step.window, name: name)
                let operation = BrowserPageOperation.submit(at: PagePoint(point, in: area.frame), expectedValue: text)
                guard let result = try await runPageScript(operation, in: area, step, commit: commit.run) else {
                    continue
                }
                if result.reason == .sensitiveField { throw DemoError.policyDenied(Self.sensitiveFieldReason) }
                if ran(result) { return }
            case .borrowedScreen, .foreground:
                if area != nil { offerTip(access, step, needsJavaScript: true) }
                try await withAppInFront(step, borrowing: route == .borrowedScreen) { turn in
                    _ = try await self.ax.focus(handle)
                    try await Task.sleep(for: .milliseconds(60))
                    guard let focused = try await self.ax.focusedElement(pid: pid, target: handle),
                        focused.matchesTarget, !focused.isSecure
                    else { throw DemoError.inputNotDelivered(name) }
                    try self.checkFrontmost(step.source)
                    try turn.commit(commit.run)
                    self.input.pressReturn(to: pid)
                }
                return
            case .selectedText:
                continue
            }
        }
    }

    /// Reads a field until its value stops changing, since apps update it asynchronously.
    private func settledValue(of handle: ElementHandle) async throws -> String {
        var last = try await ax.stringValue(of: handle) ?? ""
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(120))
            let next = try await ax.stringValue(of: handle) ?? ""
            if next == last { return next }
            last = next
        }
        return last
    }

    /// Accepts the exact text or a completion the field appended to it.
    private func matches(_ value: String, _ text: String) -> Bool {
        value == text || (value.hasPrefix(text) && value.count <= text.count + 60 && !text.isEmpty)
    }

    // MARK: Keys

    /// A key on the focused element while building and testing: the page's script
    /// when a page in the demo window has focus and the script does what the key
    /// does, Accessibility's stand-in when the demo window's own views have focus
    /// (Escape's cancel, a list's next row, a scroll area's page), else a real key
    /// with the app in front. Nil when the stand-in found nothing to do, as for Down
    /// on a list's last row.
    private func press(
        _ key: DemoKey, from recorded: DemoStepRoute, _ step: Step, commit: RouteCommit
    ) async throws -> DemoInputRoute? {
        let access = await browserAccess(step)
        let area =
            if access.scriptable && key.pageScriptActsLikeTheKey {
                await ax.focusedWebArea(pid: step.pid, windowFrame: step.frame)
            } else {
                WebAreaInfo?.none
            }
        let routes = DemoInputRoute.routes(
            for: .key(key), background: step.background, inWebArea: area != nil, browser: access, from: recorded)
        for route in routes {
            commit.handBack()
            switch route {
            case .browser:
                guard let area else { continue }
                if ran(try await runPageScript(.key(key), in: area, step, commit: commit.run)) { return route }
            case .accessibility:
                switch try await standIn(.key(key), step, commit: commit.run) {
                case .performed, .confirmed, .uncertain: return route
                case .atEdge: return nil
                case .unavailable: continue
                }
            case .borrowedScreen, .foreground:
                if area != nil { offerTip(access, step, needsJavaScript: true) }
                try await withAppInFront(step, borrowing: route == .borrowedScreen) { turn in
                    try turn.commit(commit.run)
                    self.input.press(key, to: step.pid)
                }
                return route
            case .selectedText:
                continue
            }
        }
        return nil
    }

    // MARK: Navigate

    /// Opens `url` in the demo's tab: by setting the tab's address through the
    /// browser's scripting while building and testing, else through ⌘L.
    private func navigate(to url: URL, _ step: Step, commit: @escaping @MainActor () throws -> Void) async throws
        -> DemoInputRoute
    {
        let access = await browserAccess(step)
        for route in DemoInputRoute.routes(for: .navigate, background: step.background, browser: access) {
            switch route {
            case .browser:
                if try await openInTab(url, step, commit: commit) { return route }
            case .borrowedScreen, .foreground:
                if access.scriptable { offerTip(access, step, needsJavaScript: false) }
                try await typeAddress(url, step, borrowing: route == .borrowedScreen, commit: commit)
                return route
            case .accessibility, .selectedText:
                continue
            }
        }
        throw DemoError.addressBarUnavailable
    }

    /// Sets the address of the demo window's tab. False when nothing was set, so
    /// ⌘L can try; true once it was, even if the page is slow, since a step that
    /// may have happened never runs twice.
    private func openInTab(_ url: URL, _ step: Step, commit: @escaping @MainActor () throws -> Void) async throws
        -> Bool
    {
        // The page the stage shows, so the address goes to the tab the stage shows.
        let page = await ax.webArea(pid: step.pid, windowFrame: step.frame, at: regionCenter(nil, in: step))
        guard let target = BrowserScriptTarget(source: step.window, pageURL: page?.url) else { return false }
        var committed = false
        do {
            try await browsers.navigate(target, to: url) {
                try commit()
                committed = true
            }
            return true
        } catch let error as BrowserScriptingError {
            note(error, javaScript: false)
            return committed
        }
    }

    /// ⌘L, the address, and Return in the same tab, with the app in front.
    private func typeAddress(
        _ url: URL, _ step: Step, borrowing: Bool, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        let (pid, source) = (step.pid, step.source)
        try await withAppInFront(step, borrowing: borrowing) { turn in
            guard let code = KeyLayout.keyCode(for: "l") else { throw DemoError.addressBarUnavailable }
            self.input.press(keyCode: code, flags: .maskCommand, to: pid)
            var reached = false
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100))
                try turn.check()
                if let focused = try await self.ax.focusedElement(pid: pid, target: nil), Self.isAddressBar(focused) {
                    reached = true
                    break
                }
            }
            guard reached else {
                self.input.press(.escape, to: pid)
                throw DemoError.addressBarUnavailable
            }
            try await self.input.type(url.absoluteString, to: pid, pace: .scout) {
                try self.checkFrontmost(source)
                try turn.check()
                guard let focused = try await self.ax.focusedElement(pid: pid, target: nil), Self.isAddressBar(focused)
                else { throw DemoError.addressBarUnavailable }
            }
            try await Task.sleep(for: .milliseconds(150))
            guard let focused = try await self.ax.focusedElement(pid: pid, target: nil), Self.isAddressBar(focused),
                let value = focused.value, value.contains(url.host ?? "\u{0}")
            else {
                self.input.press(.escape, to: pid)
                throw DemoError.addressBarUnavailable
            }
            try self.checkFrontmost(source)
            try turn.commit(commit)
            self.input.pressReturn(to: pid)
        }
    }

    private static func isAddressBar(_ focused: FocusedElementInfo) -> Bool {
        ["AXTextField", "AXComboBox", "AXTextArea", "AXSearchField"].contains(focused.role) && !focused.isInWebArea
            && !focused.isSecure
    }

    // MARK: Browser scripting

    /// What the source browser's scripting allows for this step. Only building and
    /// testing script browsers, and only ones whose scripting can reach a tab.
    private func browserAccess(_ step: Step) async -> DemoBrowserAccess {
        guard step.background, let setup = browserRun.setup, let automation = await setup.value, !browserRun.isBlocked
        else { return .none }
        return DemoBrowserAccess(
            scriptable: true, automation: browserRun.automation ?? automation, javaScript: browserRun.javaScript)
    }

    /// A background run starts: page scripts are probed again, and BetterMeets asks
    /// for Automation now, while the person just chose Build or Test in BetterMeets,
    /// rather than in the middle of the run.
    private func startBrowserRun(_ window: WindowSource, source: DemoSource) {
        browsers.reset()
        browserRun = BrowserRun()
        guard (try? appInfo(for: source))?.isBrowser == true,
            let bundleURL = NSRunningApplication(processIdentifier: window.processIdentifier)?.bundleURL
        else { return }
        let pid = window.processIdentifier
        let asks = NSApp.isActive
        browserRun.setup = Task { [browsers] in
            guard await browsers.definition(forBundleAt: bundleURL) != nil else { return nil }
            let permission = await browsers.automationPermission(pid: pid, askIfNeeded: false)
            guard permission == .notDetermined, asks else { return permission }
            return await browsers.automationPermission(pid: pid, askIfNeeded: true)
        }
    }

    /// Runs a page script in the demo window's tab. Nil when it couldn't run there,
    /// so another route may try; otherwise the page's answer. A failure after the
    /// commit reads as touching the page, since the step may have run and must
    /// never run twice.
    private func runPageScript(
        _ operation: BrowserPageOperation, in area: WebAreaInfo, _ step: Step,
        commit: @escaping @MainActor () throws -> Void
    ) async throws -> BrowserPageResult? {
        guard let target = BrowserScriptTarget(source: step.window, pageURL: area.url) else { return nil }
        var committed = false
        do {
            let result = try await browsers.perform(operation, in: target) {
                try commit()
                committed = true
            }
            browserRun.javaScript = .on
            return result
        } catch let error as BrowserScriptingError {
            note(error, javaScript: true)
            // The page's own check found another page, so nothing ran.
            guard committed, error != .tabMismatch else { return nil }
            var uncertain = BrowserPageResult(ok: false)
            uncertain.acted = true
            return uncertain
        }
    }

    /// Learns from a scripting failure what this run's browser allows.
    private func note(_ error: BrowserScriptingError, javaScript: Bool) {
        switch error {
        case .javaScriptOff: browserRun.javaScript = .off
        case .notPermitted: browserRun.automation = .denied
        default: if error.blocksScripting { browserRun.isBlocked = true }
        }
        let route = javaScript ? "page script" : "tab address"
        // A browser's own message can quote the page, so only the kind of failure is logged.
        let kind = if case .failed = error { "failed" } else { String(describing: error) }
        AppLog.demoMode.info("Browser \(route, privacy: .public) didn't run: \(kind, privacy: .public)")
    }

    /// Tells the person, once per run, which browser setting would have kept a web
    /// step from borrowing the screen, given what the step's browser access was.
    private func offerTip(_ access: DemoBrowserAccess, _ step: Step, needsJavaScript: Bool) {
        guard let kind = DemoBrowserTip.Kind.missing(in: access, needsJavaScript: needsJavaScript),
            browserRun.tips.insert(kind).inserted
        else { return }
        onBrowserTip?(DemoBrowserTip(kind: kind, browser: step.source.name, bundleID: step.source.bundleID))
    }

    // MARK: App in front

    /// Runs `body` with the source app in front: borrowed at the person's next
    /// pause while building and testing, or brought forward at once while
    /// presenting. `body` checks and commits through the turn it gets, and must be
    /// repeatable until it commits, since a borrowed try the person interrupts runs again.
    private func withAppInFront(
        _ step: Step, borrowing: Bool, _ body: @MainActor (DemoFrontTurn) async throws -> Void
    ) async throws {
        if borrowing {
            try await lease.borrow(DemoLeaseTarget(step.window, name: step.source.name)) { token in
                try await body(DemoFrontTurn(lease: token))
            }
        } else {
            try await inForeground(step.window, source: step.source) { try await body(DemoFrontTurn(lease: nil)) }
        }
    }

    /// Brings the source app forward for input that macOS only delivers to the
    /// frontmost app, then hands focus back to BetterMeets if it had it.
    private func inForeground(
        _ window: WindowSource, source: DemoSource, _ body: @MainActor () async throws -> Void
    ) async throws {
        let pid = window.processIdentifier
        let wasActive = NSApp.isActive
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            guard raise(window) else { throw DemoError.inputNotDelivered(source.name) }
            var arrived = false
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(50))
                if SourceWindowFocusValidator.isExactlyFocused(window) {
                    arrived = true
                    break
                }
            }
            guard arrived else { throw DemoError.inputNotDelivered(source.name) }
        }
        defer {
            if wasActive { NSApp.activate() }
        }
        try await body()
        try? await Task.sleep(for: .milliseconds(120))
    }

    func bringToFront(_ source: DemoSource) async {
        guard let window = try? window(for: source), !SourceWindowFocusValidator.isExactlyFocused(window) else {
            return
        }
        raise(window)
    }

    /// Activates the window's app and raises that exact window above its others.
    /// False when the app is no longer running.
    @discardableResult
    private func raise(_ window: WindowSource) -> Bool {
        WindowRaiser.raise(windowID: window.id, pid: window.processIdentifier)
    }

    // MARK: Geometry and visuals

    private func aimPoint(for handle: ElementHandle, window: WindowSource, name: String) async throws -> CGPoint {
        let windowFrame = WindowFrameResolver.currentFrame(for: window.id, fallback: window.window.frame)
        guard let frame = try await ax.frame(of: handle) else { throw DemoError.targetNotFound(name) }
        let visible = frame.intersection(windowFrame.insetBy(dx: 2, dy: 2))
        guard !visible.isNull, visible.width > 1, visible.height > 1 else { throw DemoError.occluded(name) }
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    private func normalized(_ point: CGPoint, in window: WindowSource) -> NormalizedWindowPoint {
        let frame = WindowFrameResolver.currentFrame(for: window.id, fallback: window.window.frame)
        return NormalizedWindowPoint(
            x: (point.x - frame.minX) / max(frame.width, 1), y: (point.y - frame.minY) / max(frame.height, 1))
    }

    /// Glides the stage cursor to `point` and waits for it to arrive.
    private func glide(to point: CGPoint, window: WindowSource, pace: DemoPace) async throws {
        movePointer(to: normalized(point, in: window), duration: pace.cursorTravel / .seconds(1))
        try await Task.sleep(for: pace.cursorTravel)
    }

    private func ripple(at point: CGPoint, window: WindowSource) {
        let location = normalized(point, in: window)
        manager?.showStageClick(at: location)
        guard drive?.mode.isBackground == true, let manager else { return }
        overlay.ripple(at: location, color: manager.clickHighlightColor, size: manager.clickHighlightSize)
    }

    static func policyKind(role: String, subrole: String?) -> DemoPolicyElement.Kind? {
        switch AXRoleClass(role: role, subrole: subrole) {
        case .button: .button
        case .link: .link
        case .tab: .tab
        case .radio: .radio
        case .checkbox: .checkbox
        case .menuItem: .menuItem
        case .field: .field
        case .row: .row
        case .cell: .cell
        default: nil
        }
    }

    // MARK: Source binding

    private func window(for source: DemoSource) throws -> WindowSource {
        guard self.source == source, let window = manager?.activeCaptureSource else { throw DemoError.sourceChanged }
        return window
    }

    private func checkFrontmost(_ source: DemoSource) throws {
        let window = try window(for: source)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.processIdentifier else {
            throw DemoError.focusChanged
        }
    }

    private func windowNumbers(of pid: pid_t) -> Set<CGWindowID> {
        Set(windowFrames(of: pid).keys)
    }

    /// The app's on-screen standard windows that count toward scope
    /// (`DemoScopeBaseline.counts`) and their global frames, null for one without
    /// bounds, so scope checks still count it.
    private func windowFrames(of pid: pid_t) -> [CGWindowID: CGRect] {
        let windows = WindowFrameResolver.onScreenWindows(of: pid).filter { DemoScopeBaseline.counts($0.frame) }
        return Dictionary(windows.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    }
}

/// One input's commit across the routes it tries. While building and testing, a
/// route that committed and then delivered nothing, as when the app refused
/// Accessibility's press or ignored its stand-in, hands it back before the next
/// route tries, so a run paused while that one waits for the person never counts
/// the input as sent.
@MainActor
private final class RouteCommit {
    private let commit: @MainActor () throws -> Void
    private let uncommit: @MainActor () -> Void
    private let handsBack: Bool
    private var committed = false

    init(
        _ commit: @escaping @MainActor () throws -> Void, uncommit: @escaping @MainActor () -> Void, handsBack: Bool
    ) {
        self.commit = commit
        self.uncommit = uncommit
        self.handsBack = handsBack
    }

    /// The step's commit, for a route to run immediately before its input becomes irreversible.
    var run: @MainActor () throws -> Void {
        { [self] in
            try commit()
            committed = true
        }
    }

    /// Another route is about to try, so whatever the last one committed reached nothing.
    func handBack() {
        guard committed else { return }
        committed = false
        if handsBack { uncommit() }
    }
}

/// One input's window, and how its run drives it.
private struct Step {
    let window: WindowSource
    let source: DemoSource
    /// Building or testing, while the person keeps using their Mac.
    let background: Bool

    var pid: pid_t { window.processIdentifier }

    /// The window's global frame as it is now, which finds its Accessibility window.
    @MainActor var frame: CGRect {
        WindowFrameResolver.currentFrame(for: window.id, fallback: window.window.frame)
    }
}

/// What one background run has found out about its browser's scripting.
private struct BrowserRun {
    /// Reads the browser's scripting definition and its Automation permission;
    /// nil for an app that isn't a browser, and a nil value when it can't be scripted.
    var setup: Task<AutomationPermission?, Never>?
    /// Automation turned out to be off after the run started.
    var automation: AutomationPermission?
    var javaScript = BrowserJavaScriptState.unknown
    /// The browser stopped answering, or BetterMeets may not ask it, so this run stops trying.
    var isBlocked = false
    var tips: Set<DemoBrowserTip.Kind> = []
}

/// The app in front for one try of a step. `check()` throws once the person comes
/// back, so a borrowed try stops and runs again at the next pause, and `commit`
/// runs the step's commit through the lease, after which nothing is retried.
@MainActor
private struct DemoFrontTurn {
    /// Nil while presenting, where nothing is borrowed.
    let lease: DemoLeaseToken?

    func check() throws {
        try lease?.check()
    }

    func commit(_ commit: @MainActor () throws -> Void) throws {
        if let lease { try lease.commit(commit) } else { try commit() }
    }
}

extension BrowserPageResult {
    /// The script did what it was asked, or touched the page trying, so the step never runs again.
    fileprivate var touchedPage: Bool { ok || acted }
}
