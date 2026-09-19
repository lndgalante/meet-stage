import CoreGraphics

enum DockSide: String {
    case right
    case left
}

struct DockSnapTarget: Equatable {
    let side: DockSide
    let frame: CGRect
}

enum DockSnap {
    static let gap: CGFloat = 12
    static let snapDistance: CGFloat = 24

    static func targets(size: CGSize, dock: CGRect, screen: CGRect, visibleScreen: CGRect) -> [DockSnapTarget] {
        guard dock.width > dock.height, dock.height > 1,
            dock.intersects(screen), abs(dock.minY - screen.minY) <= gap * 2
        else { return [] }

        // AppKit rounds window origins; integral targets keep attachment tracking still.
        let y = max(screen.minY, dock.midY - size.height / 2).rounded(.down)
        return [
            DockSnapTarget(
                side: .right,
                frame: CGRect(x: (dock.maxX + gap).rounded(.down), y: y, width: size.width, height: size.height)),
            DockSnapTarget(
                side: .left,
                frame: CGRect(
                    x: (dock.minX - gap - size.width).rounded(.down), y: y, width: size.width, height: size.height)
            )
        ].filter { target in
            screen.contains(target.frame) && target.frame.maxY <= visibleScreen.maxY
                && !target.frame.intersects(dock)
        }
    }

    static func target(for origin: CGPoint, among targets: [DockSnapTarget]) -> DockSnapTarget? {
        targets
            .filter { distance(from: origin, to: $0.frame.origin) <= snapDistance }
            .min { distance(from: origin, to: $0.frame.origin) < distance(from: origin, to: $1.frame.origin) }
    }

    private static func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}
