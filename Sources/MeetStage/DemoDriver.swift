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
}

/// One real input to the source app, already resolved to a live element.
enum DemoInput: Sendable {
    /// `pointer` uses a real mouse click with the app briefly in front, for
    /// controls that ignore Accessibility's press while in the background.
    case click(ElementHandle, name: String, pointer: Bool = false)
    case type(ElementHandle, name: String, text: String, submit: Bool)
    case press(DemoKey)
    case navigate(URL)
    case scrollToVisible(ElementHandle)
    /// Scroll-wheel steps over a region; needs the app in front, so it's a fallback.
    case wheel(around: NormRect?, down: Bool, increments: Int)
}

/// The seam between demo logic and the real app. Tests drive the scout and
/// replay engine through a fake app that implements this.
@MainActor
protocol DemoDriving: AnyObject {
    var selectedSource: DemoSource? { get }
    var source: DemoSource? { get }
    func appInfo(for source: DemoSource) throws -> DemoAppInfo
    func snapshot(_ source: DemoSource, waitForContent: Bool) async throws -> AXSnapshot
    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture
    /// Performs `input`. `commit` runs, and may veto by throwing, immediately
    /// before the input becomes irreversible, so a cancelled run never repeats it.
    /// `DemoError.inputNotDelivered` means nothing reached the app.
    func perform(
        _ input: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws
    func scopeBaseline(_ source: DemoSource) -> DemoScopeBaseline
    func scopeViolation(_ source: DemoSource, since baseline: DemoScopeBaseline) -> String?
    func show(_ cue: DemoCue?)
    /// Moves the stage's demo cursor; nil hides it.
    func movePointer(to point: NormalizedWindowPoint?, duration: Double)
}

/// Drives the source app in the background through Accessibility, so the
/// presenter stays in BetterMeets and watches on the stage. Clicks use the
/// element's own press action, typing sets the field's value, and scrolling
/// asks the element to scroll itself into view. Only keys, and controls that
/// ignore Accessibility, bring the app forward briefly.
@MainActor
final class DemoDriver: DemoDriving {
    private weak var manager: CaptureManager?
    private let input = DemoInputSynthesizer()
    private let ax = AccessibilityService.shared
    private var engines: [URL: AppEngine] = [:]

    init(manager: CaptureManager) { self.manager = manager }

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
            bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
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

    func screenshot(_ source: DemoSource) async throws -> DemoWindowScreenshot.Capture {
        let window = try window(for: source)
        guard let capture = await DemoWindowScreenshot.capture(source: window) else { throw DemoError.screenshot }
        try Task.checkCancellation()
        _ = try self.window(for: source)
        return capture
    }

