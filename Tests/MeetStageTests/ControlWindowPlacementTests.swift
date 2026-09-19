import AppKit
import Testing
@testable import MeetStage

@Suite("Controller placement beside the Dock")
struct ControlWindowPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
    private let visible = CGRect(x: 0, y: 98, width: 2048, height: 1026)
    private let dock = CGRect(x: 398, y: 5, width: 1252, height: 93)

    @Test("First launch centers in the right gap and matches the Dock's vertical center")
    func defaultPosition() {
        let frame = place()
        #expect(frame.size == CGSize(width: 336, height: 88))
        #expect(frame.midX == (dock.maxX + screen.maxX) / 2)
        #expect(frame.midY == dock.midY)
        #expect(frame.minY == 7.5)
        #expect(!frame.intersects(dock))
        #expect(screen.contains(frame))
    }

    @Test("A narrow right gap uses the left gap")
    func leftGap() {
        let shiftedDock = CGRect(x: 500, y: 5, width: 1400, height: 93)
        let frame = place(dock: shiftedDock)
        #expect(frame.midX == shiftedDock.minX / 2)
        #expect(frame.midY == shiftedDock.midY)
    }

    @Test("The compact width fits a laptop's gap beside the Dock")
    func laptopGap() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let dock = CGRect(x: 374, y: 5, width: 980, height: 93)
        let frame = ControlWindowPlacement.frame(
            size: ControlWindowSizing.size, screen: screen,
            visibleScreen: CGRect(x: 0, y: 98, width: 1728, height: 986), dock: dock
        )
        #expect(frame.midX == (dock.maxX + screen.maxX) / 2)
        #expect(frame.midY == dock.midY)
        #expect(frame.minX - dock.maxX >= ControlWindowPlacement.edgeGap)
    }

    @Test("A wide Dock puts the controller above it without overlapping")
    func noGap() {
        let wideDock = CGRect(x: 200, y: 5, width: 1648, height: 93)
        let frame = place(dock: wideDock)
        #expect(visible.contains(frame))
        #expect(frame.minY >= wideDock.maxY + ControlWindowPlacement.edgeGap)
    }

    @Test("A smaller Dock cannot push the widget below the display")
    func smallDock() {
        let smallDock = CGRect(x: 700, y: 0, width: 648, height: 48)
        let frame = place(dock: smallDock)
        #expect(frame.minY == screen.minY)
        #expect(!frame.intersects(smallDock))
    }

    @Test("Saved manual positions remain in place, including below visibleFrame")
    func restorePosition() {
        for origin in [CGPoint(x: 20, y: 7.5), CGPoint(x: 1100, y: 300)] {
            #expect(place(savedOrigin: origin).origin == origin)
        }
    }

    @Test("A saved position covered by a changed Dock is moved clear")
    func changedDock() {
        let frame = place(savedOrigin: CGPoint(x: 500, y: 10))
        #expect(!frame.intersects(dock))
        #expect(frame.midY == dock.midY)
    }

    @Test("An unavailable or hidden Dock uses the visible desktop")
    func unavailableDock() {
        for dock in [CGRect?.none, CGRect(x: 398, y: -92, width: 1252, height: 93)] {
            let frame = ControlWindowPlacement.frame(
                size: ControlWindowSizing.size, screen: screen, visibleScreen: visible, dock: dock
            )
            #expect(visible.contains(frame))
        }
    }

    @Test("Side Docks keep the controller within the available desktop")
    func sideDock() {
        let visible = CGRect(x: 0, y: 0, width: 1950, height: 1124)
        let sideDock = CGRect(x: 1955, y: 200, width: 93, height: 752)
        let frame = ControlWindowPlacement.frame(
            size: ControlWindowSizing.size, screen: screen, visibleScreen: visible, dock: sideDock
        )
        #expect(visible.contains(frame))
        #expect(!frame.intersects(sideDock))
    }

    @Test("Negative display coordinates preserve both centering axes")
    func secondDisplay() {
        let offset = CGSize(width: -2048, height: -300)
        let frame = ControlWindowPlacement.frame(
            size: ControlWindowSizing.size,
            screen: screen.offsetBy(dx: offset.width, dy: offset.height),
            visibleScreen: visible.offsetBy(dx: offset.width, dy: offset.height),
            dock: dock.offsetBy(dx: offset.width, dy: offset.height)
        )
        #expect(frame == place().offsetBy(dx: offset.width, dy: offset.height))
    }

    @Test("Disconnected displays cannot strand a restored controller")
    func offscreenRestore() {
        let frame = place(savedOrigin: CGPoint(x: -2500, y: 1600))
        #expect(screen.contains(frame))
        #expect(frame.maxY == visible.maxY)
    }

    @Test("Native saved frames retain fractional and negative origins")
    func nativeFrame() {
        #expect(
            ControlWindowPlacement.savedOrigin(from: "-1948 7.5 360 128 -2048 0 2048 1152 ")
                == CGPoint(x: -1948, y: 7.5))
        for frame in [String?.none, "", "1 2", "nan 10 360 88", "1 2 0 88"] {
            #expect(ControlWindowPlacement.savedOrigin(from: frame) == nil)
        }
    }

    private func place(dock: CGRect? = nil, savedOrigin: CGPoint? = nil) -> CGRect {
        ControlWindowPlacement.frame(
            size: ControlWindowSizing.size, screen: screen, visibleScreen: visible,
            dock: dock ?? self.dock, savedOrigin: savedOrigin
        )
    }
}
