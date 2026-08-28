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

    /// Glides the system cursor to `target` (global Quartz points) and clicks.
    /// No-op when Accessibility trust is missing. The glide honors cancellation
    /// so a teardown mid-glide never lands a click, but once the button is
    /// pressed the matching release always posts so the button is never stuck.
    static func performClick(at target: CGPoint) async {
        guard canSynthesizeInput else {
            AppLog.demoMode.notice("Skipped Demo Mode click: Accessibility not trusted")
            return
        }

        let start = CGEvent(source: nil)?.location ?? target
        for step in 1...glideSteps {
            if Task.isCancelled { return }
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
                return
            }
        }
        if Task.isCancelled { return }

        postMouseEvent(.leftMouseDown, at: target, clickState: 1)
        try? await Task.sleep(for: .milliseconds(24))
        postMouseEvent(.leftMouseUp, at: target, clickState: 1)
    }

    /// Delay between typed characters, so entry looks natural and reliably lands.
    static let typeStepDelay = Duration.milliseconds(28)

    /// Focuses the field at `target` (a visible click) and types `text` into it as
    /// synthesized Unicode keystrokes. No-op without Accessibility trust.
    static func performType(_ text: String, at target: CGPoint) async {
        guard canSynthesizeInput else {
            AppLog.demoMode.notice("Skipped Demo Mode type: Accessibility not trusted")
            return
        }
        await performClick(at: target)
        if Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(140))  // let focus settle

        for character in text {
            if Task.isCancelled { return }
            postCharacter(character)
            try? await Task.sleep(for: typeStepDelay)
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
