import Foundation

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
