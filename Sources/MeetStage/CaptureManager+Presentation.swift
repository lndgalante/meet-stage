import AppKit

extension CaptureManager {
    // MARK: - Focus and cursor capture

    func isSourceApplicationFocused(_ source: WindowSource) -> Bool {
        guard source.processIdentifier != 0,
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
        else {
            return false
        }
        return frontmostApplication.processIdentifier == source.processIdentifier
    }

    func shouldCaptureCursor(for source: WindowSource) -> Bool {
        isSourceApplicationFocused(source) && !autoPresentationEnabled
    }

    func handleApplicationActivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource else { return }
        let selectedSourceIsFocused =
            application.processIdentifier == source.processIdentifier
            && isSourceApplicationFocused(source)
        updatePresentationFocus(selectedSourceIsFocused)
    }

    func handleApplicationDeactivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource,
            application.processIdentifier == source.processIdentifier
        else { return }
        updatePresentationFocus(false)
    }

    func synchronizeDesiredCursorVisibility() {
        updatePresentationFocus(isSelectedSourceFocused)
    }

    var isSelectedSourceFocused: Bool {
        activeCaptureSource.map(isSourceApplicationFocused) ?? false
    }

    func updatePresentationFocus(_ selectedSourceIsFocused: Bool) {
        desiredCursorVisibility = selectedSourceIsFocused && !autoPresentationEnabled
        if selectedSourceIsFocused {
            activateSpotlightIfPossible()
            activateAnnotationsIfPossible()
            activateAutoPresentationIfPossible()
        } else {
            presentationPointerMonitor?.stop()
            clearKeystrokePresentation()
            clearClickPresentations()
            deactivateSpotlight()
            deactivateAnnotations(clearStrokes: false)
            autoPresentation.updatePointer(nil, zoomScale: autoZoomSize.autoZoomScale)
            autoPresentation.cancelZoom()
        }
        scheduleCaptureConfigurationUpdateIfNeeded()
    }

    func scheduleCaptureConfigurationUpdateIfNeeded() {
        guard !isSwitchingStream,
            stream != nil,
            activeCaptureSource != nil,
            activeCaptureFormat != nil,
            capturesCursor != desiredCursorVisibility,
            captureConfigurationUpdateTask == nil
        else { return }

        captureConfigurationUpdateTask = Task { [weak self] in
            await self?.applyCaptureConfigurationUpdate()
        }
    }

    func applyCaptureConfigurationUpdate() async {
        guard !Task.isCancelled,
            let targetStream = stream,
            let source = activeCaptureSource,
            let format = activeCaptureFormat
        else {
            captureConfigurationUpdateTask = nil
            return
        }

        let requestedCursorVisibility = desiredCursorVisibility
        let configuration = makeStreamConfiguration(
            for: format,
            showsCursor: requestedCursorVisibility
        )

        do {
            try await targetStream.updateConfiguration(configuration)
            guard stream === targetStream,
                activeCaptureSource?.id == source.id
            else {
                captureConfigurationUpdateTask = nil
                return
            }

            capturesCursor = requestedCursorVisibility
            captureConfigurationUpdateTask = nil
            scheduleCaptureConfigurationUpdateIfNeeded()
        } catch {
            captureConfigurationUpdateTask = nil
            guard !Task.isCancelled, stream === targetStream else { return }
            AppLog.capture.error(
                "Could not update cursor capture: \(Self.friendlyMessage(for: error), privacy: .public)"
            )
        }
    }

    func resetCursorTracking() {
        handleAutoPresentationSourceChange()
        cancelFirstFrameTimeout()
        captureConfigurationUpdateTask?.cancel()
        captureConfigurationUpdateTask = nil
        activeCaptureSource = nil
        activeCaptureFormat = nil
        capturesCursor = false
        desiredCursorVisibility = false
        clearKeystrokePresentation()
        clearClickPresentations()
        deactivateSpotlight()
        deactivateAnnotations(clearStrokes: true)
        isSwitchingStream = false
    }

    // MARK: - Presentation monitoring

    func startMouseClickMonitor() {
        if mouseClickMonitor == nil {
            mouseClickMonitor = GlobalMouseClickMonitor(mouseClicks: { [weak self] location in
                self?.handlePresentationClick(at: location)
            })
        }
        mouseClickMonitor?.start()
    }

    func showMouseClick(
        at clickLocation: GlobalClickLocation,
        normalizedLocation: NormalizedWindowPoint,
        sourceFrame: CGRect
    ) {
        let presentation = ClickPresentation(
            location: normalizedLocation,
            color: clickHighlightColor,
            size: clickHighlightSize
        )
        clickPresentations.append(presentation)
        sourceClickRipplePresenter.show(
            presentation,
            sourceFrame: sourceFrame,
            clickLocation: clickLocation
        )

        clickDismissTasks[presentation.id]?.cancel()
        clickDismissTasks[presentation.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: ClickPresentation.duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissClickPresentation(presentation.id)
        }
    }

    func dismissClickPresentation(_ id: UUID) {
        clickDismissTasks[id]?.cancel()
        clickDismissTasks[id] = nil
        clickPresentations.removeAll { $0.id == id }
    }

    func clearClickPresentations() {
        clickDismissTasks.values.forEach { $0.cancel() }
        clickDismissTasks.removeAll()
        clickPresentations.removeAll()
        sourceClickRipplePresenter.dismissAll()
    }

    func activateSpotlightIfPossible() {
        guard isSpotlightVisible,
            let source = activeCaptureSource,
            isSelectedSourceFocused
        else { return }

        sourceSpotlightPresenter.show(
            session: spotlight,
            sourceWindowID: source.id,
            fallbackSourceFrame: source.window.frame
        )
        updatePresentationPointerMonitoring()
    }

    func focusSelectedSourceIfPossible() {
        guard isLive,
            let source = activeCaptureSource,
            !isSourceApplicationFocused(source),
            let application = NSRunningApplication(
                processIdentifier: source.processIdentifier
            )
        else { return }

        application.activate()
    }

    func deactivateSpotlight() {
        sourceSpotlightPresenter.dismiss()
    }

    func activateAnnotationsIfPossible() {
        guard annotationsEnabled,
            !isAnnotating,
            isLive,
            let source = activeCaptureSource,
            isSelectedSourceFocused
        else { return }

        isAnnotating = true
        sourceAnnotationPresenter.show(
            session: annotations,
            sourceWindowID: source.id,
            fallbackSourceFrame: source.window.frame,
            onFinish: { [weak self] in
                self?.finishAnnotations()
            }
        )
    }

    func deactivateAnnotations(clearStrokes: Bool) {
        isAnnotating = false
        sourceAnnotationPresenter.dismiss()
        if clearStrokes {
            annotations.clear()
        }
    }

    func startKeystrokeMonitor() {
        if keystrokeMonitor == nil {
            keystrokeMonitor = GlobalKeystrokeMonitor { [weak self] label in
                self?.showKeystroke(label)
            }
        }
        keystrokeMonitor?.start()
    }

    func showKeystroke(_ label: String) {
        guard highlightsKeystrokes, isSelectedSourceFocused else { return }
        keystrokeDismissTask?.cancel()
        let presentation = KeystrokePresentation(
            label: label,
            size: keystrokeHighlightSize,
            appearance: keystrokeAppearance
        )
        keystrokePresentation = presentation
        keystrokeDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: KeystrokePresentation.duration)
            } catch {
                return
            }
            guard !Task.isCancelled,
                self?.keystrokePresentation?.id == presentation.id
            else { return }
            self?.keystrokePresentation = nil
            self?.keystrokeDismissTask = nil
        }
    }

    func clearKeystrokePresentation() {
        keystrokeDismissTask?.cancel()
        keystrokeDismissTask = nil
        keystrokePresentation = nil
    }
}
