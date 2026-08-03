import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class SampleBufferRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private weak var view: StageVideoView?

    func attach(_ view: StageVideoView) {
        lock.lock()
        self.view = view
        lock.unlock()
    }

    func detach(_ view: StageVideoView) {
        lock.lock()
        if self.view === view {
            self.view = nil
        }
        lock.unlock()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
           let statusValue = attachments.first?[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: statusValue),
           frameStatus != .complete {
            return
        }

        lock.lock()
        let currentView = view
        lock.unlock()
        currentView?.enqueue(sampleBuffer)
    }
}

final class StageVideoView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func clear() {
        displayLayer.flushAndRemoveImage()
    }
}
