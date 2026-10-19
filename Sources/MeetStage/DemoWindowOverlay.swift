import AppKit
import SwiftUI

/// Marks the window BetterMeets drives while it builds, tests, or goes back to
/// the start: an accent badge over the window's top-left corner and the demo's
/// own arrow inside it, so the person's pointer stays theirs. Both are panels at
/// the window's level, ordered just above it, so the person's other windows still
/// cover them. They follow the window, hide while it's minimized, hidden, on
/// another Space, or gone, and never activate BetterMeets. The arrow's panel lets
/// every click through; the badge takes clicks and shows its label on hover, even
/// while BetterMeets is in the background. Play brings the app forward and uses
/// real input, so it never shows the overlay.
@MainActor
final class DemoWindowOverlay {
    private static let refreshInterval = Duration.milliseconds(60)

    let chrome = DemoWindowOverlayChrome()
    /// Called when the person clicks the badge.
    var onBadgeClick: (@MainActor () -> Void)?

    var activity: DemoWindowActivity {
        get { chrome.activity }
        set {
            guard chrome.activity != newValue else { return }
            chrome.activity = newValue
            relabel()
        }
    }

    private(set) var windowID: CGWindowID?
    private var pid: pid_t = 0
    private(set) var cursorPanel: DemoWindowOverlayPanel?
    private(set) var badgePanel: DemoWindowOverlayPanel?
    private var badgeControl: DemoWindowBadgeControl?
    private var tracking: Task<Void, Never>?
    /// The window's global frame (top-left origin) as last seen on screen; nil once
    /// the window isn't on screen.
    private var windowFrame: CGRect?
    /// How wide the badge's panel is for the capsule; it grows before the capsule does and shrinks after.
    private var badgeRoom = DemoWindowOverlayGeometry.collapsedBadgeWidth
    private var badgeResize: Task<Void, Never>?
    private var rippleTasks: [UUID: Task<Void, Never>] = [:]
    private var isSuspended = false
    private var labelWidths: [String: CGFloat] = [:]

    deinit {
        tracking?.cancel()
    }

    /// Shown on the window right now.
    var isShown: Bool { cursorPanel?.isVisible == true }

