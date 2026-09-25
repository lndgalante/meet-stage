import AppKit
import Foundation
import ImageIO
import Testing
@testable import MeetStage

@Suite("Presentation preferences")
struct PresentationPreferencesTests {
    @Test("Uses familiar defaults for presentation effects")
    @MainActor
    func usesDefaults() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        let manager = fixture.makeManager()

        #expect(manager.annotationColor == .orange)
        #expect(manager.spotlightSize == .medium)
        #expect(manager.spotlightOutsideOpacity == SpotlightAppearance.defaultOutsideOpacity)
        #expect(manager.clickHighlightColor == .orange)
        #expect(manager.clickHighlightSize == .medium)
        #expect(manager.keystrokeHighlightSize == .medium)
        #expect(manager.keystrokeAppearance == .dark)
        #expect(manager.stageFrameStyle == .midnight)
        #expect(manager.stageFramePadding == StageFrameAppearance.defaultPadding)
        #expect(manager.stageFrameCornerRadius == StageFrameAppearance.defaultCornerRadius)
        #expect(manager.stageFrameBlur == StageFrameAppearance.defaultBlur)
        #expect(manager.stageFrameShadow == StageFrameAppearance.defaultShadow)
        #expect(manager.autoZoomSize == .medium)
        #expect(manager.stageLogo == nil)
    }

    @Test("Persists every presentation appearance setting")
    @MainActor
    func persistsAppearance() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        let manager = fixture.makeManager()
        manager.setAnnotationColor(.purple)
        manager.setSpotlightSize(.large)
        manager.setSpotlightOutsideOpacity(0.55)
        manager.setClickHighlightColor(.green)
        manager.setClickHighlightSize(.large)
        manager.setKeystrokeHighlightSize(.small)
        manager.setKeystrokeAppearance(.light)
        manager.setStageFrameStyle(.sunset)
        manager.setStageFramePadding(0.11)
        manager.setStageFrameCornerRadius(28)
        manager.setStageFrameBlur(0.7)
        manager.setStageFrameShadow(0.4)
        manager.setAutoZoomSize(.large)
        let logoData = try #require(makeLogoData())
        #expect(manager.setStageLogoData(logoData))

        let restoredManager = fixture.makeManager()
        #expect(restoredManager.annotationColor == .purple)
        #expect(restoredManager.annotations.inkColor == .purple)
        #expect(restoredManager.spotlightSize == .large)
        #expect(restoredManager.spotlight.size == .large)
        #expect(restoredManager.spotlightOutsideOpacity == 0.55)
        #expect(restoredManager.spotlight.outsideOpacity == 0.55)
        #expect(restoredManager.clickHighlightColor == .green)
        #expect(restoredManager.clickHighlightSize == .large)
        #expect(restoredManager.keystrokeHighlightSize == .small)
        #expect(restoredManager.keystrokeAppearance == .light)
        #expect(restoredManager.stageFrameStyle == .sunset)
        #expect(restoredManager.stageFramePadding == 0.11)
        #expect(restoredManager.stageFrameCornerRadius == 28)
        #expect(restoredManager.stageFrameBlur == 0.7)
        #expect(restoredManager.stageFrameShadow == 0.4)
        #expect(restoredManager.autoZoomSize == .large)
        #expect(restoredManager.stageLogo != nil)
        #expect(fixture.store.legacyStageLogoData == nil)
        #expect(fixture.store.stageLogoStorageVersion == StageLogoStore.storageVersion)
        #expect(FileManager.default.fileExists(atPath: fixture.logoStore.fileURL.path))

        restoredManager.removeStageLogo()
        #expect(restoredManager.stageLogo == nil)
        #expect(fixture.store.stageLogoStorageVersion == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.logoStore.fileURL.path))
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
            "enormous",
            forKey: PresentationPreferencesStore.spotlightSizeKey
        )
        fixture.defaults.set(
            "transparent",
            forKey: PresentationPreferencesStore.keystrokeAppearanceKey
        )
        fixture.defaults.set(
            "rainbow",
            forKey: PresentationPreferencesStore.stageFrameStyleKey
        )

        let manager = fixture.makeManager()

        #expect(manager.annotationColor == .orange)
        #expect(manager.spotlightSize == .medium)
        #expect(manager.clickHighlightSize == .medium)
        #expect(manager.keystrokeAppearance == .dark)
        #expect(manager.stageFrameStyle == .midnight)
    }

    @Test("Clamps spotlight intensity at the persistence boundary")
    func clampsSpotlightIntensity() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        fixture.store.spotlightOutsideOpacity = 8

        #expect(
            fixture.store.spotlightOutsideOpacity
                == SpotlightAppearance.outsideOpacityRange.upperBound
        )
    }

    @Test("Replaces non-finite persisted appearance values with safe defaults")
    @MainActor
    func rejectsNonFiniteAppearanceValues() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        fixture.defaults.set(
            Double.nan,
            forKey: PresentationPreferencesStore.spotlightOutsideOpacityKey
        )
        fixture.defaults.set(
            Double.infinity,
            forKey: PresentationPreferencesStore.stageFramePaddingKey
        )
        fixture.defaults.set(
            -Double.infinity,
            forKey: PresentationPreferencesStore.stageFrameCornerRadiusKey
        )
        fixture.defaults.set(
            Double.nan,
            forKey: PresentationPreferencesStore.stageFrameBlurKey
        )
        fixture.defaults.set(
            Double.infinity,
            forKey: PresentationPreferencesStore.stageFrameShadowKey
        )

        let manager = fixture.makeManager()

        #expect(manager.spotlightOutsideOpacity == SpotlightAppearance.defaultOutsideOpacity)
        #expect(manager.stageFramePadding == StageFrameAppearance.defaultPadding)
        #expect(manager.stageFrameCornerRadius == StageFrameAppearance.defaultCornerRadius)
        #expect(manager.stageFrameBlur == StageFrameAppearance.defaultBlur)
        #expect(manager.stageFrameShadow == StageFrameAppearance.defaultShadow)
    }

    @Test("Normalizes non-finite values before publishing them to the UI")
    @MainActor
    func normalizesNonFiniteSetterValues() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        let manager = fixture.makeManager()

        manager.setSpotlightOutsideOpacity(.nan)
        manager.setStageFramePadding(.infinity)
        manager.setStageFrameCornerRadius(-.infinity)
        manager.setStageFrameBlur(.nan)
        manager.setStageFrameShadow(.infinity)

        #expect(manager.spotlightOutsideOpacity == SpotlightAppearance.defaultOutsideOpacity)
        #expect(manager.stageFramePadding == StageFrameAppearance.defaultPadding)
        #expect(manager.stageFrameCornerRadius == StageFrameAppearance.defaultCornerRadius)
        #expect(manager.stageFrameBlur == StageFrameAppearance.defaultBlur)
        #expect(manager.stageFrameShadow == StageFrameAppearance.defaultShadow)
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

    @Test("Rejects invalid logo data")
    @MainActor
    func rejectsInvalidLogoData() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }

        let manager = fixture.makeManager()

        #expect(!manager.setStageLogoData(Data("not an image".utf8)))
        #expect(manager.stageLogo == nil)
        #expect(fixture.store.legacyStageLogoData == nil)
        #expect(fixture.store.stageLogoStorageVersion == nil)
    }

    @Test("Migrates the legacy defaults logo to Application Support storage")
    @MainActor
    func migratesLegacyLogo() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        let logoData = try #require(makeLogoData())
        fixture.store.legacyStageLogoData = logoData

        let manager = fixture.makeManager()

        #expect(manager.stageLogo != nil)
        #expect(fixture.store.legacyStageLogoData == nil)
        #expect(fixture.store.stageLogoStorageVersion == StageLogoStore.storageVersion)
        #expect(FileManager.default.fileExists(atPath: fixture.logoStore.fileURL.path))
    }

    @Test("Rejects oversized decoded image dimensions")
    @MainActor
    func rejectsOversizedDecodedDimensions() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        let manager = fixture.makeManager()
        let oversizedData = try #require(makePNGData(width: 9_000, height: 1))

        #expect(!manager.setStageLogoData(oversizedData))
        #expect(manager.stageLogo == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.logoStore.fileURL.path))
    }

    @Test("Downsamples imported logos before file persistence")
    @MainActor
    func downsamplesImportedLogo() throws {
        let fixture = try PreferencesFixture()
        defer { fixture.dispose() }
        let manager = fixture.makeManager()
        let sourceData = try #require(makePNGData(width: 2_500, height: 2))

        #expect(manager.setStageLogoData(sourceData))
        let storedData = try Data(contentsOf: fixture.logoStore.fileURL)
        let imageSource = try #require(CGImageSourceCreateWithData(storedData as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? NSNumber)

        #expect(width.intValue <= StageLogoStore.maximumStoredDimension)
        #expect(storedData != sourceData)
    }

    @MainActor
    private func makeLogoData() -> Data? {
        let image = NSImage(size: NSSize(width: 24, height: 12))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 12).fill()
        image.unlockFocus()
        return image.tiffRepresentation
    }

    @MainActor
    private func makePNGData(width: Int, height: Int) -> Data? {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct PreferencesFixture {
    let suiteName: String
    let defaults: UserDefaults
    let logoStore: StageLogoStore

    var store: PresentationPreferencesStore {
        PresentationPreferencesStore(defaults: defaults)
    }

    init() throws {
        suiteName = "PresentationPreferencesTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        logoStore = StageLogoStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
        )
    }

    @MainActor
    func makeManager() -> CaptureManager {
        CaptureManager(defaults: defaults, stageLogoStore: logoStore)
    }

    func dispose() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: logoStore.directoryURL)
    }
}
