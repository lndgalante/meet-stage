import ApplicationServices
import CoreGraphics
import Foundation

/// Performs a Demo Mode click as a *visible* pointer movement so the audience
/// sees the cursor glide to the control and the source app reacts to a genuine
/// event (its own hover, press, and any click ripple fire normally).
///
/// This is the one place BetterMeets deliberately synthesizes input into the
/// source application, gated on Accessibility trust. Everything else in the app
/// remains observation-only. See ARCHITECTURE.md.
enum DemoActionExecutor {
    /// Number of intermediate move events during the glide.
    static let glideSteps = 24
    /// Delay between glide steps.
    static let stepDelay = Duration.milliseconds(7)

    /// Whether the app may post synthesized events. Accessibility trust grants
    /// both AX reading and event posting under one user-facing toggle.
    static var canSynthesizeInput: Bool {
        AXIsProcessTrusted()
    }

    /// Whether `point` (global Quartz points) lies on some active display, so a
    /// posted event lands where intended rather than being clamped to an edge.
    static func isOnActiveDisplay(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        let status = CGGetDisplaysWithPoint(point, 0, nil, &count)
        return status == .success && count > 0
    }

    /// A validity check re-run at each actuation boundary: it must still be the
    /// same live, focused source window before a real event is posted, so a
    /// mid-glide focus change never lands input in the wrong app.
    typealias ValidityCheck = @Sendable () async -> Bool

    /// Glides the system cursor to `target` (global Quartz points) and clicks.
    /// No-op when Accessibility trust is missing. The glide honors cancellation,
    /// and `isStillValid` is re-checked immediately before the press so a focus
    /// change during the glide aborts before any button-down is posted; once the
    /// button is pressed the matching release always posts (never stuck).
    @discardableResult
    static func performClick(
        at target: CGPoint,
        isStillValid: ValidityCheck = { true }
    ) async -> Bool {
        guard canSynthesizeInput else {
            AppLog.demoMode.notice("Skipped Demo Mode click: Accessibility not trusted")
            return false
        }

        let start = CGEvent(source: nil)?.location ?? target
        for step in 1...glideSteps {
            if Task.isCancelled { return false }
            let progress = Double(step) / Double(glideSteps)
            let eased = 0.5 - 0.5 * cos(progress * .pi)
            let point = CGPoint(
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased
            )
            postMouseEvent(.mouseMoved, at: point)
            do {
                try await Task.sleep(for: stepDelay)
            } catch {
                return false
            }
        }
        if Task.isCancelled { return false }
        guard await isStillValid() else {
            AppLog.demoMode.notice("Aborted Demo Mode click: window/focus changed mid-glide")
            return false
        }

        postMouseEvent(.leftMouseDown, at: target, clickState: 1)
        try? await Task.sleep(for: .milliseconds(24))
        postMouseEvent(.leftMouseUp, at: target, clickState: 1)
        return true
    }

    /// Delay between typed characters, so entry looks natural and reliably lands.
    static let typeStepDelay = Duration.milliseconds(28)

    /// Retains the exact editable element that gained focus after the visible
    /// click. AX can vend a new wrapper on each read, so production identity uses
    /// Core Foundation equality rather than Swift object identity. The testing
    /// case keeps the security-critical loop independently testable without AX
    /// permission or real keyboard events.
    final class EditableFocusToken: @unchecked Sendable {
        private enum Storage {
            case accessibility(AXUIElement)
            case testing(Int)
        }

        private let storage: Storage

        fileprivate init(element: AXUIElement) {
            storage = .accessibility(element)
        }

        static func testing(_ identifier: Int) -> EditableFocusToken {
            EditableFocusToken(testIdentifier: identifier)
        }

        private init(testIdentifier: Int) {
            storage = .testing(testIdentifier)
        }

        func refersToSameElement(as other: EditableFocusToken) -> Bool {
            switch (storage, other.storage) {
            case let (.accessibility(first), .accessibility(second)):
                CFEqual(first, second)
            case let (.testing(first), .testing(second)):
                first == second
            default:
                false
            }
        }
    }

    typealias FocusedElementResolver = @Sendable (pid_t) -> EditableFocusToken?
    typealias CharacterPoster = @Sendable (Character) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Focuses the field at `target` (a visible click) and types `text` into it as
    /// synthesized Unicode keystrokes. No-op without Accessibility trust. Verifies
    /// an editable field actually gained focus before typing (so letters never
    /// become app shortcuts on a non-field), then re-checks both the source and
    /// exact focused field before every character.
    static func performType(
        _ text: String,
        at target: CGPoint,
        pid: pid_t,
        isStillValid: ValidityCheck = { true }
    ) async {
        guard canSynthesizeInput else {
            AppLog.demoMode.notice("Skipped Demo Mode type: Accessibility not trusted")
            return
        }
        guard await performClick(at: target, isStillValid: isStillValid) else { return }
        if Task.isCancelled { return }
        do {
            try await Task.sleep(for: .milliseconds(160))  // let focus settle
        } catch {
            return
        }

        guard await isStillValid() else { return }
        guard let focusedElement = focusedEditableElement(pid: pid) else {
            AppLog.demoMode.notice("Skipped Demo Mode type: focused element is not a text field")
            return
        }

        await typeCharacters(
            text,
            pid: pid,
            expectedFocus: focusedElement,
            isStillValid: isStillValid
        )
    }

    /// The focused editable element, retained so the typing loop can verify that
    /// focus never moved—even to another control in the same source window.
    private static func focusedEditableElement(pid: pid_t) -> EditableFocusToken? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                app,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success,
            let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        let focusedElement = unsafeDowncast(element, to: AXUIElement.self)

        var role: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focusedElement,
                kAXRoleAttribute as CFString,
                &role
            ) == .success,
            let roleString = role as? String
        else { return nil }

        guard
            [
                "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"
            ].contains(roleString)
        else { return nil }
        return EditableFocusToken(element: focusedElement)
    }

    /// Testable security boundary used by `performType`. Dependencies are
    /// injectable so focus drift and cancellation can be verified without
    /// posting real events.
    static func typeCharacters(
        _ text: String,
        pid: pid_t,
        expectedFocus: EditableFocusToken,
        isStillValid: ValidityCheck,
        resolveFocusedElement: FocusedElementResolver = focusedEditableElement(pid:),
        post: CharacterPoster = postCharacter,
        sleep: Sleeper = { try await Task.sleep(for: $0) }
    ) async {
        for character in text {
            if Task.isCancelled { return }
            guard await isStillValid() else {
                AppLog.demoMode.notice("Aborted Demo Mode type: window/focus changed")
                return
            }
            guard
                let currentFocus = resolveFocusedElement(pid),
                expectedFocus.refersToSameElement(as: currentFocus)
            else {
                AppLog.demoMode.notice("Aborted Demo Mode type: focused field changed")
                return
            }

            post(character)
            do {
                try await sleep(typeStepDelay)
            } catch {
                return
            }
        }
    }

    private static func postCharacter(_ character: Character) {
        var utf16 = Array(String(character).utf16)
        let count = utf16.count
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: count, unicodeString: &utf16)
            up.post(tap: .cghidEventTap)
        }
    }

    private static func postMouseEvent(
        _ type: CGEventType,
        at point: CGPoint,
        clickState: Int64 = 0
    ) {
        guard
            let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else { return }
        if clickState > 0 {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        event.post(tap: .cghidEventTap)
    }
}
