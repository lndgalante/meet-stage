import AppKit

extension CaptureManager {
    // MARK: - Focus and cursor capture

    func shouldCaptureCursor(for source: WindowSource) -> Bool {
        guard source.processIdentifier != 0,
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
        else {
            return false
        }
        return frontmostApplication.processIdentifier == source.processIdentifier
    }

    func handleApplicationActivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource else { return }
        let selectedSourceIsFocused =
            application.processIdentifier == source.processIdentifier
            && shouldCaptureCursor(for: source)
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
        let selectedSourceIsFocused = activeCaptureSource.map(shouldCaptureCursor(for:)) ?? false
        updatePresentationFocus(selectedSourceIsFocused)
    }

    func updatePresentationFocus(_ selectedSourceIsFocused: Bool) {
        desiredCursorVisibility = selectedSourceIsFocused
        if selectedSourceIsFocused {
            activateSpotlightIfPossible()
            activateAnnotationsIfPossible()
        } else {
            clearKeystrokePresentation()
            clearClickPresentations()
            deactivateSpotlight()
            deactivateAnnotations(clearStrokes: false)
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
            mouseClickMonitor = GlobalMouseClickMonitor { [weak self] location in
                self?.showMouseClick(at: location)
            }
        }
        mouseClickMonitor?.start()
    }

    func showMouseClick(at clickLocation: GlobalClickLocation) {
        guard let source = activeCaptureSource,
            selectedWindowID == source.id,
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: highlightsMouseClicks,
                selectedSourceIsFocused: shouldCaptureCursor(for: source)
            )
        else { return }

        let sourceFrame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        guard
            let normalizedLocation = ClickPresentationGeometry.normalizedLocation(
                for: clickLocation.quartzPoint,
                in: sourceFrame
            )
        else { return }

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
                try await Task.sleep(for: PresentationEffectTiming.clickDuration)
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

    func startSpotlightPointerMonitor() {
        if spotlightPointerMonitor == nil {
            spotlightPointerMonitor = GlobalPointerMonitor { [weak self] location in
                self?.moveSpotlight(to: location)
            }
        }
        spotlightPointerMonitor?.start()
    }

    func moveSpotlight(to globalLocation: CGPoint) {
        guard spotlightEnabled,
            let source = activeCaptureSource,
            selectedWindowID == source.id
        else { return }

        let sourceFrame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        guard
            let location = SpotlightGeometry.normalizedLocation(
                for: globalLocation,
                in: sourceFrame
            )
        else { return }

        spotlight.move(to: location)
    }

    func activateSpotlightIfPossible() {
        guard isSpotlightVisible,
            let source = activeCaptureSource,
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: true,
                selectedSourceIsFocused: shouldCaptureCursor(for: source)
            )
        else { return }

        sourceSpotlightPresenter.show(
            session: spotlight,
            sourceWindowID: source.id,
            fallbackSourceFrame: source.window.frame
        )
    }

    func focusSelectedSourceForSpotlightIfPossible() {
        guard isLive,
            let source = activeCaptureSource,
            !shouldCaptureCursor(for: source),
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
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: true,
                selectedSourceIsFocused: shouldCaptureCursor(for: source)
            )
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

    func focusSelectedSourceForAnnotationsIfPossible() {
        guard isLive,
            let source = activeCaptureSource,
            !shouldCaptureCursor(for: source),
            let application = NSRunningApplication(
                processIdentifier: source.processIdentifier
            )
        else { return }

        application.activate()
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
        let selectedSourceIsFocused = activeCaptureSource.map(shouldCaptureCursor(for:)) ?? false
        guard
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: highlightsKeystrokes,
                selectedSourceIsFocused: selectedSourceIsFocused
            )
        else { return }
        keystrokeDismissTask?.cancel()
        let presentation = KeystrokePresentation(
            label: label,
            size: keystrokeHighlightSize,
            appearance: keystrokeAppearance
        )
        keystrokePresentation = presentation
        keystrokeDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: PresentationEffectTiming.keystrokeDuration)
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
