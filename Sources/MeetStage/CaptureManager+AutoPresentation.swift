import AppKit

extension CaptureManager {
    func toggleAutoPresentation() {
        autoPresentationEnabled.toggle()
        if autoPresentationEnabled {
            updateMouseClickMonitoring()
            focusSelectedSourceIfPossible()
            activateAutoPresentationIfPossible()
        } else {
            autoPresentation.clear()
            updateMouseClickMonitoring()
            updatePresentationPointerMonitoring()
        }
        synchronizeDesiredCursorVisibility()
    }

    func activateAutoPresentationIfPossible() {
        guard
            autoPresentationEnabled,
            isLive,
            isSelectedSourceFocused
        else {
            autoPresentation.updatePointer(nil, zoomScale: autoZoomSize.autoZoomScale)
            updatePresentationPointerMonitoring()
            return
        }

        updatePresentationPointerMonitoring()
        if let pointer = CGEvent(source: nil)?.location {
            updatePresentationPointer(to: pointer)
        }
    }

    func handleAutoPresentationSourceChange() {
        presentationPointerMonitor?.stop()
        autoPresentation.clear()
    }

    func cancelAutoZoomForManualPresentation() {
        autoPresentation.cancelZoom()
    }

    func updateMouseClickMonitoring() {
        if highlightsMouseClicks || autoPresentationEnabled {
            startMouseClickMonitor()
        } else {
            mouseClickMonitor?.stop()
        }
    }

    func handlePresentationClick(at clickLocation: GlobalClickLocation) {
        guard
            let source = activeCaptureSource,
            selectedWindowID == source.id,
            isSelectedSourceFocused
        else { return }

        let sourceFrame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        guard
            let normalizedLocation = WindowCoordinateGeometry.normalizedPoint(
                inside: clickLocation.quartzPoint,
                sourceFrame: sourceFrame
            )
        else { return }

        if autoPresentationEnabled,
            !spotlightEnabled,
            !annotationsEnabled,
            !isAnnotating
        {
            autoPresentation.registerClick(
                at: normalizedLocation,
                zoomScale: autoZoomSize.autoZoomScale
            )
        }

        if highlightsMouseClicks {
            showMouseClick(
                at: clickLocation,
                normalizedLocation: normalizedLocation,
                sourceFrame: sourceFrame
            )
        }
    }

    func updatePresentationPointerMonitoring() {
        guard
            isLive,
            isSelectedSourceFocused,
            autoPresentationEnabled || spotlightEnabled
        else {
            presentationPointerMonitor?.stop()
            return
        }

        if presentationPointerMonitor == nil {
            presentationPointerMonitor = GlobalPointerMonitor(
                pointerMovements: { [weak self] location in
                    self?.updatePresentationPointer(to: location)
                }
            )
        }
        presentationPointerMonitor?.start()
    }

    func updatePresentationPointer(to globalLocation: CGPoint) {
        guard
            isLive,
            isSelectedSourceFocused,
            let source = activeCaptureSource,
            selectedWindowID == source.id
        else {
            if autoPresentationEnabled {
                autoPresentation.updatePointer(nil, zoomScale: autoZoomSize.autoZoomScale)
            }
            return
        }

        let sourceFrame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        let location = WindowCoordinateGeometry.normalizedPoint(
            inside: globalLocation,
            sourceFrame: sourceFrame
        )
        if autoPresentationEnabled {
            autoPresentation.updatePointer(
                location,
                zoomScale: autoZoomSize.autoZoomScale
            )
        }
        if spotlightEnabled, let location {
            spotlight.move(to: location)
        }
    }

    func setStageFrameStyle(_ value: StageFrameStyle) {
        stageFrameStyle = value
        presentationStore.stageFrameStyle = value
    }

    func setStageFramePadding(_ value: Double) {
        let value = clamped(value, to: StageFrameAppearance.paddingRange)
        stageFramePadding = value
        presentationStore.stageFramePadding = value
    }

    func setStageFrameCornerRadius(_ value: Double) {
        let value = clamped(value, to: StageFrameAppearance.cornerRadiusRange)
        stageFrameCornerRadius = value
        presentationStore.stageFrameCornerRadius = value
    }

    func setStageFrameBlur(_ value: Double) {
        let value = clamped(value, to: StageFrameAppearance.blurRange)
        stageFrameBlur = value
        presentationStore.stageFrameBlur = value
    }

    func setStageFrameShadow(_ value: Double) {
        let value = clamped(value, to: StageFrameAppearance.shadowRange)
        stageFrameShadow = value
        presentationStore.stageFrameShadow = value
    }

    func setAutoZoomSize(_ value: PresentationSize) {
        autoZoomSize = value
        presentationStore.autoZoomSize = value
    }

    @discardableResult
    func setStageLogoData(_ data: Data) -> Bool {
        guard
            data.count <= StageLogoAppearance.maximumDataSize,
            let image = NSImage(data: data),
            image.isValid
        else { return false }

        stageLogo = image
        presentationStore.stageLogoData = data
        return true
    }

    func removeStageLogo() {
        stageLogo = nil
        presentationStore.stageLogoData = nil
    }

    private func clamped(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
