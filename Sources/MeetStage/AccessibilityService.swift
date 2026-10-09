import ApplicationServices
import Foundation

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

/// Result of asking an element to perform its default action.
enum PressResult: Sendable, Equatable {
    case performed
    /// The app may or may not have acted (it timed out). Never repeat it.
    case uncertain
    /// The app refused; nothing happened.
    case refused
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
        let label = string(hit, kAXTitleAttribute) ?? string(hit, kAXDescriptionAttribute) ?? ""
        return HitTestResult(
            isTarget: isTarget, role: string(hit, kAXRoleAttribute) ?? "", subrole: string(hit, kAXSubroleAttribute),
            label: String(label.prefix(120)))
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
    /// its two nearest ancestors.
    func hitTest(pid: pid_t, point: CGPoint, target: ElementHandle) throws -> HitTestResult {
        let element = try element(target)
        var hit: AXUIElement?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit else {
            return HitTestResult(isTarget: false, role: "", subrole: nil, label: "")
        }
        let isTarget =
            CFEqual(hit, element) || ancestors(of: hit, limit: 10).contains { CFEqual($0, element) }
            || ancestors(of: element, limit: 2).contains { CFEqual($0, hit) }
        let label = string(hit, kAXTitleAttribute) ?? string(hit, kAXDescriptionAttribute) ?? ""
        return HitTestResult(
            isTarget: isTarget, role: string(hit, kAXRoleAttribute) ?? "", subrole: string(hit, kAXSubroleAttribute),
            label: String(label.prefix(120)))
    }

    // MARK: Helpers

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
        case loaded, loadingProgress, busy
    }

    private let attributes: CFArray =
        [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
            kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute, kAXEnabledAttribute, kAXIdentifierAttribute,
            "AXDOMIdentifier", kAXSelectedAttribute, kAXFocusedAttribute, kAXPlaceholderValueAttribute, "AXARIACurrent",
            kAXHelpAttribute, kAXURLAttribute, "AXLoaded", "AXLoadingProgress", "AXElementBusy"
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
        let children = (value(.children) as? [AnyObject] ?? []).compactMap { child -> AXUIElement? in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? unsafeDowncast(child, to: AXUIElement.self) : nil
        }
        return (node, children)
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