    /// Puts the overlay on the window `windowID` of the app `pid`, and follows it until `detach()`.
    func attach(windowID: CGWindowID, pid: pid_t) {
        if self.windowID == windowID, self.pid == pid, cursorPanel != nil { return refresh() }
        detach()
        self.windowID = windowID
        self.pid = pid
        cursorPanel = .makeCursor(rootView: DemoWindowCursorView(chrome: chrome))
        let control = DemoWindowBadgeControl(chrome: chrome)
        control.onHover = { [weak self] inside in self?.hoverBadge(inside) }
        control.onClick = { [weak self] in self?.onBadgeClick?() }
        badgeControl = control
        badgePanel = .makeBadge(control: control)
        refresh()
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    /// Takes the overlay off the window and forgets it.
    func detach() {
        tracking?.cancel()
        tracking = nil
        rippleTasks.values.forEach { $0.cancel() }
        rippleTasks.removeAll()
        cursorPanel?.close()
        badgePanel?.close()
        cursorPanel = nil
        badgePanel = nil
        badgeControl = nil
        windowID = nil
        windowFrame = nil
        isSuspended = false
        collapseBadge()
        chrome.pointer = nil
        chrome.ripples = []
    }

    /// Glides the arrow to `point` over `travel` seconds, as the stage's `DemoPointer` does; nil hides it.
    func movePointer(to point: NormalizedWindowPoint?, travel: Double) {
        let pointer = point.flatMap(DemoWindowOverlayGeometry.clamped).map { DemoPointer(location: $0, travel: travel) }
        guard chrome.pointer != pointer else { return }
        let appears = (chrome.pointer == nil) != (pointer == nil)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(appears && !reduceMotion ? .easeOut(duration: 0.2) : nil) { chrome.pointer = pointer }
    }

    /// A click ripple at `point`, like the stage's.
    func ripple(at point: NormalizedWindowPoint, color: PresentationColor = .orange, size: PresentationSize = .medium) {
        guard let point = DemoWindowOverlayGeometry.clamped(point) else { return }
        let ripple = ClickPresentation(location: point, color: color, size: size)
        chrome.ripples.append(ripple)
        rippleTasks[ripple.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: ClickPresentation.duration)
            } catch {
                return
            }
            self?.chrome.ripples.removeAll { $0.id == ripple.id }
            self?.rippleTasks[ripple.id] = nil
        }
    }

    /// The badge says BetterMeets is waiting for a pause in the person's input.
    func setWaiting(_ waiting: Bool) {
        guard chrome.isWaiting != waiting else { return }
        chrome.isWaiting = waiting
        relabel()
    }

    /// Hides the overlay while BetterMeets borrows the window for real input, so
    /// that input and its hit test find the app, and fades it back after.
    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended { hide() } else { reveal() }
    }

    // MARK: Tracking

    /// Follows the window: places both panels on it, orders them just above it
    /// when something came between, or hides them when it isn't on screen.
    func refresh() {
        guard let windowID, let cursorPanel, let badgePanel else { return }
        guard !isSuspended else { return hide() }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .optionIncludingWindow], windowID)
        let windows = (list as? [[String: Any]] ?? []).compactMap(DemoListedWindow.init)
        guard let primary = NSScreen.screens.first,
            let target = DemoWindowStacking.visibleTarget(in: windows, id: windowID, pid: pid)
        else {
            windowFrame = nil
            return hide()
        }
        windowFrame = target.frame
        let frames = DemoWindowOverlayFrames.make(
            window: target.frame, badgeWidth: badgeRoom, primaryScreenFrame: primary.frame)
        let level = NSWindow.Level(rawValue: target.layer)
        for panel in [cursorPanel, badgePanel] where panel.level != level { panel.level = level }
        if cursorPanel.frame != frames.cursor { cursorPanel.setFrame(frames.cursor, display: true) }
        var overlays = [cursorPanel.cgWindowID]
        if let badge = frames.badge {
            if badgePanel.frame != badge { badgePanel.setFrame(badge, display: true) }
            overlays.append(badgePanel.cgWindowID)
        } else {
            badgePanel.orderOut(nil)
        }
        let anchor = DemoWindowStacking.anchor(in: windows, target: target, overlays: overlays)
        // The window server lists changes a moment later, so panels just ordered out may still be listed.
        let visible = cursorPanel.isVisible && (frames.badge == nil || badgePanel.isVisible)
        guard !visible || !DemoWindowStacking.isOrdered(overlays, above: anchor, in: windows, target: target)
        else { return }
        cursorPanel.order(.above, relativeTo: Int(anchor))
        if frames.badge != nil { badgePanel.order(.above, relativeTo: cursorPanel.windowNumber) }
    }

    private func hide() {
        cursorPanel?.orderOut(nil)
        badgePanel?.orderOut(nil)
        if chrome.isExpanded || chrome.isPressed { collapseBadge() }
    }

    /// Brings the overlay back after a borrowed moment, fading in unless Reduce Motion is on.
    private func reveal() {
        guard !isSuspended, let cursorPanel, let badgePanel else { return }
        let panels = [cursorPanel, badgePanel]
        let fades = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if fades { panels.forEach { $0.alphaValue = 0 } }
        refresh()
        guard fades, isShown else {
            // The window isn't on screen, so the panels show at full strength when it is.
            panels.forEach { $0.alphaValue = 1 }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panels.forEach { $0.animator().alphaValue = 1 }
        }
    }

    // MARK: Badge

    /// The pointer entered or left the badge: it shows its label, or folds back to the glyph.
    func hoverBadge(_ inside: Bool) {
        guard isShown || !inside else { return }
        resizeBadge(to: inside ? expandedBadgeWidth() : DemoWindowOverlayGeometry.collapsedBadgeWidth, expanded: inside)
    }

    /// Back to the glyph at once, without animating.
    private func collapseBadge() {
        badgeResize?.cancel()
        badgeResize = nil
        badgeRoom = DemoWindowOverlayGeometry.collapsedBadgeWidth
        chrome.isExpanded = false
        chrome.isPressed = false
        chrome.capsuleWidth = badgeRoom
    }

    private func relabel() {
        badgeControl?.toolTip = chrome.help
        guard chrome.isExpanded else { return }
        resizeBadge(to: expandedBadgeWidth(), expanded: true)
    }

    /// Animates the capsule to `width`. Its panel grows first and shrinks once
    /// the capsule has, so the capsule is never cut and no empty panel takes clicks for long.
    private func resizeBadge(to width: CGFloat, expanded: Bool) {
        badgeResize?.cancel()
        badgeResize = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if width > badgeRoom || reduceMotion {
            badgeRoom = width
            refresh()
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            chrome.isExpanded = expanded
            chrome.capsuleWidth = width
        }
        guard width < badgeRoom else { return }
        badgeResize = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            guard let self else { return }
            self.badgeRoom = width
            self.refresh()
        }
    }

    /// The capsule with its label, measured as SwiftUI draws it, and no wider than the window allows.
    private func expandedBadgeWidth() -> CGFloat {
        let label = chrome.label
        let labelWidth: CGFloat
        if let measured = labelWidths[label] {
            labelWidth = measured
        } else {
            let host = NSHostingView(rootView: Text(label).font(DemoWindowBadgeView.font).fixedSize())
            labelWidth = ceil(host.fittingSize.width)
            labelWidths[label] = labelWidth
        }
        let width = DemoWindowOverlayGeometry.badgeWidth(labelWidth: labelWidth)
        guard let frame = windowFrame else { return width }
        return max(
            min(width, DemoWindowOverlayGeometry.maximumBadgeWidth(inWindow: frame)),
            DemoWindowOverlayGeometry.collapsedBadgeWidth)
    }
}