    func perform(
        _ action: DemoInput, on source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        let window = try window(for: source)
        switch action {
        case .click(let handle, let name, let pointer):
            try await click(
                handle, name: name, pointer: pointer, window: window, source: source, pace: pace, commit: commit)
        case .type(let handle, let name, let text, let submit):
            try await type(
                text, into: handle, name: name, submit: submit, window: window, source: source, pace: pace,
                commit: commit)
        case .press(let key):
            show(DemoCue(key: key.badge))
            try await inForeground(window, source: source) {
                try commit()
                self.input.press(key, to: window.processIdentifier)
            }
        case .navigate(let url):
            try await navigate(to: url, window: window, source: source, commit: commit)
        case .scrollToVisible(let handle):
            try commit()
            try await ax.scrollToVisible(handle)
        case .wheel(let around, let down, let increments):
            try await inForeground(window, source: source) {
                let frame = WindowFrameResolver.currentFrame(for: window.id, fallback: window.window.frame)
                let center = around?.clampedToWindow.center ?? NormalizedWindowPoint(x: 0.5, y: 0.55)
                let point = CGPoint(x: frame.minX + center.x * frame.width, y: frame.minY + center.y * frame.height)
                try await self.input.moveCursor(to: point, duration: .milliseconds(80)) {
                    try self.checkFrontmost(source)
                }
                try commit()
                try await self.input.scroll(at: point, down: down, increments: increments) {
                    try self.checkFrontmost(source)
                }
            }
        }
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

    func show(_ cue: DemoCue?) {
        guard manager?.demoCue != cue else { return }
        manager?.demoCue = cue
    }

    func movePointer(to point: NormalizedWindowPoint?, duration: Double) {
        manager?.demoPointer = point.map { DemoPointer(location: $0, travel: duration) }
    }

    // MARK: Click

    private func click(
        _ handle: ElementHandle, name: String, pointer: Bool, window: WindowSource, source: DemoSource,
        pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        let pid = window.processIdentifier
        let point = try await aimPoint(for: handle, window: window, name: name)
        let hit = try await ax.hitTest(pid: pid, point: point, target: handle)
        if !hit.isTarget, AXRoleClass(role: hit.role, subrole: hit.subrole).isInteractive {
            // Another control of the app (a menu, toast or dialog) sits on top.
            throw DemoError.occluded(name)
        }
        try denyDestructive(hit)
        try await glide(to: point, window: window, pace: pace)

        try Task.checkCancellation()
        if pointer {
            try await pointerClick(handle, name: name, window: window, source: source, commit: commit)
            return
        }
        try commit()
        switch try await ax.press(handle) {
        case .performed, .uncertain:
            ripple(at: point, window: window)
        case .refused:
            try await pointerClick(handle, name: name, window: window, source: source, commit: commit)
        }
    }

    /// A real mouse click with the app briefly in front. Some controls only react
    /// to a pointer, or close at once when their window isn't focused.
    private func pointerClick(
        _ handle: ElementHandle, name: String, window: WindowSource, source: DemoSource,
        commit: @escaping @MainActor () throws -> Void
    ) async throws {
        let pid = window.processIdentifier
        do {
            try await inForeground(window, source: source) {
                let point = try await self.aimPoint(for: handle, window: window, name: name)
                try await self.input.moveCursor(to: point, duration: .milliseconds(120)) {
                    try self.checkFrontmost(source)
                }
                let hit = try await self.ax.systemHitTest(pid: pid, point: point, target: handle)
                guard hit.isTarget else { throw DemoError.inputNotDelivered(name) }
                try self.checkFrontmost(source)
                try await self.input.click(at: point, commit: commit)
                self.ripple(at: point, window: window)
            }
        }
    }

    private func denyDestructive(_ hit: HitTestResult) throws {
        guard let kind = Self.policyKind(role: hit.role, subrole: hit.subrole), !hit.label.isEmpty else { return }
        let element = DemoPolicyElement(kind: kind, label: hit.label, labelIsData: kind == .row || kind == .cell)
        if case .deny(let reason) = DemoActionPolicy.evaluate(.click(element), prompt: "", startHost: nil, approved: false) {
            throw DemoError.policyDenied(reason)
        }
    }

    // MARK: Type

    private func type(
        _ text: String, into handle: ElementHandle, name: String, submit: Bool, window: WindowSource,
        source: DemoSource, pace: DemoPace, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        guard !DemoActionPolicy.containsControlCharacters(text) else { throw DemoError.typingFailed(name) }
        let pid = window.processIdentifier
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
            if !delivered {
                // Some fields ignore Accessibility values; type real keys with the app in front.
                try await inForeground(window, source: source) {
                    _ = try await self.ax.focus(handle)
                    try await Task.sleep(for: .milliseconds(80))
                    guard let focused = try await self.ax.focusedElement(pid: pid, target: handle),
                        focused.matchesTarget, !focused.isSecure
                    else { throw DemoError.typingFailed(name) }
                    if try await !self.ax.selectAllText(in: handle) {
                        guard let code = KeyLayout.keyCode(for: "a") else { throw DemoError.typingFailed(name) }
                        self.input.press(keyCode: code, flags: .maskCommand, to: pid)
                        try await Task.sleep(for: .milliseconds(60))
                    }
                    try await self.input.type(text, to: pid, pace: pace) {
                        try self.checkFrontmost(source)
                        guard try await self.ax.focusedElement(pid: pid, target: handle)?.matchesTarget == true else {
                            throw DemoError.focusChanged
                        }
                    }
                }
            }
            guard matches(try await settledValue(of: handle), text) else { throw DemoError.typingFailed(name) }
        }
        try Task.checkCancellation()
        try commit()
        guard submit else { return }
        show(DemoCue(key: "⏎"))
        try await inForeground(window, source: source) {
            _ = try await self.ax.focus(handle)
            try await Task.sleep(for: .milliseconds(60))
            // Return only ever goes to the field this step typed into.
            guard let focused = try await self.ax.focusedElement(pid: pid, target: handle), focused.matchesTarget,
                !focused.isSecure
            else { throw DemoError.inputNotDelivered(name) }
            try self.checkFrontmost(source)
            try commit()
            self.input.pressReturn(to: pid)
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

    // MARK: Navigate

    private func navigate(
        to url: URL, window: WindowSource, source: DemoSource, commit: @escaping @MainActor () throws -> Void
    ) async throws {
        let pid = window.processIdentifier
        try await inForeground(window, source: source) {
            guard let code = KeyLayout.keyCode(for: "l") else { throw DemoError.addressBarUnavailable }
            self.input.press(keyCode: code, flags: .maskCommand, to: pid)
            var reached = false
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100))
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
            try commit()
            self.input.pressReturn(to: pid)
        }
    }

    private static func isAddressBar(_ focused: FocusedElementInfo) -> Bool {
        ["AXTextField", "AXComboBox", "AXTextArea", "AXSearchField"].contains(focused.role) && !focused.isInWebArea
            && !focused.isSecure
    }

    // MARK: Foreground fallback

    /// Brings the source app forward for input that macOS only delivers to the
    /// frontmost app, then hands focus back to BetterMeets if it had it.
    private func inForeground(
        _ window: WindowSource, source: DemoSource, _ body: @MainActor () async throws -> Void
    ) async throws {
        let pid = window.processIdentifier
        let wasActive = NSApp.isActive
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            guard let application = NSRunningApplication(processIdentifier: pid) else {
                throw DemoError.inputNotDelivered(source.name)
            }
            if wasActive { NSApp.yieldActivation(to: application) }
            application.activate()
            let app = AXUIElementCreateApplication(pid)
            if let frame = WindowFrameResolver.currentSnapshot(for: window.id)?.frame,
                let axWindow = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: frame)
            {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            }
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
        let seconds = Double(pace.cursorTravel.components.attoseconds) / 1e18 + Double(pace.cursorTravel.components.seconds)
        movePointer(to: normalized(point, in: window), duration: seconds)
        try await Task.sleep(for: pace.cursorTravel)
    }

    private func ripple(at point: CGPoint, window: WindowSource) {
        manager?.showStageClick(at: normalized(point, in: window))
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
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return Set(
            windows.compactMap { window in
                guard window[kCGWindowOwnerPID as String] as? Int32 == pid,
                    window[kCGWindowLayer as String] as? Int == 0
                else { return nil }
                return window[kCGWindowNumber as String] as? CGWindowID
            })
    }
}
