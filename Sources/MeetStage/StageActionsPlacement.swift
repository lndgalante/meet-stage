import Foundation

enum StageActionsMetrics {
    static let heroDiameter: CGFloat = 44
    static let panelWidth: CGFloat = 56
    static let cornerRadius: CGFloat = 18
    static let inset: CGFloat = 10
    static let spacing: CGFloat = 6
    static let panelHeight =
        ControlMetrics.controlBarButtonHeight * 6
        + spacing * 6 + heroDiameter + 8 + inset * 2
    static let edgeGap: CGFloat = 12
    static let panelSize = CGSize(width: panelWidth, height: panelHeight)
}

enum StageActionsPlacement {
    /// AppKit screen coordinates. Prefer the right gutter, then the left, then
    /// inset the controls over the source without changing its captured pixels.
    static func panelFrame(
        sourceFrame: CGRect,
        visibleScreen: CGRect,
        panelSize: CGSize = StageActionsMetrics.panelSize
    ) -> CGRect? {
        let visibleSource = sourceFrame.intersection(visibleScreen)
        guard !visibleSource.isNull, !visibleSource.isEmpty,
            panelSize.width > 0, panelSize.height > 0,
            visibleScreen.width >= panelSize.width,
            visibleScreen.height >= panelSize.height
        else { return nil }

        let gap = StageActionsMetrics.edgeGap
        let x: CGFloat
        if sourceFrame.maxX + gap + panelSize.width <= visibleScreen.maxX {
            x = sourceFrame.maxX + gap
        } else if sourceFrame.minX - gap - panelSize.width >= visibleScreen.minX {
            x = sourceFrame.minX - gap - panelSize.width
        } else {
            x = visibleSource.maxX - gap - panelSize.width
        }

        return CGRect(
            x: min(max(x, visibleScreen.minX), visibleScreen.maxX - panelSize.width),
            y: min(
                max(visibleSource.midY - panelSize.height / 2, visibleScreen.minY),
                visibleScreen.maxY - panelSize.height
            ),
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
