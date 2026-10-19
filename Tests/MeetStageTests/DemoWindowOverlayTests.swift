import AppKit
import Testing

@testable import MeetStage

@Suite("Demo window overlay", .serialized)
struct DemoWindowOverlayTests {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // MARK: Geometry

    @Test("The badge sits over the window's traffic lights, inset from its top-left corner")
    func badgeCorner() throws {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let badge = try #require(
            DemoWindowOverlayGeometry.badgeRect(
                inWindow: window, width: DemoWindowOverlayGeometry.collapsedBadgeWidth))
        #expect(badge == CGRect(x: 108, y: 206, width: 32, height: 22))
    }

    @Test("The badge never grows past the window, and hides when even its glyph doesn't fit")
    func badgeFitsWindow() {
        let window = CGRect(x: 0, y: 0, width: 200, height: 300)
        #expect(DemoWindowOverlayGeometry.badgeRect(inWindow: window, width: 500)?.width == 184)
        #expect(DemoWindowOverlayGeometry.badgeRect(inWindow: window, width: 4)?.width == 32)
        #expect(DemoWindowOverlayGeometry.maximumBadgeWidth(inWindow: window) == 184)
        #expect(
            DemoWindowOverlayGeometry.badgeRect(inWindow: CGRect(x: 0, y: 0, width: 47, height: 300), width: 32) == nil)
        #expect(
            DemoWindowOverlayGeometry.badgeRect(inWindow: CGRect(x: 0, y: 0, width: 48, height: 300), width: 32) != nil)
        #expect(
            DemoWindowOverlayGeometry.badgeRect(inWindow: CGRect(x: 0, y: 0, width: 200, height: 33), width: 32) == nil)
    }

    @Test("The capsule is the glyph alone, or the glyph and its label")
    func badgeWidths() {
        #expect(DemoWindowOverlayGeometry.badgeWidth(labelWidth: nil) == 32)
        #expect(DemoWindowOverlayGeometry.badgeWidth(labelWidth: 0) == 32)
        #expect(DemoWindowOverlayGeometry.badgeWidth(labelWidth: 100) == 137)
    }

    @Test("Normalized points land in the window's part of the arrow's panel, clamped to the window")
    func cursorPoints() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        #expect(
            DemoWindowOverlayGeometry.cursorRect(inWindow: window) == CGRect(x: 60, y: 160, width: 880, height: 680))
        let size = window.size
        #expect(
            DemoWindowOverlayGeometry.localPoint(NormalizedWindowPoint(x: 0, y: 0), windowSize: size)
                == CGPoint(x: 40, y: 40))
        #expect(
            DemoWindowOverlayGeometry.localPoint(NormalizedWindowPoint(x: 1, y: 1), windowSize: size)
                == CGPoint(x: 840, y: 640))
        #expect(
            DemoWindowOverlayGeometry.localPoint(NormalizedWindowPoint(x: 0.5, y: 0.25), windowSize: size)
                == CGPoint(x: 440, y: 190))
        #expect(
            DemoWindowOverlayGeometry.clamped(NormalizedWindowPoint(x: -0.2, y: 1.4))
                == NormalizedWindowPoint(x: 0, y: 1))
        #expect(
            DemoWindowOverlayGeometry.clamped(NormalizedWindowPoint(x: 0.3, y: 0.7))
                == NormalizedWindowPoint(x: 0.3, y: 0.7))
        #expect(DemoWindowOverlayGeometry.clamped(NormalizedWindowPoint(x: .nan, y: 0.5)) == nil)
        #expect(DemoWindowOverlayGeometry.clamped(NormalizedWindowPoint(x: 0.5, y: .infinity)) == nil)
    }

    @Test("Panel frames convert from Quartz to AppKit against the primary display, on every display")
    func appKitFrames() throws {
        let onPrimary = DemoWindowOverlayFrames.make(
            window: CGRect(x: 100, y: 50, width: 800, height: 600), badgeWidth: 32, primaryScreenFrame: primary)
        #expect(onPrimary.cursor == CGRect(x: 60, y: 210, width: 880, height: 680))
        let badge = try #require(onPrimary.badge)
        #expect(badge == CGRect(x: 105, y: 819, width: 38, height: 28))
        // The capsule's top is 6 points under the window's, which is 850 in AppKit.
        let capsuleTop = badge.maxY - DemoWindowOverlayGeometry.badgeShadowPadding
        #expect(capsuleTop == CGFloat(844))

        let above = DemoWindowOverlayFrames.make(
            window: CGRect(x: 200, y: -700, width: 600, height: 400), badgeWidth: 32, primaryScreenFrame: primary)
        #expect(above.cursor == CGRect(x: 160, y: 1160, width: 680, height: 480))
        #expect(above.badge == CGRect(x: 205, y: 1569, width: 38, height: 28))

        let left = DemoWindowOverlayFrames.make(
            window: CGRect(x: -1200, y: 100, width: 500, height: 300), badgeWidth: 120, primaryScreenFrame: primary)
        #expect(left.cursor == CGRect(x: -1240, y: 460, width: 580, height: 380))
        #expect(left.badge == CGRect(x: -1195, y: 769, width: 126, height: 28))

        let tiny = DemoWindowOverlayFrames.make(
            window: CGRect(x: 0, y: 0, width: 40, height: 40), badgeWidth: 32, primaryScreenFrame: primary)
        #expect(tiny.badge == nil)
    }

    // MARK: Window list

    private func entry(
        _ number: CGWindowID, pid: pid_t, layer: Int = 0, frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300),
        onScreen: Bool? = true, alpha: Double? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
        if let onScreen { info[kCGWindowIsOnscreen as String] = NSNumber(value: onScreen) }
        if let alpha { info[kCGWindowAlpha as String] = NSNumber(value: alpha) }
        return info
    }

    @Test("Window list entries read as the window server writes them")
    func parsesWindowInfo() throws {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        let info = try #require(DemoListedWindow(entry(7, pid: 42, layer: 3, frame: frame, alpha: 0.5)))
        #expect(info == DemoListedWindow(number: 7, pid: 42, layer: 3, frame: frame, isOnScreen: true, alpha: 0.5))
        // The window server leaves out the on-screen key for windows that aren't, and alpha for opaque ones.
        let offScreen = try #require(DemoListedWindow(entry(7, pid: 42, onScreen: nil)))
        #expect(!offScreen.isOnScreen)
        #expect(offScreen.alpha == 1)
        var noBounds = entry(7, pid: 42)
        noBounds[kCGWindowBounds as String] = nil
        #expect(DemoListedWindow(noBounds) == nil)
        var noOwner = entry(7, pid: 42)
        noOwner[kCGWindowOwnerPID as String] = nil
        #expect(DemoListedWindow(noOwner) == nil)
    }

    @Test("The overlay shows only on the app's own window while it's on screen and drawn")
    func visibility() throws {
        let target: CGWindowID = 10
        func visible(_ entries: [[String: Any]]) -> DemoListedWindow? {
            DemoWindowStacking.visibleTarget(in: entries.compactMap(DemoListedWindow.init), id: target, pid: 42)
        }
        let frame = CGRect(x: 100, y: 80, width: 640, height: 480)
        #expect(visible([entry(3, pid: 9), entry(target, pid: 42, frame: frame)])?.frame == frame)
        // Closed.
        #expect(visible([entry(3, pid: 9)]) == nil)
        // The number now belongs to another app's window.
        #expect(visible([entry(target, pid: 9)]) == nil)
        // Minimized, hidden with its app, or on another Space.
        #expect(visible([entry(target, pid: 42, onScreen: false)]) == nil)
        #expect(visible([entry(target, pid: 42, onScreen: nil)]) == nil)
        // On screen but not drawn.
        #expect(visible([entry(target, pid: 42, alpha: 0)]) == nil)
        #expect(visible([entry(target, pid: 42, frame: CGRect(x: 0, y: 0, width: 0, height: 300))]) == nil)
    }

    private func listed(
        _ number: CGWindowID, pid: pid_t = 9, layer: Int = 0,
        frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300)
    ) -> DemoListedWindow {
        DemoListedWindow(number: number, pid: pid, layer: layer, frame: frame)
    }

    @Test("The arrow and badge belong right above the window, under anything else in front of it")
    func ordering() {
        let target = listed(10, pid: 42)
        let cursor = listed(100, pid: ownPID)
        let badge = listed(101, pid: ownPID)
        let overlays: [CGWindowID] = [100, 101]
        func ordered(_ windows: [DemoListedWindow]) -> Bool {
            let anchor = DemoWindowStacking.anchor(in: windows, target: target, overlays: overlays)
            #expect(anchor == target.number)
            return DemoWindowStacking.isOrdered(overlays, above: anchor, in: windows, target: target)
        }
        // Front to back: the menu bar, another app's window covering the overlay, then the overlay on the source.
        #expect(ordered([listed(1, layer: 24), listed(2), badge, cursor, target]))
        #expect(!ordered([badge, cursor, listed(2), target]))
        #expect(!ordered([listed(2), target]))
        #expect(!ordered([cursor, badge, target]))
        // Windows on other levels, like the teleprompter, never come between.
        #expect(ordered([badge, listed(3, pid: ownPID, layer: 27), cursor, target]))
        #expect(DemoWindowStacking.isOrdered([], above: 10, in: [target], target: target))
        #expect(DemoWindowStacking.isOrdered([100], above: 10, in: [cursor, target], target: target))
    }

    @Test("A sheet or other window the app stacks on its window carries the overlay too")
    func appWindowsAbove() {
        let target = listed(10, pid: 42)
        let sheet = listed(11, pid: 42, frame: CGRect(x: 50, y: 28, width: 300, height: 180))
        let cursor = listed(100, pid: ownPID)
        let badge = listed(101, pid: ownPID)
        let overlays: [CGWindowID] = [100, 101]

        let above = [badge, cursor, sheet, target]
        #expect(DemoWindowStacking.anchor(in: above, target: target, overlays: overlays) == 11)
        #expect(DemoWindowStacking.isOrdered(overlays, above: 11, in: above, target: target))

        let below = [sheet, badge, cursor, target]
        #expect(DemoWindowStacking.anchor(in: below, target: target, overlays: overlays) == 11)
        #expect(!DemoWindowStacking.isOrdered(overlays, above: 11, in: below, target: target))
        #expect(!DemoWindowStacking.isOrdered(overlays, above: 12, in: below, target: target))

        // An app window above someone else's isn't stacked on the source.
        let covered = [listed(12, pid: 42, frame: sheet.frame), listed(2), target]
        #expect(DemoWindowStacking.anchor(in: covered, target: target, overlays: overlays) == 10)
    }

    @Test("Another window of the same app in front, like the person's own, covers the overlay")
    func sameAppWindowsInFront() {
        let target = listed(10, pid: 42)
        let cursor = listed(100, pid: ownPID)
        let badge = listed(101, pid: ownPID)
        let overlays: [CGWindowID] = [100, 101]
        // Both maximized to the same frame, or one larger, or one off to the side.
        let same = listed(12, pid: 42)
        let larger = listed(13, pid: 42, frame: CGRect(x: -20, y: -20, width: 600, height: 500))
        let beside = listed(14, pid: 42, frame: CGRect(x: 300, y: 100, width: 200, height: 150))
        for person in [same, larger, beside] {
            let windows = [person, badge, cursor, target]
            #expect(DemoWindowStacking.anchor(in: windows, target: target, overlays: overlays) == 10)
            #expect(DemoWindowStacking.isOrdered(overlays, above: 10, in: windows, target: target))
        }
        // A sheet on the source under the person's window still carries the overlay.
        let sheet = listed(11, pid: 42, frame: CGRect(x: 1, y: 28, width: 398, height: 200))
        let windows = [same, badge, cursor, sheet, target]
        #expect(DemoWindowStacking.anchor(in: windows, target: target, overlays: overlays) == 11)
        #expect(DemoWindowStacking.isAttached(sheet, to: target))
        #expect(!DemoWindowStacking.isAttached(same, to: target))
    }

    // MARK: Panels

    @Test("Both panels sit on the window's level, never take focus, and stay out of Mission Control")
    @MainActor
    func panelConfiguration() throws {
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: 0, pid: 1)
        let cursor = try #require(overlay.cursorPanel)
        let badge = try #require(overlay.badgePanel)
        for panel in [cursor, badge] {
            #expect(panel.styleMask.contains(.nonactivatingPanel))
            #expect(!panel.styleMask.contains(.titled))
            #expect(!panel.canBecomeKey)
            #expect(!panel.canBecomeMain)
            #expect(panel.level == .normal)
            #expect(!panel.isFloatingPanel)
            #expect(!panel.hidesOnDeactivate)
            #expect(!panel.canHide)
            #expect(!panel.isOpaque)
            #expect(panel.windowNumber > 0)
            for behavior in [
                NSWindow.CollectionBehavior.ignoresCycle, .transient, .canJoinAllSpaces, .fullScreenAuxiliary
            ] {
                #expect(panel.collectionBehavior.contains(behavior))
            }
        }
        #expect(cursor.ignoresMouseEvents)
        #expect(!badge.ignoresMouseEvents)
        #expect(badge.allowsToolTipsWhenApplicationIsInactive)
        #expect(cursor.accessibilityLabel() == "BetterMeets pointer")
        #expect(badge.accessibilityLabel() == "BetterMeets status")

        let control = try #require(badge.contentView as? DemoWindowBadgeControl)
        #expect(control.accessibilityRole() == .button)
        #expect(control.accessibilityLabel() == "BetterMeets is building")
        #expect(control.acceptsFirstMouse(for: nil))
        #expect(control.trackingAreas.contains { $0.options.contains([.activeAlways, .mouseEnteredAndExited]) })

        // There's no window 0, so nothing shows.
        #expect(!overlay.isShown)
        overlay.detach()
        #expect(overlay.cursorPanel == nil)
        #expect(overlay.badgePanel == nil)
        #expect(overlay.windowID == nil)
    }

    @Test("The badge says what BetterMeets is doing, and when it's waiting for a pause")
    @MainActor
    func badgeStates() throws {
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: 0, pid: 1)
        let control = try #require(overlay.badgePanel?.contentView as? DemoWindowBadgeControl)
        #expect(overlay.chrome.symbol == "cursorarrow.motionlines")

        overlay.activity = .testing
        #expect(control.accessibilityLabel() == "BetterMeets is testing")
        overlay.activity = .returning
        #expect(control.accessibilityLabel() == "BetterMeets is going back to the start")

        overlay.setWaiting(true)
        #expect(control.accessibilityLabel() == "Waiting for a pause")
        #expect(overlay.chrome.symbol == "hourglass")
        #expect(control.toolTip == overlay.chrome.help)
        #expect(control.accessibilityHelp()?.contains("waits until you stop typing") == true)

        overlay.setWaiting(false)
        #expect(control.accessibilityLabel() == "BetterMeets is going back to the start")
        #expect(control.toolTip?.contains("keep working") == true)

        var clicks = 0
        overlay.onBadgeClick = { clicks += 1 }
        #expect(control.accessibilityPerformPress())
        #expect(clicks == 1)
    }

    @Test("The arrow stays in the window and hides with nil; ripples clear themselves")
    @MainActor
    func pointerAndRipples() async throws {
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: 0, pid: 1)
        overlay.movePointer(to: NormalizedWindowPoint(x: 1.4, y: -0.1), travel: 0.12)
        #expect(overlay.chrome.pointer == DemoPointer(location: NormalizedWindowPoint(x: 1, y: 0), travel: 0.12))
        overlay.movePointer(to: NormalizedWindowPoint(x: .nan, y: 0), travel: 0.12)
        #expect(overlay.chrome.pointer == nil)

        overlay.ripple(at: NormalizedWindowPoint(x: 0.5, y: 0.5), color: .blue, size: .large)
        let ripple = try #require(overlay.chrome.ripples.first)
        #expect(ripple.color == .blue)
        #expect(ripple.size == .large)
        try await Task.sleep(for: ClickPresentation.duration + .milliseconds(200))
        #expect(overlay.chrome.ripples.isEmpty)

        overlay.movePointer(to: NormalizedWindowPoint(x: 0.2, y: 0.3), travel: 0.42)
        overlay.ripple(at: NormalizedWindowPoint(x: 0.2, y: 0.3))
        overlay.detach()
        #expect(overlay.chrome.pointer == nil)
        #expect(overlay.chrome.ripples.isEmpty)
    }

    // MARK: A real window

    /// A window of the test process itself to put the overlay on, so no other app is
    /// touched, once the window server lists it.
    @MainActor
    private func makeWindow() async throws -> (NSWindow, CGRect) {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(
            contentRect: CGRect(x: screen.frame.minX + 160, y: screen.frame.minY + 160, width: 420, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.orderFrontRegardless()
        #expect(try await eventually { self.frame(of: window) != nil })
        return (window, try #require(frame(of: window)))
    }

    @MainActor
    private func frame(of window: NSWindow) -> CGRect? {
        WindowFrameResolver.currentSnapshot(for: CGWindowID(window.windowNumber))?.frame
    }

    /// Waits for the window server, which lists AppKit's changes a moment later.
    @MainActor
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @MainActor
    private func isInFront(of window: NSWindow, _ panel: NSWindow) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let numbers = list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        guard let panelIndex = numbers.firstIndex(of: panel.windowNumber),
            let windowIndex = numbers.firstIndex(of: window.windowNumber)
        else { return false }
        return panelIndex < windowIndex
    }

    @Test("The overlay follows its window, sits just above it, and hides when the window goes")
    @MainActor
    func followsWindow() async throws {
        let (window, frame) = try await makeWindow()
        defer { window.close() }
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: CGWindowID(window.windowNumber), pid: ownPID)
        let cursor = try #require(overlay.cursorPanel)
        let badge = try #require(overlay.badgePanel)
        let primary = try #require(NSScreen.screens.first).frame
        func frames(_ window: CGRect) -> DemoWindowOverlayFrames {
            DemoWindowOverlayFrames.make(
                window: window, badgeWidth: DemoWindowOverlayGeometry.collapsedBadgeWidth,
                primaryScreenFrame: primary)
        }

        #expect(overlay.isShown)
        #expect(badge.isVisible)
        #expect(cursor.frame == frames(frame).cursor)
        #expect(badge.frame == frames(frame).badge)
        #expect(try await eventually { isInFront(of: window, cursor) && isInFront(of: cursor, badge) })

        // The source coming forward, as when the person clicks it, covers the overlay until a refresh.
        window.orderFrontRegardless()
        #expect(
            try await eventually {
                overlay.refresh()
                return isInFront(of: window, cursor) && isInFront(of: cursor, badge)
            })

        window.setFrameOrigin(CGPoint(x: window.frame.minX + 40, y: window.frame.minY + 30))
        #expect(
            try await eventually {
                overlay.refresh()
                guard let moved = self.frame(of: window), moved.origin != frame.origin else { return false }
                return cursor.frame == frames(moved).cursor && badge.frame == frames(moved).badge
            })

        window.orderOut(nil)
        #expect(
            try await eventually {
                overlay.refresh()
                return !overlay.isShown && !badge.isVisible
            })

        window.orderFrontRegardless()
        #expect(
            try await eventually {
                overlay.refresh()
                return overlay.isShown
            })

        // The same number for another app isn't the source.
        overlay.attach(windowID: CGWindowID(window.windowNumber), pid: ownPID + 1)
        #expect(!overlay.isShown)
    }

    @Test("The badge takes a click without becoming key, and shows its label on hover")
    @MainActor
    func badgeInteraction() async throws {
        let (window, _) = try await makeWindow()
        defer { window.close() }
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: CGWindowID(window.windowNumber), pid: ownPID)
        let badge = try #require(overlay.badgePanel)
        #expect(badge.isVisible)
        var clicks = 0
        overlay.onBadgeClick = { clicks += 1 }

        // Delivered to the panel in this process, never posted to the system.
        let center = CGPoint(x: badge.frame.width / 2, y: badge.frame.height / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: center, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: badge.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            badge.sendEvent(event)
        }
        #expect(clicks == 1)
        #expect(!badge.isKeyWindow)
        #expect(!overlay.chrome.isPressed)

        let collapsed = badge.frame
        overlay.hoverBadge(true)
        #expect(overlay.chrome.isExpanded)
        #expect(badge.frame.width > collapsed.width + 40)
        let padding = DemoWindowOverlayGeometry.badgeShadowPadding
        #expect(overlay.chrome.capsuleWidth == badge.frame.width - padding * 2)
        // The panel grows away from the corner, so the glyph stays put.
        #expect(badge.frame.origin == collapsed.origin)

        overlay.setWaiting(true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(badge.frame.width > collapsed.width)
        #expect(overlay.chrome.capsuleWidth == badge.frame.width - padding * 2)

        overlay.hoverBadge(false)
        #expect(!overlay.chrome.isExpanded)
        try await Task.sleep(for: .milliseconds(300))
        #expect(badge.frame == collapsed)
    }

    @Test("A borrowed moment hides the overlay until it ends, and a detach clears it")
    @MainActor
    func suspends() async throws {
        let (window, _) = try await makeWindow()
        defer { window.close() }
        let overlay = DemoWindowOverlay()
        defer { overlay.detach() }
        overlay.attach(windowID: CGWindowID(window.windowNumber), pid: ownPID)
        #expect(overlay.isShown)

        overlay.setSuspended(true)
        #expect(!overlay.isShown)
        // Ticks run meanwhile, and keep it hidden.
        overlay.refresh()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!overlay.isShown)
        overlay.setSuspended(false)
        #expect(overlay.isShown)
        try await Task.sleep(for: .milliseconds(300))
        #expect(overlay.cursorPanel?.alphaValue == 1)

        // A detach while suspended leaves the next attach shown.
        overlay.setSuspended(true)
        overlay.detach()
        overlay.attach(windowID: CGWindowID(window.windowNumber), pid: ownPID)
        #expect(overlay.isShown)
    }
}
