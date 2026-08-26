import AppKit
import Testing
@testable import MeetStage

@Suite("Presentation effects")
struct PresentationEffectsTests {
    @Test("Observes clicks delivered to the annotation panel")
    @MainActor
    func observesLocalAnnotationClicks() {
        let monitor = GlobalMouseClickMonitor(mouseClicks: { _ in })

        monitor.start()
        #expect(monitor.observesLocalApplicationEvents)

        monitor.stop()
        #expect(!monitor.observesLocalApplicationEvents)
    }

    @Test("A pointer burst delivers only its freshest location")
    @MainActor
    func coalescesPointerBursts() async {
        let delivery = LatestMainActorDelivery<CGPoint>()
        let recorder = PointerDeliveryRecorder()

        delivery.submit(CGPoint(x: 10, y: 10)) { recorder.values.append($0) }
        delivery.submit(CGPoint(x: 20, y: 20)) { recorder.values.append($0) }
        delivery.submit(CGPoint(x: 30, y: 30)) { recorder.values.append($0) }
        await Task.yield()
        await Task.yield()

        #expect(recorder.values == [CGPoint(x: 30, y: 30)])
    }

    @Test("Stage polish, drawing, spotlight, and click highlights remain independently armed")
    @MainActor
    func armsCombinedPresentationActions() throws {
        let suiteName = "CombinedPresentationActionsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = CaptureManager(defaults: defaults)

        manager.toggleAutoPresentation()
        manager.toggleAnnotations()
        manager.toggleSpotlight()
        manager.toggleMouseClickHighlighting()

        #expect(manager.autoPresentationEnabled)
        #expect(manager.annotationsEnabled)
        #expect(manager.spotlightEnabled)
        #expect(manager.highlightsMouseClicks)
        #expect(manager.presentationPointerMonitor == nil)
    }

    @Test("Maps global clicks into the selected window")
    func normalizesClickLocation() {
        let location = WindowCoordinateGeometry.normalizedPoint(
            inside: CGPoint(x: 250, y: 250),
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200)
        )

        #expect(location == NormalizedWindowPoint(x: 0.5, y: 0.25))
    }

    @Test("Rejects clicks outside the selected window")
    func rejectsOutOfBoundsClicks() {
        let location = WindowCoordinateGeometry.normalizedPoint(
            inside: CGPoint(x: 99, y: 250),
            sourceFrame: CGRect(x: 100, y: 200, width: 300, height: 200)
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

@MainActor
private final class PointerDeliveryRecorder {
    var values: [CGPoint] = []
}
