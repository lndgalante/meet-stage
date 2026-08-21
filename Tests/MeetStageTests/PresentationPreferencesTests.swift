import Foundation
import Testing
@testable import MeetStage

@Suite("Presentation preferences")
struct PresentationPreferencesTests {
    @Test("Uses familiar defaults for presentation effects")
    @MainActor
    func usesDefaults() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        let manager = CaptureManager(defaults: fixture.defaults)

        #expect(manager.annotationColor == .orange)
        #expect(manager.clickHighlightColor == .orange)
        #expect(manager.clickHighlightSize == .medium)
        #expect(manager.keystrokeHighlightSize == .medium)
        #expect(manager.keystrokeAppearance == .dark)
    }

    @Test("Persists every presentation appearance setting")
    @MainActor
    func persistsAppearance() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        let manager = CaptureManager(defaults: fixture.defaults)
        manager.setAnnotationColor(.purple)
        manager.setClickHighlightColor(.green)
        manager.setClickHighlightSize(.large)
        manager.setKeystrokeHighlightSize(.small)
        manager.setKeystrokeAppearance(.light)

        let restoredManager = CaptureManager(defaults: fixture.defaults)
        #expect(restoredManager.annotationColor == .purple)
        #expect(restoredManager.annotations.inkColor == .purple)
        #expect(restoredManager.clickHighlightColor == .green)
        #expect(restoredManager.clickHighlightSize == .large)
        #expect(restoredManager.keystrokeHighlightSize == .small)
        #expect(restoredManager.keystrokeAppearance == .light)
    }

    @Test("Ignores unsupported persisted appearance values")
    @MainActor
    func rejectsUnsupportedValues() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        fixture.defaults.set("ultraviolet", forKey: "presentation.annotationColor")
        fixture.defaults.set("huge", forKey: "presentation.clickHighlightSize")
        fixture.defaults.set("transparent", forKey: "presentation.keystrokeAppearance")

        let manager = CaptureManager(defaults: fixture.defaults)

        #expect(manager.annotationColor == .orange)
        #expect(manager.clickHighlightSize == .medium)
        #expect(manager.keystrokeAppearance == .dark)
    }
}

private struct PreferencesFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "PresentationPreferencesTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func dispose() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
