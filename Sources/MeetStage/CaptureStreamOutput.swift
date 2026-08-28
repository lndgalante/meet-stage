import CoreMedia
import Foundation
import ScreenCaptureKit

/// Bridges ScreenCaptureKit's callback queue to thread-safe rendering and
/// main-actor lifecycle callbacks. Its stored collaborators are Sendable.
final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let renderer: SampleBufferRenderer
    private let onFrame: @Sendable (ObjectIdentifier, CaptureFrameGeometry) -> Void
    private let onFailure: @Sendable (ObjectIdentifier, Error) -> Void
    private let onAnalyzableFrame: @Sendable (DemoImageBuffer, CaptureFrameGeometry) -> Void

    // Demo Mode requests a single frame for text recognition by arming this
    // flag. Only one screen output is allowed per stream, so this tap lives
    // inside the render path rather than as a second SCStreamOutput. At most one
    // frame is delivered per arm, so ScreenCaptureKit's buffer pool is not
    // starved.
    private let analyzableFrameLock = NSLock()
    private var isAnalyzableFrameArmed = false

    init(
        renderer: SampleBufferRenderer,
        onFrame: @escaping @Sendable (ObjectIdentifier, CaptureFrameGeometry) -> Void,
        onFailure: @escaping @Sendable (ObjectIdentifier, Error) -> Void,
        onAnalyzableFrame: @escaping @Sendable (DemoImageBuffer, CaptureFrameGeometry) -> Void = { _, _ in }
    ) {
        self.renderer = renderer
        self.onFrame = onFrame
        self.onFailure = onFailure
        self.onAnalyzableFrame = onAnalyzableFrame
    }

    /// Requests one frame be delivered to the analyzable-frame handler.
    func armAnalyzableFrame() {
        analyzableFrameLock.withLock { isAnalyzableFrameArmed = true }
    }

    func disarmAnalyzableFrame() {
        analyzableFrameLock.withLock { isAnalyzableFrameArmed = false }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard let geometry = renderer.enqueue(sampleBuffer) else { return }
        onFrame(ObjectIdentifier(stream), geometry)
        deliverAnalyzableFrameIfArmed(sampleBuffer, geometry: geometry)
    }

    private func deliverAnalyzableFrameIfArmed(
        _ sampleBuffer: CMSampleBuffer,
        geometry: CaptureFrameGeometry
    ) {
        let shouldDeliver = analyzableFrameLock.withLock {
            defer { isAnalyzableFrameArmed = false }
            return isAnalyzableFrameArmed
        }
        guard shouldDeliver,
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        onAnalyzableFrame(DemoImageBuffer(imageBuffer), geometry)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(ObjectIdentifier(stream), error)
    }
}
