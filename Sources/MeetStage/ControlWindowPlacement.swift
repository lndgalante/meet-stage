import AppKit
import ApplicationServices

enum ControlWindowPlacement {
    static let edgeGap: CGFloat = 12

    static func frame(
        size: CGSize,
        screen: CGRect,
        visibleScreen: CGRect,
        dock: CGRect?,
        savedOrigin: CGPoint? = nil
    ) -> CGRect {
        let bottomDock = dock.flatMap { frame -> CGRect? in
            guard frame.width > frame.height, frame.height > 1,
                frame.intersects(screen), abs(frame.minY - screen.minY) <= edgeGap * 2
            else { return nil }
            return frame.intersection(screen)
        }
        // visibleFrame excludes the whole Dock strip, including its empty side gaps.
        let bounds =
            bottomDock == nil
            ? visibleScreen
            : CGRect(
                x: visibleScreen.minX, y: screen.minY,
                width: visibleScreen.width, height: visibleScreen.maxY - screen.minY
            )
        if let savedOrigin {
            let saved = clamped(CGRect(origin: savedOrigin, size: size), to: bounds)
            if dock.map({ saved.intersects($0) }) != true { return saved }
        }
        if let dock = bottomDock {
            let gaps = [
                CGRect(x: dock.maxX, y: screen.minY, width: max(0, bounds.maxX - dock.maxX), height: dock.height),
                CGRect(x: bounds.minX, y: screen.minY, width: max(0, dock.minX - bounds.minX), height: dock.height)
            ]
            for gap in gaps where gap.width >= size.width + edgeGap * 2 {
                return clamped(
                    CGRect(
                        x: gap.midX - size.width / 2, y: dock.midY - size.height / 2,
                        width: size.width, height: size.height),
                    to: bounds
                )
            }
        }
        let bottom = max(visibleScreen.minY, bottomDock?.maxY ?? visibleScreen.minY)
        return clamped(
            CGRect(
                x: visibleScreen.maxX - size.width - edgeGap, y: bottom + edgeGap,
                width: size.width, height: size.height),
            to: visibleScreen
        )
    }

    static func savedOrigin(from frame: String?) -> CGPoint? {
        guard let frame else { return nil }
        let values = frame.split(separator: " ").prefix(4).compactMap { Double($0) }
        guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private static func clamped(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
            y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height)),
            width: frame.width, height: frame.height
        )
    }
}

@MainActor
enum DockFrameResolver {
    static func currentFrame() -> CGRect? {
        guard let primaryScreen = NSScreen.screens.first,
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }

        // Recent macOS versions report a full-screen Dock window; AX exposes its visible list.
        if AXIsProcessTrusted() {
            let app = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success {
                for child in value as? [AXUIElement] ?? [] {
                    var role: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                        role as? String == kAXListRole,
                        let frame = AccessibilityWindowResolver.frame(of: child), frame.width > 1, frame.height > 1
                    else { continue }
                    return SourceOverlayGeometry.appKitFrame(
                        forQuartzFrame: frame, primaryScreenFrame: primaryScreen.frame)
                }
            }
        }

        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[CFString: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == dock.processIdentifier,
                (window[kCGWindowLayer] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.dockWindow)),
                let bounds = window[kCGWindowBounds] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                min(frame.width, frame.height) > 1, max(frame.width, frame.height) > min(frame.width, frame.height) * 3,
                min(frame.width, frame.height) < 256
            else { continue }
            return SourceOverlayGeometry.appKitFrame(forQuartzFrame: frame, primaryScreenFrame: primaryScreen.frame)
        }
        return nil
    }
}
