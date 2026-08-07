import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

struct CaptureFrameGeometry: Sendable {
    let contentRect: CGRect
    let bufferSize: CGSize

    var contentAspectRatio: CGFloat {
        contentRect.width / contentRect.height
    }
}

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

    func enqueue(_ sampleBuffer: CMSampleBuffer) -> CaptureFrameGeometry? {
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return nil }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
           let frameInfo = attachments.first,
           let statusValue = frameInfo[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: statusValue),
           frameStatus == .complete,
           let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let bufferSize = CGSize(
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )
        let bufferBounds = CGRect(origin: .zero, size: bufferSize)
        let contentRect: CGRect
        if let contentRectInPoints = Self.contentRect(from: frameInfo) {
            let pointPixelScale = Self.pointPixelScale(from: frameInfo)
            let contentRectInPixels = contentRectInPoints.applying(
                CGAffineTransform(scaleX: pointPixelScale, y: pointPixelScale)
            )
            contentRect = contentRectInPixels.standardized.intersection(bufferBounds)
        } else {
            contentRect = bufferBounds
        }
        guard !contentRect.isNull, contentRect.width > 0, contentRect.height > 0 else { return nil }
        let geometry = CaptureFrameGeometry(contentRect: contentRect, bufferSize: bufferSize)

        lock.lock()
        let currentView = view
        lock.unlock()
        currentView?.enqueue(sampleBuffer, geometry: geometry)
        return geometry
    }

    private static func contentRect(from frameInfo: [SCStreamFrameInfo: Any]) -> CGRect? {
        guard let value = frameInfo[.contentRect] else { return nil }
        if let rect = value as? CGRect {
            return rect
        }
        guard CFGetTypeID(value as CFTypeRef) == CFDictionaryGetTypeID() else { return nil }
        return CGRect(dictionaryRepresentation: value as! CFDictionary)
    }

    private static func pointPixelScale(from frameInfo: [SCStreamFrameInfo: Any]) -> CGFloat {
        guard let number = frameInfo[.scaleFactor] as? NSNumber else { return 1 }
        let scale = CGFloat(number.doubleValue)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    func clear() {
        lock.lock()
        let currentView = view
        lock.unlock()
        currentView?.clear()
    }
}

final class StageVideoView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var frameGeometry: CaptureFrameGeometry?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        displayLayer.videoGravity = .resize
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
        updateDisplayLayerFrame()
        CATransaction.commit()
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer, geometry: CaptureFrameGeometry) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            frameGeometry = geometry
            needsLayout = true
        }
    }

    func clear() {
        frameGeometry = nil
        displayLayer.flushAndRemoveImage()
    }

    private func updateDisplayLayerFrame() {
        guard let frameGeometry else {
            displayLayer.frame = bounds
            return
        }

        let contentRect = frameGeometry.contentRect
        let bufferSize = frameGeometry.bufferSize
        let scale = max(
            bounds.width / contentRect.width,
            bounds.height / contentRect.height
        )
        displayLayer.frame = CGRect(
            x: -contentRect.minX * scale,
            y: -contentRect.minY * scale,
            width: bufferSize.width * scale,
            height: bufferSize.height * scale
        )
    }
}
