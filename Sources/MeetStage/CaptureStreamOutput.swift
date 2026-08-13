import CoreMedia
import Foundation
import ScreenCaptureKit

/// Bridges ScreenCaptureKit's callback queue to thread-safe rendering and
/// main-actor lifecycle callbacks. Its stored collaborators are Sendable.
final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let renderer: SampleBufferRenderer
    private let onFrame: @Sendable (ObjectIdentifier, CaptureFrameGeometry) -> Void
    private let onFailure: @Sendable (ObjectIdentifier, Error) -> Void

    init(
        renderer: SampleBufferRenderer,
        onFrame: @escaping @Sendable (ObjectIdentifier, CaptureFrameGeometry) -> Void,
        onFailure: @escaping @Sendable (ObjectIdentifier, Error) -> Void
    ) {
        self.renderer = renderer
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard let geometry = renderer.enqueue(sampleBuffer) else { return }
        onFrame(ObjectIdentifier(stream), geometry)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(ObjectIdentifier(stream), error)
    }
}
