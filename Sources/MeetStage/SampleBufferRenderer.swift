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

struct RenderedCaptureFrame: Sendable {
    let geometry: CaptureFrameGeometry
    let renderGeneration: UInt64
}

enum CaptureFrameGeometryResolver {
    static func contentRectInPixels(
        contentRectInPoints: CGRect,
        pointPixelScale: CGFloat,
        bufferSize: CGSize
    ) -> CGRect {
        let bufferBounds = CGRect(origin: .zero, size: bufferSize)
        guard bufferBounds.width > 0, bufferBounds.height > 0 else { return .null }

        var contentRect = contentRectInPoints.standardized.applying(
            CGAffineTransform(scaleX: pointPixelScale, y: pointPixelScale)
        )
        guard contentRect.width > 0, contentRect.height > 0 else { return .null }

        // ScreenCaptureKit normally reports contentRect in surface points. If
        // an OS version instead supplies source-space points for a downscaled
        // stream, fit the complete rect into the delivered pixel buffer rather
        // than intersecting it and changing its aspect ratio.
        let widthScale =
            contentRect.maxX > bufferBounds.maxX
            ? bufferBounds.maxX / contentRect.maxX
            : 1
        let heightScale =
            contentRect.maxY > bufferBounds.maxY
            ? bufferBounds.maxY / contentRect.maxY
            : 1
        let fitScale = min(widthScale, heightScale)
        if fitScale < 1 {
            contentRect = contentRect.applying(
                CGAffineTransform(scaleX: fitScale, y: fitScale)
            )
        }

        return contentRect.intersection(bufferBounds)
    }
}