/// What BetterMeets is doing in the window, as the badge says it.
enum DemoWindowActivity: Equatable, Sendable {
    case building, testing, returning

    var label: String {
        switch self {
        case .building: "BetterMeets is building"
        case .testing: "BetterMeets is testing"
        case .returning: "BetterMeets is going back to the start"
        }
    }
}

/// How the overlay looks right now. The controller changes it; the panels' views draw it.
@MainActor
@Observable
final class DemoWindowOverlayChrome {
    var pointer: DemoPointer?
    var ripples: [ClickPresentation] = []
    var activity = DemoWindowActivity.building
    var isWaiting = false
    /// The badge shows its label while the pointer is over it.
    var isExpanded = false
    var isPressed = false
    var capsuleWidth = DemoWindowOverlayGeometry.collapsedBadgeWidth

    init() {}

    var label: String { isWaiting ? "Waiting for a pause" : activity.label }

    var help: String {
        isWaiting
            ? "BetterMeets needs this window in front for a moment, and waits until you stop typing or moving the pointer."
            : "BetterMeets is using this window. You can keep working in other windows."
    }

    var symbol: String { isWaiting ? "hourglass" : "cursorarrow.motionlines" }
}

// MARK: - Geometry

/// The overlay's measurements and frame math, apart from AppKit.
enum DemoWindowOverlayGeometry {
    static let badgeHeight: CGFloat = 22
    /// From the window's top-left corner, over the traffic lights.
    static let badgeInset = CGPoint(x: 8, y: 6)
    static let badgePadding: CGFloat = 9
    static let badgeGlyphWidth: CGFloat = 14
    static let badgeSpacing: CGFloat = 5
    /// Room around the capsule in its panel for the shadow.
    static let badgeShadowPadding: CGFloat = 3
    static let collapsedBadgeWidth = badgePadding * 2 + badgeGlyphWidth
    /// Room around the window in the arrow's panel, so the arrow and ripples aren't cut at its edges.
    static let cursorMargin: CGFloat = 40

