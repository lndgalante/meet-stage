import AppKit
import Testing
@testable import MeetStage

@Suite("Presentation effects")
struct PresentationEffectsTests {
    @Test("Formats shortcut modifiers in familiar macOS order")
    func formatsShortcutModifiers() {
        let label = KeystrokeFormatter.label(
            keyCode: 35,
            characters: "p",
            modifierFlags: [.command, .shift]
        )

        #expect(label == "⇧ ⌘ P")
    }

    @Test("Names navigation and whitespace keys")
    func namesSpecialKeys() {
        #expect(
            KeystrokeFormatter.label(
                keyCode: 123,
                characters: nil,
                modifierFlags: []
            ) == "←"
        )
        #expect(
            KeystrokeFormatter.label(
                keyCode: 49,
                characters: " ",
                modifierFlags: .option
            ) == "⌥ Space"
        )
    }

    @Test("Uppercases printable keys")
    func uppercasesPrintableKeys() {
        #expect(
            KeystrokeFormatter.label(
                keyCode: 0,
                characters: "a",
                modifierFlags: []
            ) == "A"
        )
    }

    @Test("Ignores unknown control characters")
    func ignoresUnknownControlCharacters() {
        #expect(
            KeystrokeFormatter.label(
                keyCode: 255,
                characters: "\u{1F}",
                modifierFlags: []
            ) == nil
        )
    }
}