/// Thread-safe handoff from ScreenCaptureKit's sample queue to the AppKit view.
/// Every cross-thread mutable property is protected by `lock`; `StageVideoView`
/// performs its visual work on the main queue.
final class SampleBufferRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private weak var view: StageVideoView?
    private var isSuppressingFrames = false
    private var transitionsNextFrame = false
    private var renderGeneration: UInt64 = 0

    @MainActor
    func attach(_ view: StageVideoView) {
        let generation = lock.withLock {
            self.view = view
            return renderGeneration
        }
        view.synchronizeRenderGeneration(generation)
    }

    @MainActor
    func detach(_ view: StageVideoView) {
        lock.withLock {
            if self.view === view {
                self.view = nil
            }
        }
    }

    @MainActor
    func beginCapture() -> UInt64 {
        let (generation, currentView) = lock.withLock {
            renderGeneration &+= 1
            isSuppressingFrames = false
            transitionsNextFrame = false
            return (renderGeneration, view)
        }
        currentView?.synchronizeRenderGeneration(generation)
        return generation
    }

    @MainActor
    func prepareForSourceSwitch() -> UInt64 {
        let (generation, currentView) = lock.withLock {
            renderGeneration &+= 1
            isSuppressingFrames = true
            transitionsNextFrame = false
            return (renderGeneration, view)
        }
        currentView?.synchronizeRenderGeneration(generation)
        return generation
    }

    @MainActor
    func commitSourceSwitch(generation: UInt64) {
        let currentView: StageVideoView? = lock.withLock {
            guard generation == renderGeneration else { return nil }
            isSuppressingFrames = false
            transitionsNextFrame = true
            return view
        }
        currentView?.prepareForSourceTransition(renderGeneration: generation)
    }

    @MainActor
    func cancelSourceSwitch(generation: UInt64) {
        lock.withLock {
            guard generation == renderGeneration else { return }
            isSuppressingFrames = false
            transitionsNextFrame = false
        }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) -> RenderedCaptureFrame? {
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return nil }

        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let frameInfo = attachments.first,
            let statusValue = frameInfo[.status] as? Int,
            let frameStatus = SCFrameStatus(rawValue: statusValue),
            frameStatus == .complete,
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return nil }

        let bufferSize = CGSize(
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )
        let bufferBounds = CGRect(origin: .zero, size: bufferSize)
        let contentRect: CGRect
        if let contentRectInPoints = Self.contentRect(from: frameInfo) {
            let pointPixelScale = Self.pointPixelScale(from: frameInfo)
            contentRect = CaptureFrameGeometryResolver.contentRectInPixels(
                contentRectInPoints: contentRectInPoints,
                pointPixelScale: pointPixelScale,
                bufferSize: bufferSize
            )
        } else {
            contentRect = bufferBounds
        }
        guard !contentRect.isNull, contentRect.width > 0, contentRect.height > 0 else { return nil }
        let geometry = CaptureFrameGeometry(contentRect: contentRect, bufferSize: bufferSize)

        let renderRequest: (startsTransition: Bool, generation: UInt64, view: StageVideoView?)? = lock.withLock {
            guard !isSuppressingFrames else { return nil }
            let startsTransition = transitionsNextFrame
            transitionsNextFrame = false
            return (startsTransition, renderGeneration, view)
        }
        guard let renderRequest else { return nil }
        renderRequest.view?.enqueue(
            sampleBuffer,
            geometry: geometry,
            startsTransition: renderRequest.startsTransition,
            renderGeneration: renderRequest.generation
        )
        return RenderedCaptureFrame(
            geometry: geometry,
            renderGeneration: renderRequest.generation
        )
    }

    private static func contentRect(from frameInfo: [SCStreamFrameInfo: Any]) -> CGRect? {
        guard let value = frameInfo[.contentRect] else { return nil }
        if let rect = value as? CGRect {
            return rect
        }
        guard let dictionary = value as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    private static func pointPixelScale(from frameInfo: [SCStreamFrameInfo: Any]) -> CGFloat {
        guard let number = frameInfo[.scaleFactor] as? NSNumber else { return 1 }
        let scale = CGFloat(number.doubleValue)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    @MainActor
    func clear() {
        let (generation, currentView) = lock.withLock {
            renderGeneration &+= 1
            isSuppressingFrames = true
            transitionsNextFrame = false
            return (renderGeneration, view)
        }
        currentView?.clear(renderGeneration: generation)
    }
}

/// Enqueues video directly from ScreenCaptureKit's serial callback queue. The
/// display renderer consumes the sample synchronously, so no IOSurface-backed
/// sample buffer is retained by a main-queue closure.
private final class StageVideoFrameSink: @unchecked Sendable {
    private struct Target {
        let renderer: AVSampleBufferVideoRenderer
        let generation: UInt64
    }

    private let lock = NSLock()
    private var target: Target?

    func update(renderer: AVSampleBufferVideoRenderer, generation: UInt64) {
        lock.withLock {
            target = Target(renderer: renderer, generation: generation)
        }
    }

    func clear() {
        lock.withLock { target = nil }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer, generation: UInt64) -> Bool {
        lock.withLock {
            guard let target, target.generation == generation else { return false }
            if target.renderer.status == .failed {
                target.renderer.flush()
            }
            target.renderer.enqueue(sampleBuffer)
            return true
        }
    }
}

/// An AppKit rendering surface whose state remains main-actor isolated. Only
/// lightweight geometry updates cross to the main queue; sample buffers are
/// consumed synchronously by `StageVideoFrameSink` on the capture queue.
final class StageVideoView: NSView, @unchecked Sendable {
    private var activeDisplayLayer = StageVideoView.makeDisplayLayer()
    private var activeFrameGeometry: CaptureFrameGeometry?
    private var retiringDisplayLayer: AVSampleBufferDisplayLayer?
    private var retiringFrameGeometry: CaptureFrameGeometry?
    private var renderGeneration: UInt64 = 0
    private let frameSink = StageVideoFrameSink()
    var reducesMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = true

        layer?.addSublayer(activeDisplayLayer)
        frameSink.update(
            renderer: activeDisplayLayer.sampleBufferRenderer,
            generation: renderGeneration
        )
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

    nonisolated func enqueue(
        _ sampleBuffer: CMSampleBuffer,
        geometry: CaptureFrameGeometry,
        startsTransition: Bool,
        renderGeneration: UInt64
    ) {
        guard frameSink.enqueue(sampleBuffer, generation: renderGeneration) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, renderGeneration == self.renderGeneration else { return }
            if startsTransition, retiringDisplayLayer != nil {
                revealPreparedTransition(geometry: geometry)
            } else {
                activeFrameGeometry = geometry
                needsLayout = true
            }
        }
    }

    func synchronizeRenderGeneration(_ generation: UInt64) {
        guard generation >= renderGeneration else { return }
        renderGeneration = generation
        frameSink.update(
            renderer: activeDisplayLayer.sampleBufferRenderer,
            generation: generation
        )
    }

    func prepareForSourceTransition(renderGeneration generation: UInt64) {
        guard generation >= renderGeneration else { return }
        renderGeneration = generation
        removeRetiringLayer()

        let oldLayer = activeDisplayLayer
        oldLayer.removeAllAnimations()
        let newLayer = Self.makeDisplayLayer()
        newLayer.opacity = 0
        layer?.addSublayer(newLayer)

        activeDisplayLayer = newLayer
        retiringDisplayLayer = oldLayer
        retiringFrameGeometry = activeFrameGeometry
        activeFrameGeometry = nil
        frameSink.update(
            renderer: newLayer.sampleBufferRenderer,
            generation: generation
        )
    }

    func clear(renderGeneration generation: UInt64) {
        guard generation >= renderGeneration else { return }
        renderGeneration = generation
        frameSink.update(
            renderer: activeDisplayLayer.sampleBufferRenderer,
            generation: generation
        )
        removeRetiringLayer()
        activeFrameGeometry = nil
        activeDisplayLayer.removeAllAnimations()
        activeDisplayLayer.opacity = 1
        activeDisplayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )
    }

    func clearForDismantle() {
        frameSink.clear()
        removeRetiringLayer()
        activeFrameGeometry = nil
        activeDisplayLayer.removeAllAnimations()
        activeDisplayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )
    }

    private func revealPreparedTransition(geometry: CaptureFrameGeometry) {
        guard let oldLayer = retiringDisplayLayer else {
            activeFrameGeometry = geometry
            needsLayout = true
            return
        }
        let newLayer = activeDisplayLayer
        let oldGeometry = retiringFrameGeometry
        let oldStartOpacity = oldLayer.presentation()?.opacity ?? oldLayer.opacity
        oldLayer.removeAllAnimations()
        activeFrameGeometry = geometry

        updateFrame(of: oldLayer, geometry: oldGeometry)
        updateFrame(of: newLayer, geometry: geometry)

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
                retiringDisplayLayer === oldLayer
            else { return }
            removeRetiringLayer()
        }
        newLayer.opacity = 1
        oldLayer.opacity = 0
        newLayer.add(newOpacity, forKey: "betterMeetsSourceIn")
        oldLayer.add(oldOpacity, forKey: "betterMeetsSourceOut")
        CATransaction.commit()
    }

    private func removeRetiringLayer() {
        guard let retiringDisplayLayer else { return }
        retiringDisplayLayer.removeAllAnimations()
        retiringDisplayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )
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
        displayLayer.backgroundColor = NSColor.clear.cgColor
        displayLayer.isOpaque = false
        return displayLayer
    }

    private static var transitionTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
    }
}
