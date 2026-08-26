import CoreGraphics
import Testing
@testable import MeetStage

@Suite("Automatic presentation polish")
struct AutoPresentationTests {
    @Test("Initial zoom focus stays inside the visible source bounds")
    func clampsInitialFocus() {
        let focus = AutoZoomCameraPolicy.clampedFocus(
            NormalizedWindowPoint(x: 0.02, y: 0.98),
            scale: 2
        )

        #expect(focus == NormalizedWindowPoint(x: 0.25, y: 0.75))
    }

    @Test("The camera stays still while the pointer remains in its safe zone")
    func safeZonePreventsCameraChasing() {
        let current = NormalizedWindowPoint(x: 0.5, y: 0.5)
        let focus = AutoZoomCameraPolicy.focusFollowingPointer(
            current: current,
            pointer: NormalizedWindowPoint(x: 0.58, y: 0.42),
            scale: 1.6
        )

        #expect(focus == current)
    }

    @Test("The camera shifts only enough to return an escaped pointer to the safe zone")
    func followsPointerOutsideSafeZone() {
        let focus = AutoZoomCameraPolicy.focusFollowingPointer(
            current: NormalizedWindowPoint(x: 0.5, y: 0.5),
            pointer: NormalizedWindowPoint(x: 0.82, y: 0.5),
            scale: 1.6
        )

        #expect(abs(focus.x - 0.645) < 0.0001)
        #expect(focus.y == 0.5)
    }

    @Test("Zoom transform never reveals space outside the captured source")
    func clampsZoomTransform() {
        let transform = AutoZoomTransform.resolve(
            focus: NormalizedWindowPoint(x: 0.98, y: 0.02),
            requestedScale: 1.8,
            viewportSize: CGSize(width: 1_000, height: 600),
            reducesMotion: false
        )

        #expect(transform.scale == 1.8)
        #expect(transform.offset.width == -800)
        #expect(abs(transform.offset.height) < 0.0001)
    }

    @Test("Reduce Motion keeps a restrained focus change")
    func reducesZoomMotion() {
        let transform = AutoZoomTransform.resolve(
            focus: NormalizedWindowPoint(x: 0.5, y: 0.5),
            requestedScale: 1.8,
            viewportSize: CGSize(width: 1_000, height: 600),
            reducesMotion: true
        )

        #expect(transform.scale == 1.12)
    }

    @Test("The mirrored system cursor is exactly twice as large and keeps its hotspot")
    func enlargesSystemCursorAroundHotSpot() {
        let frame = EnlargedCursorGeometry.frame(
            pointerLocation: NormalizedWindowPoint(x: 0.25, y: 0.5),
            viewportSize: CGSize(width: 800, height: 600),
            imageSize: CGSize(width: 20, height: 30),
            hotSpot: CGPoint(x: 2, y: 3)
        )

        #expect(frame == CGRect(x: 196, y: 294, width: 40, height: 60))
    }

    @Test("Styled frames preserve source aspect ratio inside uniform padding")
    func laysOutStyledFrame() {
        let layout = StageFrameLayout.resolve(
            viewportSize: CGSize(width: 1_600, height: 900),
            sourceAspectRatio: 16 / 9,
            paddingFraction: 0.06,
            cornerRadius: 18,
            isEnabled: true
        )

        #expect(abs(layout.contentFrame.width / layout.contentFrame.height - 16 / 9) < 0.0001)
        #expect(layout.contentFrame.minX > 0)
        #expect(layout.contentFrame.minY > 0)
        #expect(layout.cornerRadius == 18)
    }

    @Test("Disabling frame styling uses the complete stage")
    func disablesFrameLayout() {
        let viewport = CGSize(width: 1_600, height: 900)
        let layout = StageFrameLayout.resolve(
            viewportSize: viewport,
            sourceAspectRatio: 16 / 9,
            paddingFraction: 0.12,
            cornerRadius: 28,
            isEnabled: false
        )

        #expect(layout.contentFrame == CGRect(origin: .zero, size: viewport))
        #expect(layout.cornerRadius == 0)
    }

    @Test("Stage logo stays in the bottom-right gutter")
    func positionsLogoOutsideCapturedContent() throws {
        let viewport = CGSize(width: 1_600, height: 900)
        let stage = StageFrameLayout.resolve(
            viewportSize: viewport,
            sourceAspectRatio: 16 / 9,
            paddingFraction: StageLogoAppearance.minimumStagePadding,
            cornerRadius: 18,
            isEnabled: true
        )
        let logo = try #require(
            StageLogoLayout.resolve(
                viewportSize: viewport,
                contentFrame: stage.contentFrame,
                imageSize: CGSize(width: 100, height: 100)
            )
        )

        #expect(!logo.frame.intersects(stage.contentFrame))
        #expect(logo.frame.midX > stage.contentFrame.midX)
        #expect(logo.frame.midY > stage.contentFrame.midY)
        #expect(logo.frame.maxX < viewport.width)
        #expect(logo.frame.maxY < viewport.height)
    }

    @Test("Wide logos use the lower stage gutter")
    func positionsWideLogoBelowCapturedContent() throws {
        let viewport = CGSize(width: 1_600, height: 900)
        let stage = StageFrameLayout.resolve(
            viewportSize: viewport,
            sourceAspectRatio: 16 / 9,
            paddingFraction: StageLogoAppearance.minimumStagePadding,
            cornerRadius: 18,
            isEnabled: true
        )
        let logo = try #require(
            StageLogoLayout.resolve(
                viewportSize: viewport,
                contentFrame: stage.contentFrame,
                imageSize: CGSize(width: 300, height: 80)
            )
        )

        #expect(logo.frame.minY > stage.contentFrame.maxY)
    }

    @Test("Logo is hidden when no safe gutter exists")
    func refusesToOverlayCapturedContent() {
        let viewport = CGSize(width: 1_600, height: 900)

        #expect(
            StageLogoLayout.resolve(
                viewportSize: viewport,
                contentFrame: CGRect(origin: .zero, size: viewport),
                imageSize: CGSize(width: 100, height: 100)
            ) == nil
        )
    }

    @Test("Attached logo stays inactive while Auto Polish is off")
    func hidesLogoWithoutAutoPresentation() {
        #expect(
            !StageLogoVisibilityPolicy.shouldShow(
                isLive: true,
                isAutoPresentationEnabled: false,
                hasLogo: true
            )
        )
    }

    @Test("Attached logo appears with Auto Polish")
    func showsLogoWithAutoPresentation() {
        #expect(
            StageLogoVisibilityPolicy.shouldShow(
                isLive: true,
                isAutoPresentationEnabled: true,
                hasLogo: true
            )
        )
    }
}
