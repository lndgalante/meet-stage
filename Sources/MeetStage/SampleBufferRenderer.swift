import AppKit
import AVFoundation
import CoreMedia
import QuartzCore
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
    private var isSuppressingFrames = false
    private var transitionsNextFrame = false

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

    func prepareForSourceSwitch() {
        lock.lock()
        isSuppressingFrames = true
        transitionsNextFrame = false
        lock.unlock()
    }

    func commitSourceSwitch() {
        lock.lock()
        isSuppressingFrames = false
        transitionsNextFrame = true
        lock.unlock()
    }

    func cancelSourceSwitch() {
        lock.lock()
        isSuppressingFrames = false
        transitionsNextFrame = false
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
        guard !isSuppressingFrames else {
            lock.unlock()
            return nil
        }
        let startsTransition = transitionsNextFrame
        transitionsNextFrame = false
        let currentView = view
        lock.unlock()
        currentView?.enqueue(
            sampleBuffer,
            geometry: geometry,
            startsTransition: startsTransition
        )
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
        isSuppressingFrames = false
        transitionsNextFrame = false
        let currentView = view
        lock.unlock()
        currentView?.clear()
    }
}

final class StageVideoView: NSView {
    private var activeDisplayLayer = StageVideoView.makeDisplayLayer()
    private var activeFrameGeometry: CaptureFrameGeometry?
    private var retiringDisplayLayer: AVSampleBufferDisplayLayer?
    private var retiringFrameGeometry: CaptureFrameGeometry?
    var reducesMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        layer?.addSublayer(activeDisplayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFrame(of: activeDisplayLayer, geometry: activeFrameGeometry)
        if let retiringDisplayLayer {
            updateFrame(of: retiringDisplayLayer, geometry: retiringFrameGeometry)
        }
        CATransaction.commit()
    }

    func enqueue(
        _ sampleBuffer: CMSampleBuffer,
        geometry: CaptureFrameGeometry,
        startsTransition: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if startsTransition, activeFrameGeometry != nil {
                transition(to: sampleBuffer, geometry: geometry)
            } else {
                enqueue(sampleBuffer, on: activeDisplayLayer)
                activeFrameGeometry = geometry
                needsLayout = true
            }
        }
    }

    func clear() {
        let clearLayers = { [weak self] in
            guard let self else { return }
            removeRetiringLayer()
            activeFrameGeometry = nil
            activeDisplayLayer.removeAllAnimations()
            activeDisplayLayer.opacity = 1
            activeDisplayLayer.flushAndRemoveImage()
        }
        if Thread.isMainThread {
            clearLayers()
        } else {
            DispatchQueue.main.async(execute: clearLayers)
        }
    }

    private func transition(
        to sampleBuffer: CMSampleBuffer,
        geometry: CaptureFrameGeometry
    ) {
        removeRetiringLayer()

        let oldLayer = activeDisplayLayer
        let oldGeometry = activeFrameGeometry
        let oldStartOpacity = oldLayer.presentation()?.opacity ?? oldLayer.opacity
        oldLayer.removeAllAnimations()

        let newLayer = Self.makeDisplayLayer()
        newLayer.opacity = 0
        layer?.addSublayer(newLayer)
        activeDisplayLayer = newLayer
        activeFrameGeometry = geometry
        retiringDisplayLayer = oldLayer
        retiringFrameGeometry = oldGeometry

        updateFrame(of: oldLayer, geometry: oldGeometry)
        updateFrame(of: newLayer, geometry: geometry)
        enqueue(sampleBuffer, on: newLayer)

        let duration: CFTimeInterval = reducesMotion ? 0.10 : 0.20
        let newOpacity = CAKeyframeAnimation(keyPath: "opacity")
        let oldOpacity = CAKeyframeAnimation(keyPath: "opacity")

        if reducesMotion {
            newOpacity.values = [0, 1]
            newOpacity.keyTimes = [0, 1]
            oldOpacity.values = [oldStartOpacity, 0]
            oldOpacity.keyTimes = [0, 1]
            let timingFunction = CAMediaTimingFunction(name: .easeOut)
            newOpacity.timingFunctions = [timingFunction]
            oldOpacity.timingFunctions = [timingFunction]
        } else {
            // Fade the old source fully out before revealing the new source.
            newOpacity.values = [0, 0, 1]
            newOpacity.keyTimes = [0, 0.42, 1]
            oldOpacity.values = [oldStartOpacity, 0, 0]
            oldOpacity.keyTimes = [0, 0.42, 1]
            newOpacity.timingFunctions = Self.transitionTimingFunctions
            oldOpacity.timingFunctions = Self.transitionTimingFunctions
        }
        newOpacity.duration = duration
        oldOpacity.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak oldLayer] in
            guard let self, let oldLayer,
                  retiringDisplayLayer === oldLayer else { return }
            removeRetiringLayer()
        }
        newLayer.opacity = 1
        oldLayer.opacity = 0
        newLayer.add(newOpacity, forKey: "betterDemosSourceIn")
        oldLayer.add(oldOpacity, forKey: "betterDemosSourceOut")
        CATransaction.commit()
    }

    private func enqueue(_ sampleBuffer: CMSampleBuffer, on displayLayer: AVSampleBufferDisplayLayer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func removeRetiringLayer() {
        guard let retiringDisplayLayer else { return }
        retiringDisplayLayer.removeAllAnimations()
        retiringDisplayLayer.flushAndRemoveImage()
        retiringDisplayLayer.removeFromSuperlayer()
        self.retiringDisplayLayer = nil
        retiringFrameGeometry = nil
    }

    private func updateFrame(
        of displayLayer: AVSampleBufferDisplayLayer,
        geometry frameGeometry: CaptureFrameGeometry?
    ) {
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

    private static func makeDisplayLayer() -> AVSampleBufferDisplayLayer {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resize
        displayLayer.backgroundColor = NSColor.black.cgColor
        return displayLayer
    }

    private static var transitionTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
    }
}
