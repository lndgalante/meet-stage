import AppKit
import Testing
@testable import MeetStage

@Suite("Stage window sizing")
struct StageWindowSizingTests {
    @Test
    func testWideStageUsesPreferredScreenFraction() {
        let size = StageWindowSizing.windowContentSize(
            aspectRatio: 16 / 9,
            fitting: NSSize(width: 1_440, height: 900)
        )

        #expect(abs(size.width - 979) < 0.001)
        #expect(abs(size.height - 551) < 0.001)
    }

    @Test
    func testPortraitStageHonorsPreferredMinimumWidthWhenItFitsOnScreen() {
        let size = StageWindowSizing.windowContentSize(
            aspectRatio: 0.75,
            fitting: NSSize(width: 1_440, height: 900)
        )

        #expect(abs(size.width - 640) < 0.001)
        #expect(abs(size.height - 853) < 0.001)
    }

    @Test
    func testPortraitStageDoesNotApplyMinimumWidthBeyondVisibleHeight() {
        let size = StageWindowSizing.windowContentSize(
            aspectRatio: 0.75,
            fitting: NSSize(width: 1_440, height: 400)
        )

        #expect(abs(size.width - 204) < 0.001)
        #expect(abs(size.height - 272) < 0.001)
    }

    @Test
    func testInvalidAspectRatioUsesSafeDefault() {
        #expect(abs(StageWindowSizing.normalizedAspectRatio(.nan) - 1.6) < 0.001)
        #expect(abs(StageWindowSizing.normalizedAspectRatio(-1) - 1.6) < 0.001)
    }

    @Test
    func testAspectRatioIsClampedToSupportedRange() {
        #expect(abs(StageWindowSizing.normalizedAspectRatio(0.2) - 0.75) < 0.001)
        #expect(abs(StageWindowSizing.normalizedAspectRatio(8) - 3) < 0.001)
    }

    @Test
    func testEmptyVisibleSizeProducesEmptyWindowSize() {
        let size = StageWindowSizing.windowContentSize(
            aspectRatio: 16 / 9,
            fitting: .zero
        )

        #expect(size == .zero)
    }

    @Test
    func testCapturePixelCountsArePositiveAndEven() {
        #expect(StageWindowSizing.evenPixelCount(.nan) == 2)
        #expect(StageWindowSizing.evenPixelCount(-10) == 2)
        #expect(StageWindowSizing.evenPixelCount(3) == 2)
        #expect(StageWindowSizing.evenPixelCount(5.6) == 6)
    }
}
