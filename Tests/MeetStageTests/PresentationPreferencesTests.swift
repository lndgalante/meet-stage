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
        fixture.defaults.set(
            "ultraviolet",
            forKey: PresentationPreferencesStore.annotationColorKey
        )
        fixture.defaults.set(
            "huge",
            forKey: PresentationPreferencesStore.clickHighlightSizeKey
        )
        fixture.defaults.set(
            "transparent",
            forKey: PresentationPreferencesStore.keystrokeAppearanceKey
        )

        let manager = CaptureManager(defaults: fixture.defaults)

        #expect(manager.annotationColor == .orange)
        #expect(manager.clickHighlightSize == .medium)
        #expect(manager.keystrokeAppearance == .dark)
    }

    @Test("Normalizes drawing lifetime at the persistence boundary")
    func normalizesLifetime() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        fixture.store.annotationLifetimeSeconds = 9

        #expect(fixture.store.annotationLifetimeSeconds == 10)
        #expect(
            fixture.defaults.integer(
                forKey: PresentationPreferencesStore.annotationLifetimeSecondsKey
            ) == 10
        )
    }

    @Test("Keeps presentation feature flags independent")
    func persistsFeatureFlags() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        fixture.store.highlightsMouseClicks = true
        fixture.store.highlightsKeystrokes = false

        #expect(fixture.store.highlightsMouseClicks)
        #expect(!fixture.store.highlightsKeystrokes)
    }
}

private struct PreferencesFixture {
    let suiteName: String
    let defaults: UserDefaults

    var store: PresentationPreferencesStore {
        PresentationPreferencesStore(defaults: defaults)
    }

    init() throws {
        suiteName = "PresentationPreferencesTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func dispose() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