    /// The capsule's width: the glyph alone, or with a label `labelWidth` wide.
    static func badgeWidth(labelWidth: CGFloat?) -> CGFloat {
        guard let labelWidth, labelWidth > 0 else { return collapsedBadgeWidth }
        return collapsedBadgeWidth + badgeSpacing + labelWidth
    }

    /// The widest the capsule gets in `window`, keeping its inset on both sides.
    static func maximumBadgeWidth(inWindow window: CGRect) -> CGFloat {
        window.width - badgeInset.x * 2
    }

    /// The capsule in global Quartz coordinates (top-left origin), at the window's
    /// top-left corner and at most as wide as the window allows. Nil when the window
    /// is too small to hold even the glyph.
    static func badgeRect(inWindow window: CGRect, width: CGFloat) -> CGRect? {
        let available = maximumBadgeWidth(inWindow: window)
        guard available >= collapsedBadgeWidth, window.height >= badgeHeight + badgeInset.y * 2 else { return nil }
        return CGRect(
            x: window.minX + badgeInset.x, y: window.minY + badgeInset.y,
            width: min(max(width, collapsedBadgeWidth), available), height: badgeHeight)
    }

    /// The arrow's panel in global Quartz coordinates: the window with `cursorMargin` all round.
    static func cursorRect(inWindow window: CGRect) -> CGRect {
        window.insetBy(dx: -cursorMargin, dy: -cursorMargin)
    }

    /// Where a normalized window point falls in the arrow's panel, top-left origin.
    static func localPoint(_ point: NormalizedWindowPoint, windowSize: CGSize) -> CGPoint {
        CGPoint(x: cursorMargin + point.x * windowSize.width, y: cursorMargin + point.y * windowSize.height)
    }

    /// Keeps the arrow inside the window; nil for a point that isn't a number.
    static func clamped(_ point: NormalizedWindowPoint) -> NormalizedWindowPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return NormalizedWindowPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

/// Where the overlay's panels go on a window, in AppKit screen coordinates.
struct DemoWindowOverlayFrames: Equatable {
    var cursor: CGRect
    /// Nil when the window is too small for the badge.
    var badge: CGRect?

    /// `window` is the source's frame in global Quartz coordinates, as the window server lists it.
    static func make(window: CGRect, badgeWidth: CGFloat, primaryScreenFrame: CGRect) -> Self {
        let appKit = { (rect: CGRect) in
            SourceOverlayGeometry.appKitFrame(forQuartzFrame: rect, primaryScreenFrame: primaryScreenFrame)
        }
        let padding = DemoWindowOverlayGeometry.badgeShadowPadding
        return DemoWindowOverlayFrames(
            cursor: appKit(DemoWindowOverlayGeometry.cursorRect(inWindow: window)),
            badge: DemoWindowOverlayGeometry.badgeRect(inWindow: window, width: badgeWidth)
                .map { appKit($0.insetBy(dx: -padding, dy: -padding)) })
    }
}

/// One window in the window server's list, as the overlay needs it.
struct DemoListedWindow: Equatable {
    var number: CGWindowID
    var pid: pid_t
    /// The window level.
    var layer: Int
    /// Global Quartz coordinates, top-left origin.
    var frame: CGRect
    var isOnScreen: Bool
    var alpha: Double

    init(number: CGWindowID, pid: pid_t, layer: Int = 0, frame: CGRect, isOnScreen: Bool = true, alpha: Double = 1) {
        self.number = number
        self.pid = pid
        self.layer = layer
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.alpha = alpha
    }

