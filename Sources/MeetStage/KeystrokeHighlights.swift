import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct KeystrokePresentation: Equatable, Identifiable, Sendable {
    static let duration = Duration.milliseconds(1_200)

    let id = UUID()
    let label: String
    let size: PresentationSize
    let appearance: KeystrokeAppearance
}

/// Owns the Accessibility-gated global keyboard monitor.
@MainActor
final class GlobalKeystrokeMonitor {
    typealias Handler = @MainActor (String) -> Void

    private let handler: Handler
    private let resources = KeystrokeMonitorResources()

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options =
            [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard resources.monitor == nil else { return }
        resources.monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat,
                let label = KeystrokeFormatter.label(for: event)
            else { return }

            Task { @MainActor [weak self] in
                self?.handler(label)
            }
        }
    }

    func stop() {
        guard let monitor = resources.monitor else { return }
        NSEvent.removeMonitor(monitor)
        resources.monitor = nil
    }
}

private final class KeystrokeMonitorResources: @unchecked Sendable {
    var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

enum KeystrokeFormatter {
    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_ANSI_KeypadClear): "Clear",
        UInt16(kVK_ANSI_KeypadEnter): "Enter",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_UpArrow): "↑"
    ]

    static func label(for event: NSEvent) -> String? {
        label(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func label(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        guard let key = keyLabel(keyCode: keyCode, characters: characters) else { return nil }

        var parts: [String] = []
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(key)
        return parts.joined(separator: " ")
    }

    private static func keyLabel(keyCode: UInt16, characters: String?) -> String? {
        if let specialKey = specialKeys[keyCode] {
            return specialKey
        }

        guard let characters, !characters.isEmpty else { return nil }
        let printable = characters.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        guard !printable.isEmpty else { return nil }
        return String(String.UnicodeScalarView(printable)).uppercased()
    }
}
