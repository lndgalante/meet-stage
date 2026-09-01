import AppKit
import Testing
@testable import MeetStage

@Suite("Stage window sizing")
struct StageWindowSizingTests {
    @Test
    func testLiveStageUsesSourceAspectRatio() {
        let sourceAspectRatio: CGFloat = 4 / 3
        let inactiveAspectRatio: CGFloat = 16 / 10

        #expect(
            StageWindowAspectRatioPolicy.displayedAspectRatio(
                for: .capturing,
                sourceAspectRatio: sourceAspectRatio,
                inactiveAspectRatio: inactiveAspectRatio
            ) == sourceAspectRatio
        )
        #expect(
            StageWindowAspectRatioPolicy.displayedAspectRatio(
                for: .switching,
                sourceAspectRatio: sourceAspectRatio,
                inactiveAspectRatio: inactiveAspectRatio
            ) == sourceAspectRatio
        )
    }

    @Test
    func testInactiveStageStatesUseCanonicalAspectRatio() {
        let sourceAspectRatio: CGFloat = 4 / 3
        let inactiveAspectRatio: CGFloat = 16 / 10
        let states: [CaptureState] = [
            .idle,
            .loading,
            .paused,
            .permissionRequired,
            .failed("Unavailable")
        ]

        for state in states {
            #expect(
                StageWindowAspectRatioPolicy.displayedAspectRatio(
                    for: state,
                    sourceAspectRatio: sourceAspectRatio,
                    inactiveAspectRatio: inactiveAspectRatio
                ) == inactiveAspectRatio
            )
        }
    }

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

    @Test("Aspect changes preserve the user's chosen longest edge")
    func preservesUserWindowSizeAcrossAspectChanges() {
        let landscape = StageWindowSizing.resizedContentSize(
            preserving: NSSize(width: 900, height: 600),
            aspectRatio: 16 / 9,
            fitting: NSSize(width: 1_440, height: 900)
        )
        #expect(abs(landscape.width - 900) < 0.001)
        #expect(abs(landscape.height - 506.25) < 0.001)

        let portrait = StageWindowSizing.resizedContentSize(
            preserving: NSSize(width: 900, height: 600),
            aspectRatio: 0.75,
            fitting: NSSize(width: 1_440, height: 900)
        )
        #expect(abs(portrait.width - 675) < 0.001)
        #expect(abs(portrait.height - 900) < 0.001)
    }

    @Test
    func testCapturePixelCountsArePositiveAndEven() {
        #expect(StageWindowSizing.evenPixelCount(.nan) == 2)
        #expect(StageWindowSizing.evenPixelCount(-10) == 2)
        #expect(StageWindowSizing.evenPixelCount(3) == 2)
        #expect(StageWindowSizing.evenPixelCount(5.6) == 6)
    }

    @Test("Capture dimensions avoid processing an entire 4K source")
    func capsCaptureResolution() {
        let format = StageWindowSizing.captureFormat(
            forPixelSize: NSSize(width: 3_840, height: 2_160)
        )

        #expect(format == StageCaptureFormat(width: 2_560, height: 1_440))
    }

    @Test("Capture dimensions preserve smaller source pixels")
    func preservesEfficientCaptureResolution() {
        let format = StageWindowSizing.captureFormat(
            forPixelSize: NSSize(width: 1_920, height: 1_080)
        )

        #expect(format == StageCaptureFormat(width: 1_920, height: 1_080))
    }

    @Test("Downscaled frame metadata preserves the complete source aspect ratio")
    func fitsSourceSpaceMetadataIntoCaptureBuffer() {
        let contentRect = CaptureFrameGeometryResolver.contentRectInPixels(
            contentRectInPoints: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            pointPixelScale: 2,
            bufferSize: CGSize(width: 2_560, height: 1_440)
        )

        #expect(contentRect == CGRect(x: 0, y: 0, width: 2_560, height: 1_440))
    }

    @Test("Delivered-surface frame metadata keeps its existing placement")
    func preservesSurfaceSpaceMetadata() {
        let contentRect = CaptureFrameGeometryResolver.contentRectInPixels(
            contentRectInPoints: CGRect(x: 10, y: 20, width: 1_260, height: 700),
            pointPixelScale: 2,
            bufferSize: CGSize(width: 2_560, height: 1_440)
        )

        #expect(contentRect == CGRect(x: 20, y: 40, width: 2_520, height: 1_400))
    }
}
