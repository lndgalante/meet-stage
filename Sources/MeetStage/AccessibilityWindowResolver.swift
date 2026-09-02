import ApplicationServices
import CoreGraphics
import Foundation
import MeetStageCore

/// Maps a captured CG window frame to exactly one Accessibility window. Frame
/// matching is the only public bridge between these APIs, so ambiguity fails
/// closed instead of silently selecting the application's main window.
enum AccessibilityWindowResolver {
    static func uniqueMatchingWindow(
        in app: AXUIElement,
        sourceFrame: CGRect
    ) -> AXUIElement? {
        let windows = copyElements(app, attribute: kAXWindowsAttribute as CFString) ?? []
        let candidates = windows.map { window in
            frame(of: window).map(CaptureWindowBounds.init) ?? invalidBounds
        }
        guard
            let index = ExactWindowFocusPolicy.uniqueBestMatch(
                source: CaptureWindowBounds(sourceFrame),
                candidates: candidates
            )
        else { return nil }
        return windows[index]
    }

    static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        copyElement(app, attribute: kAXFocusedWindowAttribute as CFString)
    }

    static func windows(in app: AXUIElement) -> [AXUIElement] {
        copyElements(app, attribute: kAXWindowsAttribute as CFString) ?? []
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &positionValue
            ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let origin = point(positionValue),
            let size = size(sizeValue)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static let invalidBounds = CaptureWindowBounds(
        x: .nan,
        y: .nan,
        width: .nan,
        height: .nan
    )

    private static func copyElements(
        _ element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func copyElement(
        _ element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

extension CaptureWindowBounds {
    init(_ frame: CGRect) {
        self.init(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }
}
