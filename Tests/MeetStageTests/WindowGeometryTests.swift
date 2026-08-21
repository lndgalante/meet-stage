import CoreGraphics
import Testing
@testable import MeetStage

@Suite("Window geometry")
struct WindowGeometryTests {
    @Test("Accepts every source-window edge")
    func acceptsWindowEdges() {
        let sourceFrame = CGRect(x: 100, y: 200, width: 300, height: 200)

        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                inside: CGPoint(x: sourceFrame.minX, y: sourceFrame.minY),
                sourceFrame: sourceFrame
            ) == NormalizedWindowPoint(x: 0, y: 0)
        )
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                inside: CGPoint(x: sourceFrame.maxX, y: sourceFrame.maxY),
                sourceFrame: sourceFrame
            ) == NormalizedWindowPoint(x: 1, y: 1)
        )
    }

    @Test("Rejects coordinate spaces without area")
    func rejectsEmptyCoordinateSpaces() {
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                inside: .zero,
                sourceFrame: .zero
            ) == nil
        )
        #expect(
            WindowCoordinateGeometry.normalizedPoint(
                clamping: .zero,
                in: .zero
            ) == nil
        )
    }

    @Test("Converts overlays relative to the primary screen's top edge")
    func convertsRelativeToPrimaryScreen() {
        let frame = SourceOverlayGeometry.appKitFrame(
            forQuartzFrame: CGRect(x: -400, y: 50, width: 300, height: 200),
            primaryScreenFrame: CGRect(x: 0, y: -100, width: 1_440, height: 1_000)
        )

        #expect(frame == CGRect(x: -400, y: 650, width: 300, height: 200))
    }
}
