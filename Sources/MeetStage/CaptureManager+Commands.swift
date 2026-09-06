import AppKit

extension CaptureManager {
    // MARK: - Capture commands

    func select(_ source: WindowSource) {
        guard windows.contains(where: { $0.id == source.id }) else {
            AppLog.capture.warning(
                "Ignoring selection for unavailable window \(source.id)"
            )
            NSSound.beep()
            return
        }

        if CaptureSelectionPolicy.action(
            for: source.id,
            selectedWindowID: selectedWindowID,
            state: state
        ) == .pause {
            pauseCapture()
            return
        }

        pendingSelection = source
        cancelFirstFrameTimeout()
        pendingWindowID = source.id
        state = .switching

        guard selectionTask == nil else { return }
        startSelectionTask()
    }

    func pauseCapture() {
        guard isLive else { return }
        endCapture(preservingSelection: true)
    }

    func stopCapture() {
        endCapture(preservingSelection: false)
    }

    func endCapture(preservingSelection: Bool) {
        cancelFirstFrameTimeout()
        pendingSelection = nil
        awaitingLiveSelection = nil
        awaitingLiveSelectionRenderGeneration = nil
        liveRenderGeneration = nil
        pendingWindowID = nil
        selectionGeneration += 1
        selectionTask?.cancel()
        selectionTask = nil

        let streamToStop = stream
        self.stream = nil
        resetCursorTracking()
        if !preservingSelection {
            selectedWindowID = nil
        }
        state = preservingSelection && selectedWindowID != nil ? .paused : .idle
        clearKeystrokePresentation()
        renderer.clear()

        guard let streamToStop else { return }
        Task {
            do {
                try await streamToStop.stopCapture()
            } catch  where stream == nil && (state == .idle || state == .paused) {
                let message = Self.friendlyMessage(for: error)
                AppLog.capture.error(
                    "Could not stop capture: \(message, privacy: .public)"
                )
                state = .failed(message)
            } catch {
                // A newer stream owns the UI; an old stream's stop error is stale.
                AppLog.capture.debug(
                    "Ignoring stale stream stop failure: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Shortcuts

    func shortcut(for source: WindowSource) -> Int? {
        shortcutWindowIDs.first(where: { $0.value == source.id })?.key
    }

    func shortcutOwnerDescription(for slot: Int) -> String? {
        if let pin = shortcutPins[slot] {
            return pin.description
        }
        guard let windowID = shortcutWindowIDs[slot],
            let source = windows.first(where: { $0.id == windowID })
        else {
            return nil
        }
        return "\(source.applicationName) — \(source.title)"
    }

    func pin(_ source: WindowSource, to slot: Int) {
        guard ShortcutSlot.isValid(slot) else { return }

        let identity = PinnedWindow(source: source)
        shortcutExclusions.remove(identity)
        let duplicateSlots = shortcutPins.compactMap { entry -> Int? in
            let resolvesToSource = shortcutWindowIDs[entry.key] == source.id
            return resolvesToSource || entry.value == identity ? entry.key : nil
        }
        for duplicateSlot in duplicateSlots where duplicateSlot != slot {
            shortcutPins.removeValue(forKey: duplicateSlot)
            resolvedPinnedWindowIDs.removeValue(forKey: duplicateSlot)
        }

        shortcutPins[slot] = identity
        resolvedPinnedWindowIDs.removeValue(forKey: slot)
        persistShortcutPins()
        persistShortcutExclusions()
        reconcileShortcuts(with: windows)
    }

    func unpin(_ source: WindowSource) {
        let identity = PinnedWindow(source: source)
        let slots = shortcutPins.compactMap { entry -> Int? in
            shortcutWindowIDs[entry.key] == source.id || entry.value == identity ? entry.key : nil
        }
        for slot in slots {
            shortcutPins.removeValue(forKey: slot)
            resolvedPinnedWindowIDs.removeValue(forKey: slot)
        }
        shortcutExclusions.insert(identity)
        persistShortcutPins()
        persistShortcutExclusions()
        reconcileShortcuts(with: windows)
    }

    func activateShortcut(_ slot: Int) {
        guard !unavailableShortcutSlots.contains(slot) else {
            AppLog.shortcuts.warning(
                "Shortcut \(self.globalShortcutModifier.spokenName(for: slot), privacy: .public) is reserved by another application"
            )
            NSSound.beep()
            return
        }
        guard let windowID = shortcutWindowIDs[slot],
            let source = windows.first(where: { $0.id == windowID })
        else {
            if let pin = shortcutPins[slot] {
                AppLog.shortcuts.notice(
                    "Shortcut \(self.globalShortcutModifier.spokenName(for: slot), privacy: .public) is waiting for \(pin.description, privacy: .private)"
                )
                NSSound.beep()
            }
            return
        }
        select(source)
    }

    var globalShortcutsEnabled: Bool { globalShortcutModifier != .disabled }

    var preferredShortcutModifier: GlobalShortcutModifier {
        shortcutStore.loadEnabledShortcutModifier()
    }

    func setGlobalShortcutsEnabled(_ enabled: Bool) {
        setGlobalShortcutModifier(enabled ? preferredShortcutModifier : .disabled)
    }

    func setGlobalShortcutModifier(_ modifier: GlobalShortcutModifier) {
        guard globalShortcutModifier != modifier else { return }
        globalShortcutModifier = modifier
        shortcutStore.saveGlobalShortcutModifier(modifier)
        refreshHotKeyRegistrations()
    }

    // MARK: - Presentation commands and preferences

    func toggleSpotlight() {
        cancelAutoZoomForManualPresentation()
        // The presenter is taking manual control; relinquish any voice-spotlight
        // ownership so its auto-dismiss can't turn this off.
        demoSpotlightGeneration += 1
        demoSpotlightTask?.cancel()
        demoSpotlightTask = nil
        spotlightEnabled.toggle()
        if spotlightEnabled {
            focusSelectedSourceIfPossible()
            activateSpotlightIfPossible()
            updatePresentationPointerMonitoring()
            if let currentPointerLocation = CGEvent(source: nil)?.location {
                updatePresentationPointer(to: currentPointerLocation)
            }
        } else {
            deactivateSpotlight()
            updatePresentationPointerMonitoring()
        }
    }

    func toggleMouseClickHighlighting() {
        highlightsMouseClicks.toggle()
        presentationStore.highlightsMouseClicks = highlightsMouseClicks
        updateMouseClickMonitoring()
        if !highlightsMouseClicks {
            clearClickPresentations()
        }
    }

    func toggleAnnotations() {
        cancelAutoZoomForManualPresentation()
        annotationsEnabled.toggle()
        if annotationsEnabled {
            focusSelectedSourceIfPossible()
            activateAnnotationsIfPossible()
        } else {
            deactivateAnnotations(clearStrokes: true)
        }
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        let snapshot = annotations.snapshot()
        annotations.clear()
        annotations.registerUndo(
            restoring: snapshot,
            with: annotationUndoManager,
            actionName: "Clear Annotations",
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    func finishAnnotations() {
        guard annotationsEnabled || isAnnotating else { return }
        annotationsEnabled = false
        deactivateAnnotations(clearStrokes: true)
    }

    func setAnnotationLifetimeSeconds(_ value: Int) {
        let normalizedValue = AnnotationTiming.normalizedLifetimeSeconds(value)
        annotationLifetimeSeconds = normalizedValue
        annotations.setLifetimeSeconds(normalizedValue)
        presentationStore.annotationLifetimeSeconds = normalizedValue
    }

    func setAnnotationColor(_ value: PresentationColor) {
        annotationColor = value
        annotations.setInkColor(value)
        presentationStore.annotationColor = value
    }

    func setSpotlightSize(_ value: PresentationSize) {
        spotlightSize = value
        spotlight.setSize(value)
        presentationStore.spotlightSize = value
    }

    func setSpotlightOutsideOpacity(_ value: Double) {
        let normalizedValue = SpotlightAppearance.normalizedOutsideOpacity(value)
        spotlightOutsideOpacity = normalizedValue
        spotlight.setOutsideOpacity(normalizedValue)
        presentationStore.spotlightOutsideOpacity = normalizedValue
    }

    func setClickHighlightColor(_ value: PresentationColor) {
        clickHighlightColor = value
        presentationStore.clickHighlightColor = value
    }

    func setClickHighlightSize(_ value: PresentationSize) {
        clickHighlightSize = value
        presentationStore.clickHighlightSize = value
    }

    func setKeystrokeHighlightSize(_ value: PresentationSize) {
        keystrokeHighlightSize = value
        presentationStore.keystrokeHighlightSize = value
    }

    func setKeystrokeAppearance(_ value: KeystrokeAppearance) {
        keystrokeAppearance = value
        presentationStore.keystrokeAppearance = value
    }

    func toggleKeystrokeHighlighting() {
        if highlightsKeystrokes {
            highlightsKeystrokes = false
            needsKeystrokeAccessibilityPermission = false
            presentationStore.highlightsKeystrokes = false
            keystrokeMonitor?.stop()
            clearKeystrokePresentation()
            return
        }

        guard GlobalKeystrokeMonitor.hasAccessibilityPermission else {
            needsKeystrokeAccessibilityPermission = true
            GlobalKeystrokeMonitor.requestAccessibilityPermission()
            return
        }

        needsKeystrokeAccessibilityPermission = false
        highlightsKeystrokes = true
        presentationStore.highlightsKeystrokes = true
        startKeystrokeMonitor()
    }

    // MARK: - Application actions

    func openScreenRecordingSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    func restartApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let message = "Could not restart BetterMeets: \(error.localizedDescription)"
            AppLog.application.error("\(message, privacy: .public)")
            state = .failed(message)
        }
    }
}
