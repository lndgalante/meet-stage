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

        // Report on-device model status so you can verify Apple Intelligence is
        // downloaded and ready (visible in the log stream).
        if DemoModelIntentResolver.isAvailable {
            AppLog.demoMode.notice("On-device conversational model: available")
        } else {
            AppLog.demoMode.notice(
                "On-device conversational model: unavailable (\(DemoModelIntentResolver.unavailableReason ?? "unknown", privacy: .public))"
            )
        }
        let brainStatus = hasDemoBrainKey ? "configured" : "no API key"
        AppLog.demoMode.notice(
            "Conversational brain (\(self.demoBrainProvider.label, privacy: .public)): \(brainStatus, privacy: .public)"
        )

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

    func setDemoSmartUnderstanding(_ value: Bool) {
        demoSmartUnderstanding = value
        presentationStore.demoSmartUnderstanding = value
    }

    func setDemoCloudConsented(_ value: Bool) {
        if !value {
            cancelDemoBrainRequest()
        }
        demoCloudConsented = value
        presentationStore.demoCloudConsented = value
    }

    /// Switches which cloud model the brain uses, and refreshes the key state so
    /// the UI reflects whether the newly selected provider has a key.
    func setDemoBrainProvider(_ value: DemoBrainProvider) {
        guard demoBrainProvider != value else { return }
        cancelDemoBrainRequest()
        demoBrainProvider = value
        presentationStore.demoBrainProvider = value
        // Consent names a concrete third-party recipient in Settings. Switching
        // vendors requires a fresh opt-in instead of carrying consent across.
        demoCloudConsented = false
        presentationStore.demoCloudConsented = false
        hasDemoBrainKey = value.keyStore.hasKey
    }

    /// Saves (or clears) the API key for the currently selected provider, in that
    /// provider's Keychain item — never the app bundle.
    func setDemoBrainKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = demoBrainProvider
        cancelDemoBrainRequest()
        guard provider.keyStore.save(trimmed) else {
            hasDemoBrainKey = provider.keyStore.hasKey
            demoModeUnavailableReason =
                "BetterMeets couldn’t update the \(provider.vendor) key in Keychain."
            return
        }
        // Prime (or clear) the in-memory cache from the value we just have in hand,
        // so this session never reads the Keychain back and never prompts for it.
        cachedBrainKeys[provider] = trimmed.isEmpty ? nil : trimmed
        hasDemoBrainKey = provider.keyStore.hasKey
        if trimmed.isEmpty {
            setDemoCloudConsented(false)
        }
        demoModeUnavailableReason = nil
    }

    /// The selected provider's key. Cached in memory after the first read (or the
    /// save that primed it), so a voice command never re-reads the Keychain secret
    /// and never re-triggers the "wants to access key" prompt within a session.
    var currentBrainKey: String? {
        if let cached = cachedBrainKeys[demoBrainProvider] { return cached }
        let key = demoBrainProvider.keyStore.key
        if let key { cachedBrainKeys[demoBrainProvider] = key }
        return key
    }

    /// Cancels and invalidates the current cloud request. Cancellation stops the
    /// URLSession work in the common case; the generation also prevents a response
    /// that raced cancellation from affecting UI or synthesizing input.
    func cancelDemoBrainRequest() {
        demoBrainGeneration += 1
        demoBrainTask?.cancel()
        demoBrainTask = nil
        if demoMode.isListening, demoMode.caption?.status == .thinking {
            demoMode.setCaption(.listening)
        }
    }

    /// Whether any smarter-understanding tier is available. On-device embeddings
    /// ship with the OS, so this is effectively always true; Apple Intelligence
    /// adds the conversational (pronoun) tier on top when present.
    var isDemoSmartUnderstandingAvailable: Bool {
        demoEmbeddingMatcher.isAvailable || DemoModelIntentResolver.isAvailable
    }

    /// Whether the conversational (Apple Intelligence) tier is present, on top of
    /// the always-available semantic tier.
    var isDemoConversationalTierAvailable: Bool {
        DemoModelIntentResolver.isAvailable
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
        sourceDemoOverlayPresenter.dismiss()
        demoActionTask?.cancel()
        demoActionTask = nil
        demoModelTask?.cancel()
        demoModelTask = nil
        cancelDemoBrainRequest()
        // Clear a still-active voice spotlight (we own it only while its task
        // is live; a manual toggle nils the task and takes ownership).
        if let task = demoSpotlightTask {
            task.cancel()
            demoSpotlightTask = nil
            demoSpotlightGeneration += 1
            if spotlightEnabled {
                spotlightEnabled = false
                deactivateSpotlight()
                updatePresentationPointerMonitoring()
            }
        }
        demoModelResolver.reset()
        demoEmbeddingMatcher.reset()
        demoConversation.reset()
        lastReferencedControl = nil
        demoMode.clearVisuals()
        demoMode.elementIndex = .empty
        demoCommandGate.reset()
        demoBrainRequestGate.reset()
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
        demoIndexWalkTask?.cancel()
        demoIndexWalkTask = nil
        demoRecognitionGeneration &+= 1
        demoRecognitionTask?.cancel()
        demoRecognitionTask = nil
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
            let context = demoSourceContext(),
            demoRecognitionTask == nil
        else { return }

        let generation = demoIndexGeneration
        demoRecognitionGeneration &+= 1
        let recognitionGeneration = demoRecognitionGeneration
        let windowID = context.windowID
        let fallback = context.fallbackFrame

        demoRecognitionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if demoRecognitionGeneration == recognitionGeneration {
                    demoRecognitionTask = nil
                }
            }
            let frame = WindowFrameResolver.currentFrame(for: windowID, fallback: fallback)
            let recognized = await DemoTextRecognizer.recognize(
                buffer: buffer,
                geometry: geometry,
                sourceFrame: frame,
                generation: generation
            )
            guard !Task.isCancelled,
                demoModeEnabled,
                demoIndexGeneration == generation
            else { return }
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
        guard demoSmartUnderstanding, looksLikeDemoCommand(segment.text) else { return }

        // Brain-first: with a key configured AND the presenter's consent to send
        // a screenshot to the selected provider, the conversational vision model
        // is the SINGLE authority — no deterministic matcher runs ahead of it.
        // Without consent (or a key) it falls through to the on-device tiers.
        if hasDemoBrainKey, demoCloudConsented {
            resolveWithBrain(transcript: segment.text)
            return
        }

        let elements = demoMode.elementIndex.elements
        if let resolved = DemoIntentPolicy.resolve(
            transcript: segment.text,
            elements: elements,
            voiceActions: demoVoiceActions
        ) {
            dispatchDemoCommand(resolved, transcript: segment.text)
            return
        }
        if let command = resolveWithEmbeddings(transcript: segment.text, elements: elements) {
            dispatchDemoCommand(command, transcript: segment.text)
            return
        }
        guard DemoModelIntentResolver.isAvailable else { return }
        resolveWithModel(transcript: segment.text, elements: elements)
    }

    /// Semantic target match plus verb-based intent, both on device.
    private func resolveWithEmbeddings(
        transcript: String,
        elements: [DemoElement]
    ) -> DemoResolvedCommand? {
        let labels = orderedUniqueLabels(from: elements)
        guard !labels.isEmpty,
            let match = demoEmbeddingMatcher.bestMatch(transcript: transcript, labels: labels),
            let element = elements.first(where: { $0.label == match.label })
        else { return nil }

        let tokens = DemoText.tokenizeTranscript(transcript).tokens
        let wantsClick =
            DemoIntentPolicy.utteranceRequestsClick(tokens)
            && demoVoiceActions.allowsClicking
            && element.pressable
        return DemoResolvedCommand(
            kind: wantsClick ? .click : .highlight,
            element: element,
            matchedPhrase: match.label,
            score: match.similarity
        )
    }

    /// Broad set of command-signal words. A cheap pre-filter so the brain runs
    /// on plausible commands, not on every narrated sentence — deliberately
    /// generous (natural phrasing), since the brain itself returns "none" for
    /// anything that isn't actually a command.
    private static let demoCommandSignals: Set<String> = [
        // action / navigation verbs
        "click", "clicks", "clicking", "press", "pressing", "tap", "tapping",
        "open", "opens", "opening", "select", "selecting", "choose", "choosing",
        "explore", "show", "shows", "showing", "find", "check", "look", "looking",
        "view", "see", "go", "goes", "going", "take", "takes", "navigate", "visit",
        "scroll", "close", "closes", "closing", "expand", "collapse", "hit",
        "activate", "launch", "pick", "toggle", "switch", "enter", "type",
        // pronouns / deictics
        "it", "that", "this", "these", "those", "there", "here", "back", "one"
    ]

    private func looksLikeDemoCommand(_ transcript: String) -> Bool {
        let tokens = Set(DemoText.tokenizeTranscript(transcript).tokens)
        guard !tokens.isEmpty else { return false }
        return !tokens.isDisjoint(with: Self.demoCommandSignals)
            || !tokens.isDisjoint(with: DemoIntentPolicy.controlNouns)
    }

    private func resolveWithModel(transcript: String, elements: [DemoElement]) {
        let controls = uniqueModelControls(from: elements)
        guard !controls.isEmpty else { return }
        let generation = demoIndexGeneration
        let lastControl = lastReferencedControl
        let voiceActions = demoVoiceActions

        demoModelTask?.cancel()
        demoModelTask = Task { [weak self] in
            guard let self else { return }
            let result = await demoModelResolver.resolve(
                transcript: transcript,
                controls: controls,
                lastReferencedControl: lastControl
            )
            guard !Task.isCancelled, let result,
                demoModeEnabled, isLive, isSelectedSourceFocused,
                demoIndexGeneration == generation,
                let element = demoMode.elementIndex.elements.first(where: {
                    $0.label == result.label
                })
            else { return }

            // The model may propose a click; apply the same click-eligibility
            // rules the deterministic policy enforces.
            let proposedKind: DemoIntentKind =
                (result.kind == .click && voiceActions.allowsClicking && element.pressable)
                ? .click : .highlight
            let kind = DemoModelActuationPolicy.authorize(
                proposedKind,
                transcript: transcript
            )
            dispatchDemoCommand(
                DemoResolvedCommand(
                    kind: kind,
                    element: element,
                    matchedPhrase: result.label,
                    score: 1
                ),
                transcript: transcript
            )
        }
    }

    private func orderedUniqueLabels(from elements: [DemoElement]) -> [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for element in elements where seen.insert(element.label).inserted {
            labels.append(element.label)
        }
        return labels
    }

    private func uniqueModelControls(from elements: [DemoElement]) -> [DemoModelControl] {
        var seen = Set<String>()
        var controls: [DemoModelControl] = []
        for element in elements where seen.insert(element.label).inserted {
            controls.append(
                DemoModelControl(label: element.label, role: element.role.spokenNoun)
            )
        }
        return controls
    }

    /// Shared dispatch for every tier: downgrade a click the app can't perform,
    /// debounce, then run it.
    func dispatchDemoCommand(_ resolved: DemoResolvedCommand, transcript: String) {
        // Without Accessibility trust the click cannot fire, so present it
        // honestly as a highlight (this also dedups the gate on the real kind).
        let command =
            (resolved.kind == .click && !DemoActionExecutor.canSynthesizeInput)
            ? resolved.downgradedToHighlight
            : resolved

        let now = ProcessInfo.processInfo.systemUptime
        guard demoCommandGate.admit(command, at: now) else { return }
        executeDemoCommand(command, transcript: transcript)
    }

    private func executeDemoCommand(_ command: DemoResolvedCommand, transcript: String) {
        // Remember the target so the next turn can resolve a later "it".
        lastReferencedControl = command.element.label
        demoConversation.record(
            user: transcript,
            assistant: (command.kind == .click ? "clicked " : "highlighted ") + command.element.label
        )

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
            await DemoActionExecutor.performClick(
                at: target,
                isStillValid: demoActuationValidator(windowID: windowID)
            )
            guard !Task.isCancelled else { return }
            // The click likely navigated: the target is gone, so remove its ring
            // and release the zoom instead of leaving them over the new screen.
            demoMode.clearHighlights()
            if autoPresentation.zoomScaleOverride != nil {
                autoPresentation.cancelZoom()
            }
            // Refresh the control index for the new screen.
            await rebuildDemoIndex()
        }
    }

    /// A validity check the input executor re-runs at each actuation boundary
    /// (before a press, and periodically while typing) so a mid-action focus or
    /// window change aborts before input lands in the wrong app.
    func demoActuationValidator(windowID: CGWindowID) -> DemoActionExecutor.ValidityCheck {
        { [weak self] in
            await self?.isDemoActuationValid(windowID: windowID) ?? false
        }
    }

    func isDemoActuationValid(windowID: CGWindowID) -> Bool {
        demoModeEnabled && isLive && isSelectedSourceFocused
            && demoSourceContext()?.windowID == windowID
    }

    /// Re-resolves the click point from the live window frame at actuation time,
    /// returning nil if Demo Mode is no longer live and focused on the same
    /// window, the window is gone, or the target lies off every display.
    func resolveClickTarget(
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
