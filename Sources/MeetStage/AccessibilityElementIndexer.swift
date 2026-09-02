import ApplicationServices
import CoreGraphics
import Foundation

/// Walks the Accessibility tree of the captured source window to build a list
/// of named, targetable controls for Demo Mode.
///
/// Every call is Mach IPC into the target application, so the walk is bounded
/// by depth, node, and result budgets and is meant to run off the main thread.
/// It stores no live `AXUIElement`; elements are described by their on-screen
/// frame so the index can be snapshotted and compared cheaply.
enum AccessibilityElementIndexer {
    static let maxDepth = 45
    static let nodeBudget = 6_000
    static let maxElements = 400
    static let messagingTimeout: Float = 0.75
    /// Hard wall-clock ceiling so one slow target app cannot pin the walk.
    static let walkDeadline = Duration.seconds(3)

    // CFArray is not Sendable, so the batched attribute list is rebuilt per
    // index pass and threaded through the walk rather than held statically.
    private static func batchedAttributes() -> CFArray {
        [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXValueAttribute,
            kAXPositionAttribute,
            kAXSizeAttribute,
            kAXChildrenAttribute,
            kAXEnabledAttribute
        ] as CFArray
    }

    private enum Attribute: Int {
        case role, subrole, title, description, value, position, size, children, enabled
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Builds an element list for the window identified by `sourceFrame` in the
    /// process `pid`. `sourceFrame` is the live Quartz frame (global, top-left)
    /// used both to select the window and to normalize element bounds.
    static func index(
        pid: pid_t,
        sourceFrame: CGRect,
        generation: Int
    ) -> DemoElementIndex {
        guard pid > 0, sourceFrame.width > 0, sourceFrame.height > 0 else {
            return DemoElementIndex(generation: generation, elements: [])
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Force web-rendered (Chromium/Electron) trees to materialize. Both keys
        // are literal strings with no public constant; setting either is
        // best-effort and safe to ignore on failure.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        guard
            let window = AccessibilityWindowResolver.uniqueMatchingWindow(
                in: app,
                sourceFrame: sourceFrame
            )
        else {
            return DemoElementIndex(generation: generation, elements: [])
        }

        var elements: [DemoElement] = []
        var budget = nodeBudget
        var nextID = 0
        let deadline = ContinuousClock.now.advanced(by: walkDeadline)
        walk(
            window,
            depth: 0,
            attributes: batchedAttributes(),
            sourceFrame: sourceFrame,
            deadline: deadline,
            budget: &budget,
            nextID: &nextID,
            into: &elements
        )
        return DemoElementIndex(generation: generation, elements: elements)
    }

    // MARK: - Tree walk

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        attributes: CFArray,
        sourceFrame: CGRect,
        deadline: ContinuousClock.Instant,
        budget: inout Int,
        nextID: inout Int,
        into elements: inout [DemoElement]
    ) {
        guard depth < maxDepth, budget > 0, elements.count < maxElements,
            !Task.isCancelled,
            ContinuousClock.now < deadline
        else { return }
        budget -= 1

        var values: CFArray?
        guard
            AXUIElementCopyMultipleAttributeValues(
                element,
                attributes,
                AXCopyMultipleAttributeOptions(),
                &values
            ) == .success,
            let slots = values as? [AnyObject],
            slots.count == 9
        else { return }

        let role = string(slots[Attribute.role.rawValue]) ?? ""
        let enabled = (slots[Attribute.enabled.rawValue] as? NSNumber)?.boolValue ?? true

        if enabled,
            let demoElement = makeElement(
                element,
                role: role,
                subrole: string(slots[Attribute.subrole.rawValue]),
                title: string(slots[Attribute.title.rawValue]),
                description: string(slots[Attribute.description.rawValue]),
                value: string(slots[Attribute.value.rawValue]),
                position: point(slots[Attribute.position.rawValue]),
                size: size(slots[Attribute.size.rawValue]),
                sourceFrame: sourceFrame,
                id: nextID
            )
        {
            nextID += 1
            elements.append(demoElement)
        }

        guard let children = slots[Attribute.children.rawValue] as? [AXUIElement] else { return }
        for child in children {
            guard elements.count < maxElements, budget > 0 else { return }
            walk(
                child,
                depth: depth + 1,
                attributes: attributes,
                sourceFrame: sourceFrame,
                deadline: deadline,
                budget: &budget,
                nextID: &nextID,
                into: &elements
            )
        }
    }

    private static func makeElement(
        _ element: AXUIElement,
        role: String,
        subrole: String?,
        title: String?,
        description: String?,
        value: String?,
        position: CGPoint?,
        size: CGSize?,
        sourceFrame: CGRect,
        id: Int
    ) -> DemoElement? {
        let demoRole = mapRole(role, subrole: subrole)
        let pressable = actionNames(element).contains(kAXPressAction) || demoRole == .field

        // Descriptive text is only useful as an OCR-like fallback; skip it here
        // unless it is a small, clearly interactive control.
        guard demoRole != .other || pressable else { return nil }

        let candidates = [title, description, value].compactMap { $0 }
        guard let label = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLabel.count <= 64 else { return nil }

        guard let position, let size, size.width > 0, size.height > 0 else { return nil }
        let screenFrame = CGRect(origin: position, size: size)

        guard let bounds = normalizedBounds(of: screenFrame, in: sourceFrame) else { return nil }

        return DemoElement(
            id: id,
            label: trimmedLabel,
            role: demoRole,
            source: .accessibility,
            normalizedBounds: bounds,
            screenFrame: screenFrame,
            pressable: pressable
        )
    }

    /// Normalizes a global element frame into source-window fractions, requiring
    /// the element center to fall inside the window.
    static func normalizedBounds(
        of elementFrame: CGRect,
        in sourceFrame: CGRect
    ) -> NormalizedAnnotationBounds? {
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return nil }
        let centerX = elementFrame.midX
        let centerY = elementFrame.midY
        guard centerX >= sourceFrame.minX, centerX <= sourceFrame.maxX,
            centerY >= sourceFrame.minY, centerY <= sourceFrame.maxY
        else { return nil }

        return NormalizedAnnotationBounds(
            minX: (elementFrame.minX - sourceFrame.minX) / sourceFrame.width,
            minY: (elementFrame.minY - sourceFrame.minY) / sourceFrame.height,
            width: elementFrame.width / sourceFrame.width,
            height: elementFrame.height / sourceFrame.height
        )
    }

    static func mapRole(_ role: String, subrole: String?) -> DemoElementRole {
        switch role {
        case "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
            "AXDisclosureTriangle", "AXToolbarButton":
            return subrole == "AXTabButton" ? .tab : .button
        case "AXLink":
            return .link
        case "AXTabButton":
            return .tab
        case "AXMenuItem", "AXMenuBarItem":
            return .menuItem
        case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField":
            return .field
        case "AXImage":
            return .image
        case "AXStaticText":
            return .text
        default:
            return .other
        }
    }

    // MARK: - AX value helpers

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
            let list = names as? [String]
        else { return [] }
        return list
    }

    private static func string(_ value: AnyObject?) -> String? {
        value as? String
    }

    private static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
