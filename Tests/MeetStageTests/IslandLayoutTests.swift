import AppKit
import SwiftUI
import Testing

@testable import MeetStage

@Suite("Island layout")
struct IslandLayoutTests {
    /// A 14-inch MacBook Pro: 1728 × 1117 points, a 185-point notch, a 33-point menu bar.
    private let builtIn = IslandScreen(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 94, width: 1728, height: 990),
        safeTop: 32, auxLeftWidth: 771, auxRightWidth: 772)

    private func layout(_ screen: IslandScreen, size: Double = 26, rowHeight: CGFloat = 31) -> IslandLayout {
        IslandLayout.make(screen: screen, fontSize: size, rowHeight: rowHeight)
    }

    private func expandedFrame(_ layout: IslandLayout) -> CGRect {
        layout.frame(for: IslandShapeState.expanded(layout).size)
    }

    private func compactFrame(_ layout: IslandLayout) -> CGRect {
        layout.frame(for: IslandShapeState.compact(layout).size)
    }

    @Test("With a notch, the island is flush with the top and centered on the camera")
    func notchedDisplay() {
        let layout = layout(builtIn)
        #expect(layout.notch == CGRect(x: 771, y: 1085, width: 185, height: 32))
        #expect(layout.band == 33)
        #expect(layout.midX == 863.5)
        #expect(layout.top == 1117)
        #expect(layout.slotGap == 185)
        #expect(layout.width == 500)
        #expect(layout.advance == 39)
        #expect(layout.viewport == 101)
        #expect(layout.height == 188)
        #expect(layout.anchor == 1)
        #expect(layout.textWidth == 444)
        #expect(layout.meterWidth == 88)
        #expect(expandedFrame(layout) == CGRect(x: 613.5, y: 929, width: 500, height: 188))
        #expect(compactFrame(layout) == CGRect(x: 659, y: 1084, width: 409, height: 33))
    }

    @Test("An auto-hidden menu bar leaves the band as tall as the notch")
    func autoHiddenMenuBar() {
        var screen = builtIn
        screen.visibleFrame = CGRect(x: 0, y: 94, width: 1728, height: 1023)
        let layout = layout(screen)
        #expect(layout.band == 32)
        #expect(expandedFrame(layout) == CGRect(x: 613.5, y: 930, width: 500, height: 187))
    }

    @Test("Without a notch, the island hangs from the menu bar in the middle of the display")
    func externalDisplay() {
        let screen = IslandScreen(
            frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1055), safeTop: 0, auxLeftWidth: nil,
            auxRightWidth: nil)
        let layout = layout(screen)
        #expect(layout.notch == nil)
        #expect(layout.band == 28)
        #expect(layout.slotGap == 16)
        #expect(expandedFrame(layout) == CGRect(x: 2438, y: 872, width: 500, height: 183))
        #expect(
            layout.frame(for: IslandShapeState.compact(layout).size) == CGRect(x: 2538, y: 1027, width: 300, height: 28)
        )
        #expect(
            IslandShapeState.collapsed(layout)
                == .init(size: CGSize(width: 120, height: 4), shoulder: 6, bottomRadius: 10))
    }

    @Test("Text size sets the width and depth, within 460 to 700 points")
    func textSizes() {
        let small = layout(builtIn, size: 16, rowHeight: 19)
        #expect(small.width == 460)
        #expect(small.height == 157)
        #expect(small.meterWidth == 68)
        #expect(small.anchor == 1)
        let large = layout(builtIn, size: 48, rowHeight: 57)
        #expect(large.width == 700)
        #expect(large.height == 237)
        // Rows this tall leave no room to keep the previous one in view.
        #expect(large.anchor == 0)
    }

    @Test("From 40 points up the island is as large as it gets, so a new text size changes only the content")
    func largestIsland() {
        let layouts = stride(from: 40.0, through: 48, by: 2).map { size in
            layout(builtIn, size: size, rowHeight: IslandType.rowHeight(IslandType.font(size: size, bold: false)))
        }
        #expect(layouts.allSatisfy { IslandShapeState.expanded($0) == .expanded(layouts[0]) })
        #expect(IslandShapeState.expanded(layouts[0]).size == CGSize(width: 700, height: 237))
        #expect(Set(layouts.map(\.advance)).count == layouts.count)
    }

    @Test("Rows are measured in the rounded script font")
    func rowHeights() {
        for (size, height): (CGFloat, CGFloat) in [(16, 19), (26, 31), (48, 57)] {
            #expect(IslandType.rowHeight(IslandType.font(size: size, bold: false)) == height)
            #expect(IslandType.rowHeight(IslandType.font(size: size, bold: true)) == height)
        }
    }

    @Test("The shape grows from the notch to the compact and expanded sizes")
    func shapeStates() {
        let layout = layout(builtIn)
        #expect(
            IslandShapeState.collapsed(layout)
                == .init(size: CGSize(width: 185, height: 32), shoulder: 6, bottomRadius: 10))
        #expect(
            IslandShapeState.compact(layout)
                == .init(size: CGSize(width: 409, height: 33), shoulder: 8, bottomRadius: 12))
        #expect(
            IslandShapeState.expanded(layout)
                == .init(size: CGSize(width: 500, height: 188), shoulder: 16, bottomRadius: 20))
    }

    @Test("Shoulders fill between the top edge and the curve; the body below is inset by the shoulder")
    func shapePath() {
        let path = IslandShape(shoulder: 16, bottomRadius: 20).path(in: CGRect(x: 0, y: 0, width: 500, height: 188))
        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 500, height: 188))
        #expect(path.contains(CGPoint(x: 250, y: 100)))
        // Near the top edge the shoulder reaches out toward the menu bar…
        #expect(path.contains(CGPoint(x: 15, y: 1)))
        #expect(path.contains(CGPoint(x: 485, y: 1)))
        #expect(!path.contains(CGPoint(x: 3, y: 1)))
        #expect(!path.contains(CGPoint(x: 497, y: 1)))
        // …and curves in to the body's edge below it.
        #expect(!path.contains(CGPoint(x: 2, y: 10)))
        #expect(!path.contains(CGPoint(x: 8, y: 100)))
        #expect(path.contains(CGPoint(x: 17, y: 100)))
        #expect(!path.contains(CGPoint(x: 17, y: 187)))
        #expect(!path.contains(CGPoint(x: 483, y: 187)))
    }

    @Test("At rest, the chrome draws the mode's shape with its content showing")
    @MainActor func restingChrome() {
        let layout = layout(builtIn)
        #expect(layout.fontSize == 26)
        let expanded = IslandChrome(resting: .expanded, in: layout)
        #expect(expanded.shape == .expanded(layout))
        #expect(expanded.contentMode == .expanded)
        #expect(expanded.contentSize == CGSize(width: 500, height: 188))
        #expect(expanded.contentOpacity == 1)
        let compact = IslandChrome(resting: .compact, in: layout)
        #expect(compact.shape == .compact(layout))
        #expect(compact.contentMode == .compact)
        #expect(compact.contentSize == CGSize(width: 409, height: 33))
    }

    @Test("Window frames sit on whole backing pixels")
    func pixelAligned() {
        let layout = layout(builtIn)
        #expect(layout.frame(for: CGSize(width: 500.5, height: 10)).minX == 613.5)
    }

    @Test("Event coordinates convert to AppKit's, measured from the primary display's bottom")
    func appKitPoint() {
        #expect(IslandLayout.appKitPoint(CGPoint(x: 900, y: 20), primaryMaxY: 1117) == CGPoint(x: 900, y: 1097))
        #expect(IslandLayout.appKitPoint(CGPoint(x: 2000, y: -30), primaryMaxY: 1117) == CGPoint(x: 2000, y: 1147))
    }
}
