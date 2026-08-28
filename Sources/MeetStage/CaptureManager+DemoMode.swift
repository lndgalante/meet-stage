import AppKit
import Foundation

extension CaptureManager {
    /// Rebuild cadence for the accessibility control index while listening.
    static let demoIndexInterval = Duration.milliseconds(1_500)
    /// Below this many accessibility controls, supplement the index with one
    /// text-recognition pass over the captured frame.
    static let demoOCRThreshold = 6
    /// Delay between showing a click highlight and performing the click, so the
    /// audience sees the target before the pointer arrives.
    static let demoClickLeadIn = Duration.milliseconds(450)

    struct DemoSourceContext {
        let pid: pid_t
        let windowID: CGWindowID
        let fallbackFrame: CGRect
    }

    // MARK: - Command

    func toggleDemoMode() {
        if demoModeEnabled {
            demoModeEnabled = false
            presentationStore.demoModeEnabled = false
            deactivateDemoMode()
            return
        }

        switch DemoSpeechTranscriber.microphoneAuthorization {
        case .authorized:
            enableDemoMode()
        case .notDetermined:
            // First time: the system permission dialog appears here.
            needsMicrophonePermission = true
            Task { [weak self] in
                let granted = await DemoSpeechTranscriber.requestMicrophoneAccess()
                guard let self else { return }
                needsMicrophonePermission = !granted
                if granted {
                    enableDemoMode()
                } else {
                    demoModeUnavailableReason =
                        "Demo Mode needs microphone access. Enable it in System Settings."
                }
            }
        default:
            // Denied or restricted: macOS will not prompt again, so send the
            // presenter straight to the Microphone settings pane.
            needsMicrophonePermission = true
            demoModeUnavailableReason =
                "Demo Mode needs microphone access. Enable it in System Settings."
            openMicrophoneSettings()
        }
    }

    private func enableDemoMode() {
        needsMicrophonePermission = false
        demoModeUnavailableReason = nil
        demoModeEnabled = true
        presentationStore.demoModeEnabled = true

        // Accessibility is a soft requirement: it enables richer control
        // discovery and clicking. Without it Demo Mode still highlights controls
        // found by text recognition.
        if !AccessibilityElementIndexer.isAccessibilityTrusted {
            AccessibilityElementIndexer.requestAccessibilityTrust()
        }

        focusSelectedSourceIfPossible()
        startDemoModeIfPossible()
    }

    func setDemoVoiceActions(_ value: DemoVoiceActions) {
        demoVoiceActions = value
        presentationStore.demoVoiceActions = value
    }

    func setDemoHighlightColor(_ value: PresentationColor) {
        demoHighlightColor = value
        presentationStore.demoHighlightColor = value
    }

    func setDemoZoomSize(_ value: PresentationSize) {
        demoZoomSize = value
        presentationStore.demoZoomSize = value
    }

    // MARK: - Activation

    /// Starts listening (and, if the source is focused, the visible surfaces).
    /// Listening is intentionally not gated on focus so the microphone stays
    /// warm while the presenter glances at BetterMeets; commands are ignored
    /// unless the source is focused.
    func startDemoModeIfPossible() {
        guard demoModeEnabled, isLive else { return }
        refreshAccessibilityTrust()
        startDemoListening()
        if isSelectedSourceFocused {
            activateDemoModeSurfaces()
        }
    }

    func activateDemoModeSurfaces() {
        guard demoModeEnabled, isLive, isSelectedSourceFocused,
            let source = activeCaptureSource
        else { return }

        sourceDemoOverlayPresenter.show(
            session: demoMode,
            sourceWindowID: source.id,
            fallbackSourceFrame: source.window.frame
        )
        startDemoIndexing()
    }

