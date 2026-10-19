import ApplicationServices
import Foundation
import MeetStageCore

/// Refers to one element of one snapshot. Handles from older snapshots are
/// rejected so a stale element can never be acted on.
struct ElementHandle: Hashable, Sendable {
    let generation: Int
    let id: Int
}

/// What sits under a point the demo is about to click.
struct HitTestResult: Sendable, Equatable {
    var isTarget: Bool
    var role: String
    var subrole: String?
    var label: String
}

struct FocusedElementInfo: Sendable, Equatable {
    var matchesTarget: Bool
    var role: String
    var isSecure: Bool
    var isInWebArea: Bool
    /// The focused element's text; never read for secure fields.
    var value: String?
}

/// The page an element or point sits in: its web area's visible frame
/// (global, top-left) and address.
struct WebAreaInfo: Sendable, Equatable {
    var frame: CGRect
    var url: URL?
}

/// Result of asking an element to perform its default action.
enum PressResult: Sendable, Equatable {
    case performed
    /// The app may or may not have acted (it timed out). Never repeat it.
    case uncertain
    /// The app refused; nothing happened.
    case refused
}

/// Input Accessibility can do in an app's own views, in place of a real key or wheel.
enum AXStandIn: Sendable, Equatable {
    case key(DemoKey)
    /// Scrolls the content under `at` (global, top-left) by `points`; positive moves it up.
    case scroll(points: Double, at: CGPoint)
}

/// What Accessibility's stand-in for a key or a scroll did.
enum AXStandInResult: Sendable, Equatable {
    /// It acted, with nothing to read back whether the app followed, as for a cancel.
    case performed
    /// It acted, and the effect reads back: the list's selection or the scroll bar
    /// moved, though the elements on screen may read the same, as a text view's do.
    case confirmed
    /// The app may or may not have acted (it timed out). Never repeat it.
    case uncertain
    /// Already at the edge it moves toward, so there was nothing to do; the real
    /// key or wheel would do nothing there either.
    case atEdge
    /// Nothing to act on, or the app refused or ignored it; nothing happened.
    case unavailable
}

extension AppEngine {
    static func detect(bundleURL: URL?) -> AppEngine {
        guard let bundleURL else { return .native }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let manager = FileManager.default
        if manager.fileExists(atPath: frameworks.appendingPathComponent("Electron Framework.framework").path) {
            return .electron
        }
        if manager.fileExists(atPath: bundleURL.appendingPathComponent("Contents/MacOS/XUL").path) { return .gecko }
        // Every Chromium-based browser ships a renderer helper app, whatever its framework is called.
        if let enumerator = manager.enumerator(at: frameworks, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasSuffix("Helper (Renderer).app") { return .chromium }
                if enumerator.level >= 5 || url.pathExtension == "app" { enumerator.skipDescendants() }
            }
        }
        if Bundle(url: bundleURL)?.bundleIdentifier == "com.apple.Safari" { return .webkit }
        return .native
    }
}

