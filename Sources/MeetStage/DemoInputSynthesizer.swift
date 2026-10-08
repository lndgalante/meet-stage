import AppKit
import Carbon
import CoreGraphics
import MeetStageCore

/// How fast the demo moves. Presenting is paced for an audience; scouting and
/// checking move as fast as the app reliably follows.
enum DemoPace: Sendable {
    case scout, verify, present

    var cursorTravel: Duration {
        self == .present ? .milliseconds(420) : .milliseconds(120)
    }

    func typingDelay(index: Int) -> Duration {
        guard self == .present else { return .milliseconds(12) }
        // A little variation reads as typing rather than pasting.
        return .milliseconds(38 + (index * 7919) % 18)
    }
}

/// Posts the demo's synthetic mouse and keyboard events.
///
/// Every event comes from a private event source, carries `eventTag`, and has
/// its modifier flags set explicitly, so the presenter's held keys never mix
/// in and BetterMeets' own input monitors can ignore it. Keyboard events are
/// posted to the source process, so a focus change can't redirect keystrokes
/// into another app such as the meeting.
@MainActor
final class DemoInputSynthesizer {
    nonisolated static let eventTag: Int64 = 0x424D_4445_4D4F

    private let eventSource = CGEventSource(stateID: .privateState)

    nonisolated static func isSynthetic(_ event: CGEvent?) -> Bool {
        guard let event else { return false }
        return event.getIntegerValueField(.eventSourceUserData) == eventTag
            || event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
    }

    // MARK: Pointer

    func moveCursor(to point: CGPoint, duration: Duration, check: () throws -> Void) async throws {
        let start = CGEvent(source: nil)?.location ?? point
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let milliseconds = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        let steps = reduceMotion ? 1 : max(1, Int(milliseconds / 12))
        for index in 1...steps {
            try Task.checkCancellation()
            try check()
            let progress = 0.5 - 0.5 * cos(Double(index) / Double(steps) * .pi)
            postMouse(
                .mouseMoved,
                at: CGPoint(x: start.x + (point.x - start.x) * progress, y: start.y + (point.y - start.y) * progress))
            if steps > 1 { try await Task.sleep(for: .milliseconds(12)) }
        }
    }

    /// Presses and releases the left button. `commit` runs, and may veto, right
    /// before the press, with nothing in between that could suspend.
    func click(at point: CGPoint, commit: () throws -> Void) async throws {
        try Task.checkCancellation()
        try commit()
        postMouse(.leftMouseDown, at: point)
        try? await Task.sleep(for: .milliseconds(40))
        postMouse(.leftMouseUp, at: point)
    }

    func scroll(at point: CGPoint, down: Bool, increments: Int, check: () throws -> Void) async throws {
        postMouse(.mouseMoved, at: point)
        for _ in 0..<increments {
            try Task.checkCancellation()
            try check()
            guard
                let event = CGEvent(
                    scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 1, wheel1: down ? -160 : 160,
                    wheel2: 0, wheel3: 0)
            else { return }
            tag(event)
            event.flags = []
            event.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard
            let event = CGEvent(
                mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        event.flags = []
        tag(event)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Keyboard

    /// Posts one key press to `pid`. The key-up is always sent, even when the
    /// surrounding task is cancelled.
    func press(keyCode: CGKeyCode, flags: CGEventFlags = [], unicode: String? = nil, to pid: pid_t) {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = flags
            if let unicode {
                let units = Array(unicode.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            tag(event)
        }
        down.postToPid(pid)
        up.postToPid(pid)
    }

    /// Types `text` character by character into the focused element of `pid`.
    /// `check` runs every few characters; when it throws, typing stops where it is.
    func type(_ text: String, to pid: pid_t, pace: DemoPace, check: () async throws -> Void) async throws {
        // A newline or tab would act as Return or Tab, so it never reaches the app as text.
        guard !DemoActionPolicy.containsControlCharacters(text) else { throw DemoError.typingFailed(text) }
        let restore = KeyLayout.selectASCIIInputSourceIfNeeded()
        defer { restore() }
        for (index, character) in text.enumerated() {
            if index % 8 == 0 {
                try Task.checkCancellation()
                try await check()
            }
            press(keyCode: 0, unicode: String(character), to: pid)
            try await Task.sleep(for: pace.typingDelay(index: index))
        }
    }

    func pressReturn(to pid: pid_t) {
        press(keyCode: CGKeyCode(kVK_Return), unicode: "\r", to: pid)
    }

    func press(_ key: DemoKey, to pid: pid_t) {
        let (code, flags): (Int, CGEventFlags) =
            switch key {
            case .escape: (kVK_Escape, [])
            case .tab: (kVK_Tab, [])
            case .shiftTab: (kVK_Tab, .maskShift)
            case .up: (kVK_UpArrow, [])
            case .down: (kVK_DownArrow, [])
            case .left: (kVK_LeftArrow, [])
            case .right: (kVK_RightArrow, [])
            case .pageUp: (kVK_PageUp, [])
            case .pageDown: (kVK_PageDown, [])
            }
        press(keyCode: CGKeyCode(code), flags: flags, to: pid)
    }

    /// ⌘L using whichever key types “l” in the current layout.
    func focusAddressBar(of pid: pid_t) -> Bool {
        guard let code = KeyLayout.keyCode(for: "l") else { return false }
        press(keyCode: code, flags: .maskCommand, to: pid)
        return true
    }

    private func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
    }

}

/// Keyboard-layout helpers. Text Input Sources must be used on the main thread.
@MainActor
enum KeyLayout {
    /// The virtual key that produces `character` together with ⌘ in the current
    /// layout, so ⌘L stays ⌘L on Dvorak, AZERTY or Dvorak–QWERTY ⌘. Non-Latin
    /// layouts fall back to the system's ASCII-capable layout.
    static func keyCode(for character: Character) -> CGKeyCode? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        for source in sources.compactMap({ $0 }) {
            if let code = keyCode(for: character, in: source) { return code }
        }
        return nil
    }

    private static func keyCode(for character: Character, in source: TISInputSource) -> CGKeyCode? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let commandState = UInt32((cmdKey >> 8) & 0xFF)
        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for modifiers in [commandState, 0] {
                for code in 0..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                    if status == noErr, length == 1,
                        String(utf16CodeUnits: characters, count: 1).lowercased() == String(character)
                    {
                        return CGKeyCode(code)
                    }
                }
            }
            return nil
        }
    }

    /// Switches away from an input method (Japanese, Chinese…) that would
    /// intercept typed characters. Returns a closure that restores it.
    static func selectASCIIInputSourceIfNeeded() -> () -> Void {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(current, kTISPropertyInputSourceIsASCIICapable)
        else { return {} }
        let isASCII = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue())
        guard !isASCII, let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
            return {}
        }
        TISSelectInputSource(ascii)
        return { TISSelectInputSource(current) }
    }
}
