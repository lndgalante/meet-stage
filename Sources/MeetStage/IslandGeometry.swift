import AppKit
import SwiftUI

/// What the island needs to know about the display it docks on, read once so
/// layout stays a pure function.
struct IslandScreen: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    /// The safe area's top inset: the notch's height, or 0 without one.
    var safeTop: CGFloat
    /// The widths of the menu bar on either side of the notch, when there is one.
    var auxLeftWidth: CGFloat?
    var auxRightWidth: CGFloat?
    var scale: CGFloat = 2

    init(
        frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat, auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?,
        scale: CGFloat = 2
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeTop = safeTop
        self.auxLeftWidth = auxLeftWidth
        self.auxRightWidth = auxRightWidth
        self.scale = scale
    }

    @MainActor init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width, auxRightWidth: screen.auxiliaryTopRightArea?.width,
            scale: screen.backingScaleFactor)
    }

    /// The display with the camera: the built-in one while the lid is open, else
    /// the primary. Never `NSScreen.main`, which follows the key window and would
    /// make the island jump between displays.
    @MainActor static func camera() -> NSScreen? {
        NSScreen.screens.first { $0.cgDirectDisplayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
            ?? NSScreen.screens.first
    }

    /// The camera housing in global AppKit coordinates, when the display has one.
    var notch: CGRect? {
        guard safeTop > 0, let left = auxLeftWidth, let right = auxRightWidth else { return nil }
        return CGRect(
            x: frame.minX + left, y: frame.maxY - safeTop, width: frame.width - left - right, height: safeTop)
    }

    /// The strip beside the camera: as tall as the menu bar, or the notch when an
    /// auto-hidden menu bar leaves only that; an internal row without a notch.
    var band: CGFloat { notch == nil ? 28 : max(safeTop, frame.maxY - visibleFrame.maxY) }

    /// The y an island hangs from: the top edge with a notch, else the bottom of the menu bar.
    var islandTop: CGFloat { notch == nil ? visibleFrame.maxY : frame.maxY }

    /// The x an island is centered on: the camera, else the middle of the display.
    var islandMidX: CGFloat { notch?.midX ?? frame.midX }
}

/// Where the island sits and how big it is at a text size. With a notch it is
/// flush with the top edge and centered on the camera; without one it hangs
/// from the bottom of the menu bar.
struct IslandLayout: Equatable {
    /// The camera housing in global AppKit coordinates, when the display has one.
    var notch: CGRect?
    /// The script's text size the island is sized for.
    var fontSize: Double
    /// The y every shape hangs from.
    var top: CGFloat
    var midX: CGFloat
    /// The strip beside the camera: as tall as the menu bar with a notch, an internal row without.
    var band: CGFloat
    var scale: CGFloat
    var width: CGFloat
    var height: CGFloat
    var compactWidth: CGFloat
    /// One row of the line plus the gap below it.
    var advance: CGFloat
    /// The height that shows the line's rows.
    var viewport: CGFloat
    var textWidth: CGFloat
    /// Rows kept visible above the row being read.
    var anchor: Int
    var meterWidth: CGFloat

    /// The gap between the band's two slots: the camera, or a small gap without one.
    var slotGap: CGFloat { notch?.width ?? 16 }

    static func make(screen: IslandScreen, fontSize: Double, rowHeight: CGFloat) -> IslandLayout {
        let notch = screen.notch
        let size = CGFloat(fontSize)
        let band = screen.band
        let width = min(700, max(460, 16 * size + 84))
        let advance = rowHeight + max(8, (0.3 * size).rounded())
        let viewport = min(150, (2.6 * advance).rounded())
        return IslandLayout(
            notch: notch, fontSize: fontSize, top: screen.islandTop, midX: screen.islandMidX, band: band,
            scale: screen.scale, width: width,
            height: band + 6 + viewport + 48, compactWidth: (notch?.width ?? 76) + 224, advance: advance,
            viewport: viewport, textWidth: width - 56, anchor: viewport / advance >= 2.5 ? 1 : 0,
            meterWidth: width >= 500 ? 88 : 68)
    }

    /// A window frame of `size` hanging from the top, centered on the camera and
    /// on whole backing pixels.
    func frame(for size: CGSize) -> CGRect {
        .hanging(size, from: top, midX: midX, scale: scale)
    }

    /// A global CoreGraphics point (top-left origin, as events and hit tests use)
    /// in AppKit's bottom-left space, which hangs off the primary display.
    static func appKitPoint(_ point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }
}

/// The island's outline at rest in one of its sizes; animating between two
/// morphs the island.
struct IslandShapeState: Equatable {
    var size: CGSize
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    /// A notch of `size`, where an island's growing starts and folding ends.
    static func notch(_ size: CGSize) -> Self {
        .init(size: size, shoulder: 6, bottomRadius: 10)
    }

    /// The notch itself, where showing starts and hiding ends. Without a notch, a
    /// sliver that fades out.
    static func collapsed(_ layout: IslandLayout) -> Self {
        .notch(layout.notch?.size ?? CGSize(width: 120, height: 4))
    }

    static func compact(_ layout: IslandLayout) -> Self {
        .init(size: CGSize(width: layout.compactWidth, height: layout.band), shoulder: 8, bottomRadius: 12)
    }

    static func expanded(_ layout: IslandLayout) -> Self {
        .init(size: CGSize(width: layout.width, height: layout.height), shoulder: 16, bottomRadius: 20)
    }
}

/// The teleprompter at rest on screen, for the demo notice to hang below.
struct DockedIsland: Equatable {
    var frame: CGRect
    /// The body between the shoulders, which a card below matches.
    var bodyWidth: CGFloat

    init(_ shape: IslandShapeState, in layout: IslandLayout) {
        frame = layout.frame(for: shape.size)
        bodyWidth = shape.size.width - 2 * shape.shoulder
    }
}

extension CGRect {
    /// A window frame of `size` hanging from `top`, centered on `midX` and on whole backing pixels.
    static func hanging(_ size: CGSize, from top: CGFloat, midX: CGFloat, scale: CGFloat) -> CGRect {
        let x = ((midX - size.width / 2) * scale).rounded() / scale
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

extension CGSize {
    /// Big enough for both, as a window is while its shape morphs between them.
    func covering(_ other: CGSize) -> CGSize {
        CGSize(width: max(width, other.width), height: max(height, other.height))
    }
}

/// Textream's concave shoulders (NotchOverlayController.swift:613-675), where
/// the island meets the menu bar, on a body with continuous bottom corners.
struct IslandShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(shoulder, bottomRadius) }
        set {
            shoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulder, rect.width / 4, rect.height)
        let radius = max(0, min(bottomRadius, (rect.width - 2 * shoulder) / 2, rect.height))
        var path = UnevenRoundedRectangle(
            bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous
        )
        .path(in: CGRect(x: rect.minX + shoulder, y: rect.minY, width: rect.width - 2 * shoulder, height: rect.height))
        guard shoulder > 0 else { return path }
        // Fills between the top edge and a curve bowing toward the body's top corner.
        var flare = Path()
        flare.move(to: CGPoint(x: rect.minX, y: rect.minY))
        flare.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        flare.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
        flare.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.addPath(flare)
        path.addPath(flare.applying(CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0).scaledBy(x: -1, y: 1)))
        return path
    }
}

/// The script's type, measured in AppKit so rows break exactly where SwiftUI draws them.
enum IslandType {
    static func font(size: CGFloat, bold: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    static func rowHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }
}
