import Foundation
import Testing
@testable import MeetStage

@Suite("Shortcut preference persistence", .serialized)
struct ShortcutPreferencesStoreTests {
    @Test
    func testRoundTripsPinsAndExclusions() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let editor = identity(application: "Editor", title: "Document")
        let browser = identity(application: "Browser", title: "Dashboard")

        fixture.store.savePins([2: editor, 7: browser])
        fixture.store.saveExclusions([browser])

        #expect(fixture.store.loadPins() == [2: editor, 7: browser])
        #expect(fixture.store.loadExclusions() == [browser])
    }

    @Test
    func testLoadingPinsRejectsInvalidSlotsAndKeepsNewestDuplicate() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let oldIdentity = identity(application: "Editor", title: "Old")
        let newIdentity = identity(application: "Editor", title: "New")
        let encodedPins = [
            ShortcutPin(slot: 0, window: oldIdentity),
            ShortcutPin(slot: 3, window: oldIdentity),
            ShortcutPin(slot: 3, window: newIdentity),
            ShortcutPin(slot: 10, window: oldIdentity)
        ]
        fixture.defaults.set(
            try JSONEncoder().encode(encodedPins),
            forKey: ShortcutPreferencesStore.pinsKey
        )

        #expect(fixture.store.loadPins() == [3: newIdentity])
    }

    @Test
    func testCorruptPreferencesFallBackToEmptyCollections() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        fixture.defaults.set(Data("not-json".utf8), forKey: ShortcutPreferencesStore.pinsKey)
        fixture.defaults.set(Data("not-json".utf8), forKey: ShortcutPreferencesStore.exclusionsKey)

        #expect(fixture.store.loadPins().isEmpty)
        #expect(fixture.store.loadExclusions().isEmpty)
    }

    private func makeFixture() throws -> PreferencesFixture {
        let suiteName = "ShortcutPreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return PreferencesFixture(suiteName: suiteName, defaults: defaults)
    }

    private func identity(application: String, title: String) -> PinnedWindow {
        PinnedWindow(
            bundleIdentifier: "dev.example.\(application.lowercased())",
            applicationName: application,
            title: title
        )
    }
}

private struct PreferencesFixture {
    let suiteName: String
    let defaults: UserDefaults

    var store: ShortcutPreferencesStore {
        ShortcutPreferencesStore(defaults: defaults)
    }

    func clear() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