    /// Stops the visible surfaces and indexing on focus loss or source switch
    /// while keeping the microphone warm.
    func deactivateDemoModeSurfaces() {
        // Bump the generation so any in-flight AX rebuild or Vision merge is
        // discarded and can never resurrect a previous window's index.
        demoIndexGeneration += 1
        stopDemoIndexing()
        demoIndexWalkTask?.cancel()
        demoIndexWalkTask = nil
        sourceDemoOverlayPresenter.dismiss()
        demoActionTask?.cancel()
        demoActionTask = nil
        demoMode.clearVisuals()
        demoMode.elementIndex = .empty
        demoCommandGate.reset()
    }

    /// Fully stops Demo Mode (stop, source teardown, or toggle off).
    func deactivateDemoMode() {
        deactivateDemoModeSurfaces()
        stopDemoListening()
        // Release any demo-driven stage zoom (Auto Polish click zooms never set
        // an override, so this leaves them untouched).
        if autoPresentation.zoomScaleOverride != nil {
            autoPresentation.cancelZoom()
        }
        demoMode.reset()
    }

    private func startDemoListening() {
        guard demoSpeechTranscriber == nil else { return }
        let transcriber = DemoSpeechTranscriber()
        demoSpeechTranscriber = transcriber
        demoModeUnavailableReason = nil
        demoMode.setListening(true)

        demoListeningStartTask = Task { [weak self] in
            do {
                try await transcriber.start { [weak self] segment in
                    self?.handleDemoTranscript(segment)
                }
            } catch is CancellationError {
                // Superseded or torn down before start finished; nothing to do.
            } catch {
                // Always clean up the failed transcriber's resources first.
                await transcriber.stop()
                guard let self, demoSpeechTranscriber === transcriber else { return }
                handleDemoListeningFailure(error)
            }
        }
    }

    private func handleDemoListeningFailure(_ error: Error) {
        AppLog.demoMode.error(
            "Could not start listening: \(error.localizedDescription, privacy: .public)"
        )
        demoMode.setListening(false)
        demoSpeechTranscriber = nil

        switch error {
        case DemoSpeechError.microphoneDenied:
            needsMicrophonePermission = true
        case DemoSpeechError.localeUnsupported, DemoSpeechError.noCompatibleAudioFormat:
            // Deterministic: turning it back on will fail the same way, so
            // disable it and explain why rather than leaving a dead toggle.
            demoModeEnabled = false
            presentationStore.demoModeEnabled = false
            demoModeUnavailableReason =
                "Demo Mode isn’t available for your language or audio device."
        default:
            // Possibly transient (model download, engine hiccup); leave the
            // feature armed so a later focus regain retries, but surface it.
            demoModeUnavailableReason = "Demo Mode couldn’t start listening. Try again."
        }
    }

    private func stopDemoListening() {
        demoListeningStartTask?.cancel()
        demoListeningStartTask = nil
        guard let transcriber = demoSpeechTranscriber else { return }
        demoSpeechTranscriber = nil
        demoMode.setListening(false)
        Task { await transcriber.stop() }
    }

    // MARK: - Indexing