/// Owns all Accessibility IPC for demos on one serial queue, off the main actor.
/// Callers receive Sendable snapshots and handles; live `AXUIElement`s never leave.
actor AccessibilityService {
    static let shared = AccessibilityService()

    private let queue = DispatchSerialQueue(label: "com.lndgalante.bettermeets.accessibility")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var generation = 0
    private var handles: [Int: [AXUIElement]] = [:]
    private var preparedPIDs: [pid_t: AppEngine] = [:]
    private var enhancedPIDs: Set<pid_t> = []

    static let snapshotDeadline = Duration.milliseconds(2_500)

    init() {
        // Applies to every element created by this process, including children.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
    }

    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    nonisolated static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: Snapshots

    /// Turns on web accessibility once per process. Electron and Chromium build
    /// their tree asynchronously afterwards, so callers wait with `readySnapshot`.
    private func prepare(pid: pid_t, engine: AppEngine) {
        guard preparedPIDs[pid] != engine else { return }
        preparedPIDs[pid] = engine
        let app = AXUIElementCreateApplication(pid)
        switch engine {
        case .electron, .chromium:
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        case .native, .gecko, .webkit:
            break
        }
    }

    func snapshot(pid: pid_t, windowFrame: CGRect, engine: AppEngine) throws -> AXSnapshot {
        guard AXIsProcessTrusted() else { throw DemoError.permission }
        prepare(pid: pid, engine: engine)
        let app = AXUIElementCreateApplication(pid)
        guard let window = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: windowFrame) else {
            throw DemoError.sourceChanged
        }
        generation += 1
        let deadline = ContinuousClock.now.advanced(by: Self.snapshotDeadline)
        var builder = AXSnapshotBuilder(source: LiveAXSource(), window: window, windowFrame: windowFrame)
        builder.isExpired = { ContinuousClock.now >= deadline || Task.isCancelled }
        let (snapshot, elements) = builder.build(generation: generation)
        handles[generation] = elements
        handles = handles.filter { $0.key >= generation - 2 }
        return snapshot
    }

    /// A snapshot taken once web content has loaded. Native apps return at once.
    func readySnapshot(pid: pid_t, windowFrame: CGRect, engine: AppEngine, timeout: Duration = .seconds(4))
        async throws -> AXSnapshot
    {
        var snapshot = try snapshot(pid: pid, windowFrame: windowFrame, engine: engine)
        guard engine.rendersWebContent else { return snapshot }
        let start = ContinuousClock.now
        var delay = Duration.milliseconds(100)
        while snapshot.webContent?.isReady != true {
            // Gecko and WebKit show native views (new tab, start page) with no web area at all.
            if snapshot.webContent == nil, engine == .gecko || engine == .webkit { return snapshot }
            let elapsed = ContinuousClock.now - start
            if elapsed >= timeout { throw DemoError.webContentUnavailable(engine) }
            if engine == .chromium, elapsed >= .seconds(1), snapshot.webContent?.hasChildren != true,
                !enhancedPIDs.contains(pid)
            {
                // Some Chromium browsers only build the page tree for assistive apps.
                enhancedPIDs.insert(pid)
                AXUIElementSetAttributeValue(
                    AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
            try await Task.sleep(for: delay)
            delay = min(delay * 2, .milliseconds(800))
            snapshot = try self.snapshot(pid: pid, windowFrame: windowFrame, engine: engine)
        }
        return snapshot
    }

    // MARK: Element queries

    private func element(_ handle: ElementHandle) throws -> AXUIElement {
        guard let elements = handles[handle.generation], elements.indices.contains(handle.id) else {
            throw DemoError.targetNotFound("a control from an earlier screen")
        }
        return elements[handle.id]
    }

    /// Finds elements of an earlier snapshot among a later snapshot's elements by
    /// identity, which survives scrolling where positions and clipped frames don't.
    func follow(_ handles: [ElementHandle], into generation: Int) -> [Int?] {
        guard let elements = self.handles[generation] else { return handles.map { _ in nil } }
        return handles.map { handle in
            guard let old = try? element(handle) else { return nil }
            return elements.firstIndex { CFEqual($0, old) }
        }
    }

    func frame(of handle: ElementHandle) throws -> CGRect? {
        AccessibilityWindowResolver.frame(of: try element(handle))
    }

    func stringValue(of handle: ElementHandle) throws -> String? {
        let element = try element(handle)
        guard string(element, kAXSubroleAttribute) != "AXSecureTextField" else { return nil }
        return string(element, kAXValueAttribute)
    }

    func toggleValue(of handle: ElementHandle) throws -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(try element(handle), kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber).map { $0.intValue != 0 }
    }

    /// Selects all text in a field so typing replaces it. Returns false when the
    /// app ignores the request.
    func selectAllText(in handle: ElementHandle) throws -> Bool {
        let element = try element(handle)
        let length = (string(element, kAXValueAttribute) ?? "").utf16.count
        guard length > 0 else { return true }
        var range = CFRange(location: 0, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        var readBack: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &readBack) == .success,
            let readBack, CFGetTypeID(readBack) == AXValueGetTypeID()
        else { return false }
        var selected = CFRange()
        AXValueGetValue(unsafeDowncast(readBack, to: AXValue.self), .cfRange, &selected)
        return selected.location == 0 && selected.length == length
    }

    func scrollToVisible(_ handle: ElementHandle) throws {
        AXUIElementPerformAction(try element(handle), "AXScrollToVisible" as CFString)
    }

    /// Performs the element's default action without moving the pointer or
    /// activating the app, so it works while BetterMeets stays in front.
    func press(_ handle: ElementHandle) throws -> PressResult {
        switch AXUIElementPerformAction(try element(handle), kAXPressAction as CFString) {
        case .success: return .performed
        case .cannotComplete: return .uncertain
        default: return .refused
        }
    }

    /// Whether a field offers Accessibility's confirm action, its Return. Never for secure fields.
    func canConfirm(_ handle: ElementHandle) throws -> Bool {
        let element = try element(handle)
        return string(element, kAXSubroleAttribute) != "AXSecureTextField"
            && actionNames(of: element).contains(kAXConfirmAction)
    }

    /// Confirms a field the way Return does, without keyboard focus on the app.
    func confirm(_ handle: ElementHandle) throws -> PressResult {
        switch AXUIElementPerformAction(try element(handle), kAXConfirmAction as CFString) {
        case .success: return .performed
        case .cannotComplete: return .uncertain
        default: return .refused
        }
    }

    /// Presses the close button of the app's window at each frame (global,
    /// top-left origin). False if any window can't be found or closed that way.
    func closeWindows(pid: pid_t, frames: [CGRect]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return frames.map { frame in
            guard let window = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: frame),
                let button = elementAttribute(window, kAXCloseButtonAttribute)
            else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }.allSatisfy { $0 }
    }

    func focus(_ handle: ElementHandle) throws -> Bool {
        AXUIElementSetAttributeValue(try element(handle), kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// Replaces a text field's value through Accessibility, which apps apply as
    /// if the text were entered, without keyboard focus on the app.
    func setValue(_ text: String, of handle: ElementHandle) throws -> Bool {
        let element = try element(handle)
        guard string(element, kAXSubroleAttribute) != "AXSecureTextField" else { return false }
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
    }

    /// Selects all of a field's text and replaces the selection with `text`, as
    /// typing over it does, for a field that ignores a new value. Never for a
    /// secure field, and never through the clipboard. False when the field's
    /// selected text can't be set, its text can't be selected, or the app refused.
    func replaceText(with text: String, in handle: ElementHandle) throws -> Bool {
        let element = try element(handle)
        guard string(element, kAXSubroleAttribute) != "AXSecureTextField",
            string(element, kAXRoleAttribute) != "AXSecureTextField",
            isSettable(element, kAXSelectedTextAttribute), try selectAllText(in: handle)
        else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            == .success
    }

    /// What the window server would deliver a click at `point` to, across all
    /// apps. Used only when BetterMeets brings the source forward to click.
    func systemHitTest(pid: pid_t, point: CGPoint, target: ElementHandle) throws -> HitTestResult {
        let element = try element(target)
        var hit: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
                == .success, let hit
        else { return HitTestResult(isTarget: false, role: "", subrole: nil, label: "") }
        var owner: pid_t = 0
        AXUIElementGetPid(hit, &owner)
        var isTarget = false
        if owner == pid {
            let above = ancestors(of: hit, limit: 10)
            let below = ancestors(of: element, limit: 2)
            isTarget =
                CFEqual(hit, element) || above.contains { CFEqual($0, element) } || below.contains { CFEqual($0, hit) }
        }
        return describe(hit, isTarget: isTarget)
    }

    func focusedElement(pid: pid_t, target: ElementHandle?) throws -> FocusedElementInfo? {
        let app = AXUIElementCreateApplication(pid)
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute) else { return nil }
        var matches = false
        if let target {
            let element = try element(target)
            matches =
                CFEqual(focused, element) || ancestors(of: focused, limit: 3).contains { CFEqual($0, element) }
                || elementAttribute(element, kAXParentAttribute).map { CFEqual($0, focused) } == true
        }
        let subrole = string(focused, kAXSubroleAttribute)
        let isSecure = subrole == "AXSecureTextField"
        return FocusedElementInfo(
            matchesTarget: matches, role: string(focused, kAXRoleAttribute) ?? "",
            isSecure: isSecure,
            isInWebArea: ancestors(of: focused, limit: 30).contains {
                string($0, kAXRoleAttribute) == "AXWebArea"
            }, value: isSecure ? nil : string(focused, kAXValueAttribute))
    }

    /// Reports what the app would receive at `point` (global, top-left). The
    /// target counts as hit when the topmost element is it, inside it, or one of
    /// its two nearest ancestors. When another of the app's standard windows
    /// covers the point, like one the presenter is using, the target still counts
    /// as hit, since background input reaches it by element, not by position.
    func hitTest(pid: pid_t, point: CGPoint, target: ElementHandle) throws -> HitTestResult {
        let element = try element(target)
        var hit: AXUIElement?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit else {
            return HitTestResult(isTarget: false, role: "", subrole: nil, label: "")
        }
        if let covering = window(of: hit), let own = window(of: element), !CFEqual(covering, own),
            string(covering, kAXSubroleAttribute) == kAXStandardWindowSubrole
        {
            return describe(element, isTarget: true)
        }
        let isTarget =
            CFEqual(hit, element) || ancestors(of: hit, limit: 10).contains { CFEqual($0, element) }
            || ancestors(of: element, limit: 2).contains { CFEqual($0, hit) }
        return describe(hit, isTarget: isTarget)
    }

    /// Whether the element sits in an open dialog, sheet or alert, as snapshots tell it.
    func isInDialog(_ handle: ElementHandle) throws -> Bool {
        ancestors(of: try element(handle), limit: 40).contains { ancestor in
            AXRoleClass.isDialog(
                role: string(ancestor, kAXRoleAttribute) ?? "", subrole: string(ancestor, kAXSubroleAttribute))
        }
    }

    private func describe(_ element: AXUIElement, isTarget: Bool) -> HitTestResult {
        HitTestResult(
            isTarget: isTarget, role: string(element, kAXRoleAttribute) ?? "",
            subrole: string(element, kAXSubroleAttribute), label: String(name(of: element).prefix(120)))
    }

    /// What the policy's denial check reads at the click: the element's title or
    /// description, else its help text, as snapshots name an icon-only control.
    private func name(of element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].lazy
            .compactMap { self.string(element, $0) }.first { !$0.isEmpty } ?? ""
    }

    // MARK: Web areas

    /// The page holding `handle`, for scripting it in the browser.
    func webArea(containing handle: ElementHandle) throws -> WebAreaInfo? {
        webArea(around: try element(handle))
    }

    /// The page under `point` (global, top-left) in the app's window at
    /// `windowFrame`, even where another of the app's windows covers it.
    func webArea(pid: pid_t, windowFrame: CGRect, at point: CGPoint) -> WebAreaInfo? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: windowFrame) else {
            return nil
        }
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit,
            self.window(of: hit).map({ CFEqual($0, window) }) == true
        {
            return webArea(around: hit)
        }
        return outermostWebArea(in: window, at: point)
    }

    /// The page holding the app's focused element when it's in the window at
    /// `windowFrame`; nil when focus is outside every page or in another window.
    func focusedWebArea(pid: pid_t, windowFrame: CGRect) -> WebAreaInfo? {
        let app = AXUIElementCreateApplication(pid)
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute),
            let window = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: windowFrame),
            self.window(of: focused).map({ CFEqual($0, window) }) == true
        else { return nil }
        return webArea(around: focused)
    }

    /// The window holding `element`.
    private func window(of element: AXUIElement) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == kAXWindowRole { return element }
        return elementAttribute(element, kAXWindowAttribute)
            ?? ancestors(of: element, limit: 120).first { string($0, kAXRoleAttribute) == kAXWindowRole }
    }

    /// The outermost page in `window` whose frame holds `point`, found breadth
    /// first through the browser's own views, never into a page.
    private func outermostWebArea(in window: AXUIElement, at point: CGPoint) -> WebAreaInfo? {
        var queue = [(node: window, depth: 0)]
        var index = 0
        while index < queue.count, index < 600 {
            let (node, depth) = queue[index]
            index += 1
            if string(node, kAXRoleAttribute) == "AXWebArea" {
                if let page = webArea(around: node), page.frame.contains(point) { return page }
            } else if depth < 12 {
                queue += elements(node, kAXChildrenAttribute).map { ($0, depth + 1) }
            }
        }
        return nil
    }

    /// Frames nest web areas of their own, so this takes the outermost one in the
    /// window: the page whose address and viewport the tab's scripts see.
    private func webArea(around element: AXUIElement) -> WebAreaInfo? {
        var page: AXUIElement?
        for node in [element] + ancestors(of: element, limit: 120) {
            let role = string(node, kAXRoleAttribute)
            if role == kAXWindowRole { break }
            if role == "AXWebArea" { page = node }
        }
        guard let page, var frame = AccessibilityWindowResolver.frame(of: page) else { return nil }
        // WebKit's web area spans the whole document inside a scroll area; its viewport is the scroll area.
        if let parent = elementAttribute(page, kAXParentAttribute),
            string(parent, kAXRoleAttribute) == kAXScrollAreaRole,
            let viewport = AccessibilityWindowResolver.frame(of: parent), !frame.intersection(viewport).isNull
        {
            frame = frame.intersection(viewport)
        }
        var url: CFTypeRef?
        AXUIElementCopyAttributeValue(page, kAXURLAttribute as CFString, &url)
        return WebAreaInfo(frame: frame, url: url as? URL ?? (url as? String).flatMap(URL.init(string:)))
    }

    // MARK: Keys and scrolling

    /// What stands in for a key or a scroll, found in the demo window's own views.
    private enum StandInTarget {
        /// Performs `AXCancel`, which the element lists.
        case cancel(AXUIElement)
        /// Presses the sheet's or window's cancel button, the one Escape presses, which
        /// the policy's denials judged first.
        case cancelButton(AXUIElement)
        /// Selects `row` and scrolls it into view; nil when the selection is at that end already.
        case selectRow(list: AXUIElement, row: AXUIElement?)
        /// Sets the vertical scroll bar's value to `to`; nil when it's at that edge already.
        case scrollBar(AXUIElement, from: Double, to: Double?)
    }

    /// Whether Accessibility can do `input` in the window at `windowFrame`, so a
    /// caller can commit before `standIn(for:pid:windowFrame:)` does it. Throws
    /// `policyDenied` for a cancel button the policy denies.
    func canStandIn(for input: AXStandIn, pid: pid_t, windowFrame: CGRect) throws -> Bool {
        try standInTarget(for: input, pid: pid, windowFrame: windowFrame) != nil
    }

    /// Does what a key or a scroll would in the app's own views, without the real
    /// key or wheel, and only in the window at `windowFrame` or a sheet on it, never
    /// in a page or another of the app's windows. It uses only actions an element
    /// lists and attributes it reports settable.
    func standIn(for input: AXStandIn, pid: pid_t, windowFrame: CGRect) throws -> AXStandInResult {
        guard let target = try standInTarget(for: input, pid: pid, windowFrame: windowFrame) else {
            return .unavailable
        }
        switch target {
        case .cancel(let element):
            return Self.result(AXUIElementPerformAction(element, kAXCancelAction as CFString))
        case .cancelButton(let button):
            return Self.result(AXUIElementPerformAction(button, kAXPressAction as CFString))
        case .selectRow(let list, let row):
            guard let row else { return .atEdge }
            let result = Self.result(
                AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, [row] as CFArray))
            guard result == .performed else { return result }
            // A list that ignored the selection did nothing, so the real key may try.
            guard elements(list, kAXSelectedRowsAttribute).contains(where: { CFEqual($0, row) }) else {
                return .unavailable
            }
            AXUIElementPerformAction(row, "AXScrollToVisible" as CFString)
            return .confirmed
        case .scrollBar(let bar, let from, let to):
            guard let to else { return .atEdge }
            let result = Self.result(
                AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: to)))
            guard result == .performed else { return result }
            // A bar that stayed put scrolled nothing, so the real wheel may try.
            return number(bar, kAXValueAttribute).map({ abs($0 - from) > 0.000_1 }) == true ? .confirmed : .unavailable
        }
    }

    private static func result(_ error: AXError) -> AXStandInResult {
        switch error {
        case .success: .performed
        case .cannotComplete: .uncertain
        default: .unavailable
        }
    }

    private func standInTarget(for input: AXStandIn, pid: pid_t, windowFrame: CGRect) throws -> StandInTarget? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = AccessibilityWindowResolver.uniqueMatchingWindow(in: app, sourceFrame: windowFrame) else {
            return nil
        }
        let element: AXUIElement?
        switch input {
        case .key:
            element = elementAttribute(app, kAXFocusedUIElementAttribute)
        case .scroll(_, let point):
            var hit: AXUIElement?
            let found = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success
            element = found ? hit : nil
        }
        // A page scripts its own keys and scrolling, and another window is never the demo's.
        guard let element, belongs(element, to: window), !isInWebArea(element) else { return nil }
        let scope = enclosing(element, upTo: window)
        switch input {
        case .key(.escape):
            if let cancelling = scope.enumerated().first(where: {
                ($0.offset == 0 || isDialog($0.element)) && actionNames(of: $0.element).contains(kAXCancelAction)
            }) {
                return .cancel(cancelling.element)
            }
            let owners = scope.filter { string($0, kAXRoleAttribute) == kAXSheetRole } + [window]
            guard let button = owners.compactMap({ elementAttribute($0, kAXCancelButtonAttribute) }).first,
                bool(button, kAXEnabledAttribute) != false
            else { return nil }
            // Escape presses it too, but a press through Accessibility is judged like any click.
            let label = name(of: button)
            if !label.isEmpty,
                case .deny(let reason) = DemoActionPolicy.evaluate(
                    .click(DemoPolicyElement(kind: .button, label: label)), prompt: "", startHost: nil, approved: false)
            {
                throw DemoError.policyDenied(reason)
            }
            return .cancelButton(button)
        case .key(let key) where key == .up || key == .down:
            // A field's arrows move its caret, not the list it sits in.
            let fields = ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"]
            guard !fields.contains(string(element, kAXRoleAttribute) ?? ""),
                let list = scope.prefix(8).first(where: {
                    [kAXTableRole, kAXOutlineRole, kAXListRole].contains(string($0, kAXRoleAttribute) ?? "")
                }), isSettable(list, kAXSelectedRowsAttribute)
            else { return nil }
            let rows = elements(list, kAXRowsAttribute)
            guard !rows.isEmpty else { return nil }
            let selected = elements(list, kAXSelectedRowsAttribute).compactMap { row in
                rows.firstIndex { CFEqual($0, row) }
            }
            let next = DemoAccessibilityMotion.row(after: selected, count: rows.count, down: key == .down)
            return .selectRow(list: list, row: next.map { rows[$0] })
        case .key(let key) where key == .pageUp || key == .pageDown:
            let sign: Double = key == .pageDown ? 1 : -1
            return scrollBar(in: scope) { visible in sign * DemoAccessibilityMotion.pageFraction * visible }
        case .scroll(let points, _):
            return scrollBar(in: scope) { _ in points }
        case .key:
            return nil
        }
    }

    /// The nearest scroll area in `scope` with a vertical scroll bar, and the value
    /// that moves its content by `points(visibleHeight)`. Nil when that bar's value
    /// can't be set or its sizes can't be read, since the real wheel would scroll it.
    private func scrollBar(in scope: [AXUIElement], points: (Double) -> Double) -> StandInTarget? {
        for node in scope where string(node, kAXRoleAttribute) == kAXScrollAreaRole {
            guard let bar = elementAttribute(node, kAXVerticalScrollBarAttribute) else { continue }
            guard isSettable(bar, kAXValueAttribute), let value = number(bar, kAXValueAttribute),
                let visible = AccessibilityWindowResolver.frame(of: node)?.height,
                let content = elements(node, kAXContentsAttribute).compactMap({
                    AccessibilityWindowResolver.frame(of: $0)?.height
                }).max()
            else { return nil }
            let next = DemoAccessibilityMotion.scrollValue(
                from: value, by: points(visible), visible: visible, content: content)
            return .scrollBar(bar, from: value, to: next)
        }
        return nil
    }

    /// `element` and what holds it, up to and ending with `window`: a sheet on the
    /// window is in it, and nothing past the window is.
    private func enclosing(_ element: AXUIElement, upTo window: AXUIElement) -> [AXUIElement] {
        var scope = [element]
        var current = element
        while !CFEqual(current, window), scope.count < 30, let parent = elementAttribute(current, kAXParentAttribute),
            string(parent, kAXRoleAttribute) != kAXApplicationRole
        {
            scope.append(parent)
            current = parent
        }
        return CFEqual(current, window) ? scope : scope + [window]
    }

    /// Whether `element` is in `window` itself or in a sheet on it, never in another of the app's windows.
    private func belongs(_ element: AXUIElement, to window: AXUIElement) -> Bool {
        guard let own = self.window(of: element) else { return false }
        if CFEqual(own, window) { return true }
        return string(own, kAXRoleAttribute) == kAXSheetRole
            && elementAttribute(own, kAXParentAttribute).map { CFEqual($0, window) } == true
    }

    private func isInWebArea(_ element: AXUIElement) -> Bool {
        ([element] + ancestors(of: element, limit: 120)).contains { string($0, kAXRoleAttribute) == "AXWebArea" }
    }

    private func isDialog(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXSheetRole
            || [kAXDialogSubrole, kAXSystemDialogSubrole].contains(string(element, kAXSubroleAttribute) ?? "")
    }

    // MARK: Helpers

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func number(_ element: AXUIElement, _ attribute: String) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private func ancestors(of element: AXUIElement, limit: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var current = element
        while result.count < limit, let parent = elementAttribute(current, kAXParentAttribute) {
            result.append(parent)
            current = parent
        }
        return result
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let items = value as? [AnyObject]
        else { return [] }
        return items.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
        }
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

