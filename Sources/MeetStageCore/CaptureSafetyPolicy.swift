import Foundation

/// Framework-neutral window bounds used by the security policies that sit
/// between macOS window discovery and synthesized input.
public struct CaptureWindowBounds: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    fileprivate var isUsable: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && width > 0 && height > 0
    }

    fileprivate func disagreement(with other: CaptureWindowBounds) -> Double {
        abs(x - other.x) + abs(y - other.y)
            + abs(width - other.width) + abs(height - other.height)
    }
}

/// Fail-closed policy for proving that the selected CG window is the one
/// currently focused in its Accessibility application.
public enum ExactWindowFocusPolicy {
    public static let frameMatchTolerance = 8.0
    private static let tieTolerance = 0.5

    /// Returns the sole best Accessibility-window index matching `source`, or
    /// nil when no candidate is close enough or the result is ambiguous.
    public static func uniqueBestMatch(
        source: CaptureWindowBounds,
        candidates: [CaptureWindowBounds]
    ) -> Int? {
        guard source.isUsable else { return nil }

        var bestIndex: Int?
        var bestScore = Double.greatestFiniteMagnitude
        var hasTie = false

        for (index, candidate) in candidates.enumerated() where candidate.isUsable {
            let score = candidate.disagreement(with: source)
            if score < bestScore - tieTolerance {
                bestIndex = index
                bestScore = score
                hasTie = false
            } else if abs(score - bestScore) <= tieTolerance {
                hasTie = true
            }
        }

        guard !hasTie, bestScore <= frameMatchTolerance else { return nil }
        return bestIndex
    }

    public static func allowsActuation(
        sourcePID: Int,
        frontmostPID: Int?,
        windowOwnerPID: Int?,
        windowIsOnScreen: Bool,
        matchingWindowIndex: Int?,
        focusedWindowIndex: Int?
    ) -> Bool {
        sourcePID > 0
            && frontmostPID == sourcePID
            && windowOwnerPID == sourcePID
            && windowIsOnScreen
            && matchingWindowIndex != nil
            && focusedWindowIndex == matchingWindowIndex
    }
}

/// A complete frame may publish a pending source only when it belongs to the
/// exact render generation installed for that source switch.
public enum CaptureFrameAcceptancePolicy {
    public static func confirmsSelection(
        expectedGeneration: UInt64?,
        frameGeneration: UInt64
    ) -> Bool {
        expectedGeneration == frameGeneration
    }
}