    private func startDemoIndexing() {
        demoIndexRefreshTask?.cancel()
        demoIndexRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.rebuildDemoIndex()
                do {
                    try await Task.sleep(for: CaptureManager.demoIndexInterval)
                } catch {
                    return
                }
                guard self?.demoModeEnabled == true else { return }
            }
        }
    }

    private func stopDemoIndexing() {
        demoIndexRefreshTask?.cancel()
        demoIndexRefreshTask = nil
        streamOutput.disarmAnalyzableFrame()
    }

    func rebuildDemoIndex() async {
        guard demoModeEnabled, isLive, isSelectedSourceFocused,
            let context = demoSourceContext(),
            demoIndexWalkTask == nil
        else { return }

        demoIndexGeneration += 1
        let generation = demoIndexGeneration
        let pid = context.pid
        let windowID = context.windowID
        let fallback = context.fallbackFrame

        let walkTask = Task.detached(priority: .utility) {
            let frame = WindowFrameResolver.currentFrame(for: windowID, fallback: fallback)
            return AccessibilityElementIndexer.index(
                pid: pid,
                sourceFrame: frame,
                generation: generation
            )
        }
        demoIndexWalkTask = walkTask
        let index = await withTaskCancellationHandler {
            await walkTask.value
        } onCancel: {
            walkTask.cancel()
        }

        // Only adopt the result if it is still for the same live, focused window.
        // A teardown bumps the generation and nils the walk task, so a stale
        // completion is dropped here without clobbering a newer rebuild.
        guard demoModeEnabled, demoIndexGeneration == generation,
            isSelectedSourceFocused,
            demoSourceContext()?.windowID == windowID
        else { return }
        demoIndexWalkTask = nil
        demoMode.elementIndex = index
        if index.elements.count < CaptureManager.demoOCRThreshold {
            streamOutput.armAnalyzableFrame()
        }
    }

    func handleDemoAnalyzableFrame(
        _ buffer: DemoImageBuffer,
        geometry: CaptureFrameGeometry
    ) {
        guard demoModeEnabled, isLive, isSelectedSourceFocused,
            let context = demoSourceContext()
        else { return }

        let generation = demoIndexGeneration
        let windowID = context.windowID
        let fallback = context.fallbackFrame

        Task { [weak self] in
            let frame = WindowFrameResolver.currentFrame(for: windowID, fallback: fallback)
            let recognized = await DemoTextRecognizer.recognize(
                buffer: buffer,
                geometry: geometry,
                sourceFrame: frame,
                generation: generation
            )
            guard let self else { return }
            guard demoModeEnabled, demoIndexGeneration == generation else { return }
            demoMode.elementIndex = CaptureManager.mergedIndex(
                current: demoMode.elementIndex,
                recognized: recognized
            )
        }
    }

    /// Merges recognized-text elements into the current index, dropping any that
    /// duplicate an existing control (by name or by overlapping position).
    static func mergedIndex(
        current: DemoElementIndex,
        recognized: DemoElementIndex
    ) -> DemoElementIndex {
        var elements = current.elements
        var nextID = (elements.map(\.id).max() ?? -1) + 1
        let existingLabels = Set(elements.compactMap { DemoText.normalize($0.label) })

        for candidate in recognized.elements {
            let normalizedLabel = DemoText.normalize(candidate.label)
            let center = candidate.screenCenter
            let isDuplicate =
                (normalizedLabel.map(existingLabels.contains) ?? false)
                || elements.contains { $0.screenFrame.contains(center) }
            guard !isDuplicate else { continue }

            elements.append(
                DemoElement(
                    id: nextID,
                    label: candidate.label,
                    role: candidate.role,
                    source: candidate.source,
                    normalizedBounds: candidate.normalizedBounds,
                    screenFrame: candidate.screenFrame,
                    pressable: candidate.pressable
                )
            )
            nextID += 1
        }
        return DemoElementIndex(generation: current.generation, elements: elements)
    }

    // MARK: - Transcript handling

    func handleDemoTranscript(_ segment: DemoTranscriptSegment) {
        guard demoModeEnabled, isLive, isSelectedSourceFocused, segment.isFinal else { return }

        guard
            let resolved = DemoIntentPolicy.resolve(
                transcript: segment.text,
                elements: demoMode.elementIndex.elements,
                voiceActions: demoVoiceActions
            )
        else { return }

        // Without Accessibility trust the click cannot fire, so present it
        // honestly as a highlight (this also dedups the gate on the real kind).
        let command =
            (resolved.kind == .click && !DemoActionExecutor.canSynthesizeInput)
            ? resolved.downgradedToHighlight
            : resolved

        let now = ProcessInfo.processInfo.systemUptime
        guard demoCommandGate.admit(command, at: now) else { return }
        executeDemoCommand(command)
    }

    private func executeDemoCommand(_ command: DemoResolvedCommand) {
        let presentation = DemoHighlightPresentation(
            bounds: command.element.normalizedBounds,
            color: demoHighlightColor,
            kind: command.kind
        )
        demoMode.showHighlight(presentation)
        autoPresentation.focus(
            on: command.element.normalizedCenter,
            zoomScale: demoZoomSize.autoZoomScale,
            hold: presentation.duration
        )
        demoMode.setCaption(
            command.kind == .click
                ? .clicking(command.element.label)
                : .highlighting(command.element.label)
        )
        AppLog.demoMode.notice(
            "Demo \(command.kind.rawValue, privacy: .public) command (score \(command.score, format: .fixed(precision: 2), privacy: .public))"
        )

        guard command.kind == .click, demoVoiceActions.allowsClicking,
            let context = demoSourceContext()
        else { return }
        // Actuation re-resolves the target from the live window frame after the
        // lead-in, so a moved window or a cancelled task never clicks stale
        // coordinates or the wrong window.
        let windowID = context.windowID
        let fallbackFrame = context.fallbackFrame
        let normalizedCenter = command.element.normalizedCenter
        demoActionTask?.cancel()
        demoActionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: CaptureManager.demoClickLeadIn)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            guard
                let target = resolveClickTarget(
                    windowID: windowID,
                    fallbackFrame: fallbackFrame,
                    normalizedCenter: normalizedCenter
                )
            else { return }
            await DemoActionExecutor.performClick(at: target)
            guard !Task.isCancelled else { return }
            // Navigation likely changed the UI; refresh the control index.
            await rebuildDemoIndex()
        }
    }

    /// Re-resolves the click point from the live window frame at actuation time,
    /// returning nil if Demo Mode is no longer live and focused on the same
    /// window, the window is gone, or the target lies off every display.
    private func resolveClickTarget(
        windowID: CGWindowID,
        fallbackFrame: CGRect,
        normalizedCenter: NormalizedWindowPoint
    ) -> CGPoint? {
        guard demoModeEnabled, isLive, isSelectedSourceFocused,
            demoSourceContext()?.windowID == windowID
        else { return nil }

        let frame = WindowFrameResolver.currentFrame(for: windowID, fallback: fallbackFrame)
        guard frame.width > 0, frame.height > 0 else { return nil }
        let target = CGPoint(
            x: frame.minX + normalizedCenter.x * frame.width,
            y: frame.minY + normalizedCenter.y * frame.height
        )
        guard DemoActionExecutor.isOnActiveDisplay(target) else {
            AppLog.demoMode.notice("Skipped Demo Mode click: target is off-screen")
            return nil
        }
        return target
    }

    /// True when clicking is selected but Accessibility trust is missing, so
    /// Demo Mode will highlight controls it can read but cannot open them.
    var demoModeNeedsClickAccessibility: Bool {
        demoModeEnabled
            && demoVoiceActions.allowsClicking
            && !isAccessibilityTrustedForDemo
    }

    /// Re-reads Accessibility trust and publishes any change so the badge and
    /// settings note update after the user grants access (which otherwise only
    /// takes effect on the next AX call, not automatically in the UI).
    func refreshAccessibilityTrust() {
        let trusted = AccessibilityElementIndexer.isAccessibilityTrusted
        if isAccessibilityTrustedForDemo != trusted {
            isAccessibilityTrustedForDemo = trusted
        }
    }

    func openMicrophoneSettings() {
        openPrivacySettings(pane: "Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        // Also fire the trust prompt; on a first, undecided state this is what
        // adds BetterMeets to the Accessibility list.
        AccessibilityElementIndexer.requestAccessibilityTrust()
        openPrivacySettings(pane: "Privacy_Accessibility")
    }

    private func openPrivacySettings(pane: String) {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Source context

    func demoSourceContext() -> DemoSourceContext? {
        guard let source = activeCaptureSource,
            selectedWindowID == source.id,
            source.processIdentifier > 0
        else { return nil }
        return DemoSourceContext(
            pid: source.processIdentifier,
            windowID: source.id,
            fallbackFrame: source.window.frame
        )
    }
}