    /// From a `CGWindowListCopyWindowInfo` entry; nil without a number, owner, or bounds.
    init?(_ info: [String: Any]) {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
            let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        self.init(
            number: number.uint32Value, pid: pid.int32Value,
            layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0, frame: frame,
            isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
            alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
    }
}

/// Where the overlay belongs in the window server's stack. `windows` are front to
/// back, as `CGWindowListCopyWindowInfo` lists the source and the windows in front of it.
enum DemoWindowStacking {
    /// The source, when the overlay should show on it: still the app's, on screen in
    /// this Space (not minimized or hidden), drawn, and with an area.
    static func visibleTarget(in windows: [DemoListedWindow], id: CGWindowID, pid: pid_t)
        -> DemoListedWindow?
    {
        guard let target = windows.first(where: { $0.number == id }), target.pid == pid, target.isOnScreen,
            target.alpha > 0, target.frame.minX.isFinite, target.frame.minY.isFinite,
            target.frame.width.isFinite, target.frame.height.isFinite, target.frame.width >= 1,
            target.frame.height >= 1
        else { return nil }
        return target
    }

    /// The window the overlay goes just above: the source, or the topmost of the
    /// app's own windows stacked right on it, like a sheet, so the arrow shows on those too.
    static func anchor(
        in windows: [DemoListedWindow], target: DemoListedWindow, overlays: [CGWindowID]
    ) -> CGWindowID {
        var anchor = target.number
        for window in stack(above: target, in: windows) where !overlays.contains(window.number) {
            guard window.pid == target.pid, isAttached(window, to: target) else { break }
            anchor = window.number
        }
        return anchor
    }

    /// Whether a window of the source's app belongs to the source, like a sheet,
    /// a find bar or a bubble: smaller, and within its frame give or take a couple
    /// of points. Another document window of the app, like one the person is
    /// using, is no part of it, even when it covers it exactly.
    static func isAttached(_ window: DemoListedWindow, to target: DemoListedWindow) -> Bool {
        let frame = window.frame
        return target.frame.insetBy(dx: -2, dy: -2).contains(frame)
            && frame.width * frame.height < target.frame.width * target.frame.height
    }

    /// Whether `overlays` sit right above `anchor`, nearest first, with no other
    /// window of the source's level between. Windows on other levels never count.
    static func isOrdered(
        _ overlays: [CGWindowID], above anchor: CGWindowID, in windows: [DemoListedWindow],
        target: DemoListedWindow
    ) -> Bool {
        guard !overlays.isEmpty else { return true }
        let stack = stack(above: target, in: windows)
        let start: Int
        if anchor == target.number {
            start = 0
        } else if let index = stack.firstIndex(where: { $0.number == anchor }) {
            start = index + 1
        } else {
            return false
        }
        return stack.dropFirst(start).prefix(overlays.count).map(\.number) == overlays
    }

    /// The windows in front of `target` on its level, nearest first.
    private static func stack(above target: DemoListedWindow, in windows: [DemoListedWindow])
        -> [DemoListedWindow]
    {
        guard let index = windows.firstIndex(where: { $0.number == target.number }) else { return [] }
        return windows[..<index].reversed().filter { $0.layer == target.layer }
    }
}

// MARK: - Panels

/// A borderless, nonactivating panel on the source window's level. It never takes
/// focus from the app the person is using and stays where it's put.
final class DemoWindowOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    var cgWindowID: CGWindowID { CGWindowID(truncatingIfNeeded: windowNumber) }

    /// The arrow's panel: the whole window, and every click goes through it.
    @MainActor static func makeCursor(rootView: some View) -> DemoWindowOverlayPanel {
        let panel = make(title: "BetterMeets pointer")
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: rootView)
        // The overlay sizes the panel; the view never pushes its own size onto it.
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    /// The badge's panel: just the capsule, which takes clicks and hover.
    @MainActor static func makeBadge(control: NSView) -> DemoWindowOverlayPanel {
        let panel = make(title: "BetterMeets status")
        panel.ignoresMouseEvents = false
        // It's used from other apps, so its help tag must show while BetterMeets is inactive.
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.contentView = control
        return panel
    }