/// Reads live elements with one batched IPC per node.
struct LiveAXSource: AXNodeSource {
    private enum Slot: Int, CaseIterable {
        case role, subrole, title, description, value, position, size, children, enabled
        case identifier, domIdentifier, selected, focused, placeholder, ariaCurrent, help, url
        case loaded, loadingProgress, busy, maxValue
    }

    private let attributes: CFArray =
        [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute, kAXEnabledAttribute, kAXIdentifierAttribute,
            "AXDOMIdentifier", kAXSelectedAttribute, kAXFocusedAttribute, kAXPlaceholderValueAttribute, "AXARIACurrent",
            kAXHelpAttribute, kAXURLAttribute, "AXLoaded", "AXLoadingProgress", kAXElementBusyAttribute,
            kAXMaxValueAttribute
        ] as CFArray

    func read(_ handle: AXUIElement) -> (node: AXRawNode, children: [AXUIElement])? {
        var values: CFArray?
        guard
            AXUIElementCopyMultipleAttributeValues(handle, attributes, AXCopyMultipleAttributeOptions(), &values)
                == .success, let slots = values as? [AnyObject], slots.count == Slot.allCases.count
        else { return nil }
        func value(_ slot: Slot) -> AnyObject? {
            let object = slots[slot.rawValue]
            // Unsupported attributes come back as AXValue-wrapped errors.
            if CFGetTypeID(object) == AXValueGetTypeID(),
                AXValueGetType(unsafeDowncast(object, to: AXValue.self)) == .axError
            {
                return nil
            }
            return object
        }
        func string(_ slot: Slot) -> String? { value(slot) as? String }
        func bool(_ slot: Slot) -> Bool? { (value(slot) as? NSNumber)?.boolValue }

        var node = AXRawNode()
        node.role = string(.role) ?? ""
        node.subrole = string(.subrole)
        node.title = string(.title)
        node.description = string(.description)
        let isSecure = node.subrole == "AXSecureTextField" || node.role == "AXSecureTextField"
        if !isSecure {
            let rawValue = value(.value)
            node.stringValue = rawValue as? String
            node.numberValue = (rawValue as? NSNumber)?.doubleValue
        }
        if let origin = point(value(.position)), let size = size(value(.size)) {
            node.frame = CGRect(origin: origin, size: size)
        }
        node.enabled = bool(.enabled) ?? true
        node.identifier = string(.identifier) ?? string(.domIdentifier)
        let ariaCurrent = string(.ariaCurrent) ?? (bool(.ariaCurrent) == true ? "true" : nil)
        node.selected = bool(.selected) == true || (ariaCurrent.map { !$0.isEmpty && $0 != "false" } ?? false)
        node.focused = bool(.focused) ?? false
        node.placeholder = string(.placeholder)
        node.help = string(.help)
        node.url = (value(.url) as? URL)?.absoluteString ?? string(.url)
        node.loaded = bool(.loaded)
        node.loadingProgress = (value(.loadingProgress) as? NSNumber)?.doubleValue
        node.busy = bool(.busy) ?? false
        node.maxValue = (value(.maxValue) as? NSNumber)?.doubleValue
        let children = (value(.children) as? [AnyObject] ?? []).compactMap { child -> AXUIElement? in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? unsafeDowncast(child, to: AXUIElement.self) : nil
        }
        return (node, children)
    }

    /// A static text's words, or another element's title, for the control it titles.
    /// Any other element's value is never read, so a field's text never becomes a label.
    func titleElementText(of handle: AXUIElement) -> String? {
        var reference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(handle, kAXTitleUIElementAttribute as CFString, &reference) == .success,
            let reference, CFGetTypeID(reference) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(reference, to: AXUIElement.self)
        var values: CFArray?
        let attributes = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute] as CFArray
        guard
            AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(), &values)
                == .success, let slots = values as? [AnyObject], slots.count == 3
        else { return nil }
        let texts = slots.map { $0 as? String }
        let (role, title, description) = (texts[0], texts[1], texts[2])
        var candidates = [title, description]
        if role == kAXStaticTextRole {
            var words: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &words)
            candidates = [words as? String, title]
        }
        return candidates.compactMap { $0 }.first { !$0.isEmpty }
    }

    private func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) ? point : nil
    }

    private func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) ? size : nil
    }
}
