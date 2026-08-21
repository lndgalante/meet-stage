import AppKit
import Testing
@testable import MeetStage

@Suite("Presentation effects")
struct PresentationEffectsTests {
    @Test("Observes clicks delivered to the annotation panel")
    @MainActor
    func observesLocalAnnotationClicks() {
        let monitor = GlobalMouseClickMonitor { _ in }

        monitor.start()
        #expect(monitor.observesLocalApplicationEvents)

        monitor.stop()
        #expect(!monitor.observesLocalApplicationEvents)
    }

    @Test("Only presents enabled effects while the selected source is focused")
    func gatesEffectsBySelectedSourceFocus() {
        #expect(
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: true,
                selectedSourceIsFocused: true
            )
        )
        #expect(
            !PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: true,
                selectedSourceIsFocused: false
            )
        )
        #expect(
            !PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: false,
                selectedSourceIsFocused: true
            )
        )
    }

    @Test("Maps global clicks into the selected window")
    func normalizesClickLocation() {
        let location = ClickPresentationGeometry.normalizedLocation(
            for: CGPoint(x: 250, y: 250),
            in: CGRect(x: 100, y: 200, width: 300, height: 200)
        )

        #expect(location == NormalizedWindowPoint(x: 0.5, y: 0.25))
    }

    @Test("Rejects clicks outside the selected window")
    func rejectsOutOfBoundsClicks() {
        let location = ClickPresentationGeometry.normalizedLocation(
            for: CGPoint(x: 99, y: 250),
            in: CGRect(x: 100, y: 200, width: 300, height: 200)
        )

        #expect(location == nil)
    }

    @Test("Aligns an AppKit overlay with the selected window")
    func resolvesSourceOverlayFrame() {
        let frame = ClickPresentationGeometry.appKitOverlayFrame(
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200),
            globalClickLocation: CGPoint(x: 250, y: 250),
            appKitClickLocation: CGPoint(x: 250, y: 650)
        )

        #expect(frame == CGRect(x: 100, y: 500, width: 300, height: 200))
    }

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