    /// Not floating, on every Space and beside full-screen apps (the overlay hides
    /// itself where the window isn't), left out of Mission Control and window
    /// cycling, untouched by hiding BetterMeets, and out of screen capture where
    /// that's honored, since it's for the person at the Mac.
    @MainActor private static func make(title: String) -> DemoWindowOverlayPanel {
        let panel = DemoWindowOverlayPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.setAccessibilityLabel(title)
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.sharingType = .none
        return panel
    }
}

/// Draws the badge and takes its clicks and hover itself, through a tracking area
/// that works while BetterMeets is in the background. To VoiceOver it's a button.
final class DemoWindowBadgeControl: NSView {
    let chrome: DemoWindowOverlayChrome
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    init(chrome: DemoWindowOverlayChrome) {
        self.chrome = chrome
        super.init(frame: .zero)
        let host = NSHostingView(rootView: DemoWindowBadgeView(chrome: chrome))
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        toolTip = chrome.help
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clicks land here, never on the drawing.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    /// Acts on the first click, so the badge works while another app is frontmost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { chrome.isPressed = true }
    override func mouseDragged(with event: NSEvent) { chrome.isPressed = contains(event) }

    override func mouseUp(with event: NSEvent) {
        chrome.isPressed = false
        if contains(event) { onClick?() }
    }

    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { chrome.label }
    override func accessibilityHelp() -> String? { chrome.help }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

// MARK: - Views

/// The accent capsule with a white glyph, and its label while the pointer is over it.
struct DemoWindowBadgeView: View {
    static let font = Font.system(size: 11, weight: .semibold, design: .rounded)

    let chrome: DemoWindowOverlayChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let capsule = Capsule(style: .continuous)
        HStack(spacing: DemoWindowOverlayGeometry.badgeSpacing) {
            Image(systemName: chrome.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: DemoWindowOverlayGeometry.badgeGlyphWidth)
            if chrome.isExpanded {
                Text(chrome.label)
                    .font(Self.font)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DemoWindowOverlayGeometry.badgePadding)
        .frame(width: chrome.capsuleWidth, height: DemoWindowOverlayGeometry.badgeHeight, alignment: .leading)
        .background(Color.accentColor, in: capsule)
        .overlay { DemoWindowBadgeRing(turns: !chrome.isWaiting) }
        .overlay {
            if contrast == .increased {
                capsule.strokeBorder(.white.opacity(0.6), lineWidth: 1)
            }
        }
        .clipShape(capsule)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .scaleEffect(chrome.isPressed && !reduceMotion ? 0.96 : 1)
        .opacity(chrome.isPressed ? 0.82 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: chrome.isPressed)
        .padding(DemoWindowOverlayGeometry.badgeShadowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Claude's multi-hue edge, in `DemoGlow`'s hues, fine enough for the badge. It
/// turns once every four seconds while BetterMeets drives the window, and holds
/// still while it waits, and with Reduce Motion.
private struct DemoWindowBadgeRing: View {
    var turns: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let turning = turns && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !turning)) { context in
            let degrees =
                turning ? (context.date.timeIntervalSinceReferenceDate * 90).truncatingRemainder(dividingBy: 360) : 0
            Capsule(style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: DemoGlow.colors, center: .center, angle: .degrees(degrees)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// The demo's arrow and click ripples over the window itself, drawn as the stage draws them.
private struct DemoWindowCursorView: View {
    let chrome: DemoWindowOverlayChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let margin = DemoWindowOverlayGeometry.cursorMargin
            let window = CGSize(
                width: max(geometry.size.width - margin * 2, 0), height: max(geometry.size.height - margin * 2, 0))
            ZStack(alignment: .topLeading) {
                if let pointer = chrome.pointer {
                    DemoPointerLayer(pointer: pointer)
                        .padding(margin)
                        .transition(.opacity)
                }
                ForEach(chrome.ripples) { ripple in
                    ClickRippleGlyph(presentation: ripple, reducesMotion: reduceMotion)
                        .position(DemoWindowOverlayGeometry.localPoint(ripple.location, windowSize: window))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
