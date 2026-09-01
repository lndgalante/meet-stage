import AppKit
import Foundation

/// The cloud conversational-brain pipeline for Demo Mode: it takes a spoken
/// command, sends the screenshot + control inventory + dialogue to the selected
/// brain (`demoBrain`), and routes the returned action to a highlight/click, a
/// typed field, or an on-demand BetterMeets effect (circle/spotlight/zoom). The
/// offline deterministic/embedding/on-device tiers live in `CaptureManager+DemoMode`;
/// this file owns only the cloud path so that coordinator stays under a healthy size.
extension CaptureManager {
    /// Cloud conversational tier: screenshot + inventory + dialogue → brain →
    /// exact element snap (or a vision-coordinate fallback).
    func resolveWithBrain(transcript: String) {
        guard let source = activeCaptureSource else { return }
        guard let apiKey = currentBrainKey else {
            AppLog.demoMode.error("Demo brain: no API key found")
            return
        }
        // Drop the transcriber's re-emitted duplicate final so we don't pay for a
        // second identical vision call within a short window.
        let now = ProcessInfo.processInfo.systemUptime
        if transcript == lastBrainTranscript, now - lastBrainTranscriptAt < 2 {
            return
        }
        lastBrainTranscript = transcript
        lastBrainTranscriptAt = now

        // Snapshot the index we send so the brain's element id resolves against
        // the exact list it saw — ids are not stable across the 1.5s rebuilds.
        let windowID = source.id
        let elementsSnapshot = demoMode.elementIndex.elements
        let controls = uniqueBrainControls(from: elementsSnapshot)
        let history = demoConversation.turns
        let allowsClicking = demoVoiceActions.allowsClicking

        AppLog.demoMode.notice(
            "Demo brain path for \"\(transcript, privacy: .private)\" (\(controls.count, privacy: .public) controls)"
        )
        // Show the presenter that async work is happening (the ~1.5s call).
        demoMode.setCaption(.thinking)
        demoBrainTask?.cancel()
        demoBrainTask = Task { [weak self] in
            guard let self else { return }
            let capture = await DemoWindowScreenshot.capture(source: source)
            AppLog.demoMode.notice(
                "Demo brain screenshot: \(capture != nil ? "captured" : "none", privacy: .public)"
            )
            // A superseded call (a newer utterance cancelled this one) must not
            // touch the caption the new call now owns.
            if Task.isCancelled { return }
            // Gate on the window, not the index generation: routine rebuilds bump
            // the generation during the ~1.5s call and would drop every result.
            guard demoModeEnabled, isLive, isSelectedSourceFocused,
                demoSourceContext()?.windowID == windowID
            else {
                endDemoThinking()
                return
            }

            let request = DemoBrainRequest(
                apiKey: apiKey,
                transcript: transcript,
                history: history,
                controls: controls,
                imageJPEGBase64: capture?.base64JPEG,
                imagePixelSize: capture?.pixelSize ?? .zero,
                allowsClicking: allowsClicking
            )
            let decision: DemoBrainDecision?
            do {
                decision = try await demoBrain.decide(request)
            } catch {
                if !Task.isCancelled { surfaceDemoBrainError(error) }
                return
            }
            if Task.isCancelled { return }
            guard let decision,
                demoModeEnabled, isLive, isSelectedSourceFocused,
                demoSourceContext()?.windowID == windowID
            else {
                endDemoThinking()
                return
            }
            executeBrainDecision(
                decision,
                elements: elementsSnapshot,
                imagePixelSize: capture?.pixelSize ?? .zero,
                transcript: transcript
            )
        }
    }

    /// Routes a resolved brain decision to the matching action: highlight/click
    /// (input), type (input), or a visual effect (circle/spotlight/zoom).
    private func executeBrainDecision(
        _ decision: DemoBrainDecision,
        elements: [DemoElement],
        imagePixelSize: CGSize,
        transcript: String
    ) {
        guard
            let element = resolveBrainElement(
                from: decision,
                elements: elements,
                imagePixelSize: imagePixelSize
            )
        else {
            endDemoThinking()
            return
        }
        AppLog.demoMode.notice(
            "Demo brain resolved \(decision.action.rawValue, privacy: .public) → \(element.label, privacy: .private)"
        )

        // A type without Accessibility trust cannot enter text, so present it as
        // an honest highlight instead of a "Typing…" pill that silently no-ops.
        var action = decision.action
        if action == .type, !DemoActionExecutor.canSynthesizeInput {
            action = .highlight
        }

        // highlight/click carry their debounce inside dispatchDemoCommand (shared
        // with the offline tiers). The effect actions are gated here so a
        // re-emitted final segment can't re-run a paid call or type text twice.
        switch action {
        case .none:
            endDemoThinking()
        case .highlight, .click:
            dispatchDemoCommand(
                DemoResolvedCommand(
                    kind: action == .click ? .click : .highlight,
                    element: element,
                    matchedPhrase: decision.label.isEmpty ? element.label : decision.label,
                    score: 1
                ),
                transcript: transcript
            )
        case .type, .circle, .spotlight, .zoom:
            let now = ProcessInfo.processInfo.systemUptime
            guard demoCommandGate.admit(label: element.label, action: action.rawValue, at: now)
            else {
                endDemoThinking()
                return
            }
            switch action {
            case .type:
                guard let text = decision.text else {
                    endDemoThinking()
                    return
                }
                executeTypeCommand(element: element, text: text, transcript: transcript)
            case .circle:
                executeCircleCommand(element: element, transcript: transcript)
            case .spotlight:
                executeSpotlightCommand(element: element, transcript: transcript)
            default:
                executeZoomCommand(element: element, transcript: transcript)
            }
        }
    }

    /// Returns the caption to "Listening" after a brain call that produced no
    /// action (so the "Thinking…" pill never gets stuck).
    private func endDemoThinking() {
        guard demoMode.isListening, demoMode.caption?.status == .thinking else { return }
        demoMode.setCaption(.listening)
    }

    /// Surfaces a brain failure to the presenter instead of a silent no-op: a
    /// transient error blips the caption, a persistent one (bad key) is held on
    /// the control tooltip so a whole session doesn't fail silently.
    private func surfaceDemoBrainError(_ error: Error) {
        let brainError = error as? DemoBrainError
        AppLog.demoMode.error(
            "Demo brain failed: \(brainError?.userMessage ?? error.localizedDescription, privacy: .public)"
        )
        if case let .http(status, detail) = brainError {
            // The provider's error envelope is server-generated (no user data or
            // key), so log it publicly — it's what pinpoints quota vs auth vs param.
            AppLog.demoMode.error(
                "Demo brain HTTP \(status, privacy: .public) body: \(detail, privacy: .public)"
            )
        }
        let message = brainError?.userMessage ?? "Assistant unreachable"
        demoMode.setCaption(.acting(symbol: "exclamationmark.triangle.fill", text: message))
        if brainError?.isPersistent == true {
            demoModeUnavailableReason = message
        }
    }

    /// Resolves a brain decision to a target element: an exact element by id, or
    /// a synthetic target at the returned image coordinate (for unlisted controls).
    private func resolveBrainElement(
        from decision: DemoBrainDecision,
        elements: [DemoElement],
        imagePixelSize: CGSize
    ) -> DemoElement? {
        if let id = decision.elementID,
            let element = elements.first(where: { $0.id == id })
        {
            return element
        }
        guard let point = decision.point,
            imagePixelSize.width > 0, imagePixelSize.height > 0,
            let source = activeCaptureSource
        else { return nil }

        let normalizedX = min(max(point.x / imagePixelSize.width, 0), 1)
        let normalizedY = min(max(point.y / imagePixelSize.height, 0), 1)
        let frame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        let halfWidth = 0.06
        let halfHeight = 0.035
        let bounds = NormalizedAnnotationBounds(
            minX: max(normalizedX - halfWidth, 0),
            minY: max(normalizedY - halfHeight, 0),
            width: halfWidth * 2,
            height: halfHeight * 2
        )
        let screenFrame = CGRect(
            x: frame.minX + (normalizedX - halfWidth) * frame.width,
            y: frame.minY + (normalizedY - halfHeight) * frame.height,
            width: halfWidth * 2 * frame.width,
            height: halfHeight * 2 * frame.height
        )
        return DemoElement(
            id: -1,
            label: decision.label.isEmpty ? "control" : decision.label,
            role: .other,
            source: .recognizedText,
            normalizedBounds: bounds,
            screenFrame: screenFrame,
            pressable: true
        )
    }

    // MARK: - Effect actions (typing + on-demand BetterMeets effects)

    private func executeTypeCommand(element: DemoElement, text: String, transcript: String) {
        lastReferencedControl = element.label
        demoConversation.record(user: transcript, assistant: "typed \"\(text)\" into \(element.label)")
        demoMode.setCaption(.acting(symbol: "keyboard", text: "Typing…"))
        demoMode.showHighlight(
            DemoHighlightPresentation(
                bounds: element.normalizedBounds,
                color: demoHighlightColor,
                kind: .click
            )
        )
        guard demoVoiceActions.allowsClicking, let context = demoSourceContext() else { return }

        let windowID = context.windowID
        let pid = context.pid
        let fallbackFrame = context.fallbackFrame
        let normalizedCenter = element.normalizedCenter
        demoActionTask?.cancel()
        demoActionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: CaptureManager.demoClickLeadIn)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                let target = resolveClickTarget(
                    windowID: windowID,
                    fallbackFrame: fallbackFrame,
                    normalizedCenter: normalizedCenter
                )
            else { return }
            await DemoActionExecutor.performType(
                text,
                at: target,
                pid: pid,
                isStillValid: demoActuationValidator(windowID: windowID)
            )
            guard !Task.isCancelled else { return }
            demoMode.clearHighlights()
            await rebuildDemoIndex()
        }
    }

    private func executeCircleCommand(element: DemoElement, transcript: String) {
        lastReferencedControl = element.label
        demoConversation.record(user: transcript, assistant: "circled \(element.label)")
        demoMode.setCaption(.acting(symbol: "circle.dashed", text: "Circling \(element.label)"))

        guard let source = activeCaptureSource else { return }
        let frame = WindowFrameResolver.currentFrame(for: source.id, fallback: source.window.frame)
        let minDimension = max(min(frame.width, frame.height), 1)
        let widthPixels = element.normalizedBounds.width * frame.width
        let heightPixels = element.normalizedBounds.height * frame.height
        let diameter = (max(widthPixels, heightPixels) * 1.5 + 28) / minDimension
        annotations.addShape(
            .circle(center: element.normalizedCenter, diameter: diameter),
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    /// How long a voice-triggered spotlight stays before clearing itself.
    static let demoSpotlightHold = Duration.seconds(4)

    private func executeSpotlightCommand(element: DemoElement, transcript: String) {
        lastReferencedControl = element.label
        demoConversation.record(user: transcript, assistant: "spotlighted \(element.label)")
        demoMode.setCaption(.acting(symbol: "magnifyingglass", text: "Spotlighting \(element.label)"))

        spotlight.move(to: element.normalizedCenter)

        // If the presenter already has the spotlight on, just move it and leave it
        // under their control. Otherwise show it pinned to the element (no pointer
        // following) and auto-dismiss after a few seconds — a momentary "look here".
        guard !spotlightEnabled else { return }
        spotlightEnabled = true
        demoSpotlightGeneration += 1
        let generation = demoSpotlightGeneration
        if let source = activeCaptureSource, isSelectedSourceFocused {
            sourceSpotlightPresenter.show(
                session: spotlight,
                sourceWindowID: source.id,
                fallbackSourceFrame: source.window.frame
            )
        }

        demoSpotlightTask?.cancel()
        demoSpotlightTask = Task { [weak self] in
            do {
                try await Task.sleep(for: CaptureManager.demoSpotlightHold)
            } catch {
                return
            }
            guard let self else { return }
            demoSpotlightTask = nil
            // Only dismiss the spotlight WE armed; a manual toggle in the meantime
            // bumps the generation and takes ownership.
            guard !Task.isCancelled, spotlightEnabled,
                demoSpotlightGeneration == generation
            else { return }
            spotlightEnabled = false
            deactivateSpotlight()
            updatePresentationPointerMonitoring()
        }
    }

    private func executeZoomCommand(element: DemoElement, transcript: String) {
        lastReferencedControl = element.label
        demoConversation.record(user: transcript, assistant: "zoomed to \(element.label)")
        demoMode.setCaption(.acting(symbol: "plus.magnifyingglass", text: "Zooming to \(element.label)"))
        autoPresentation.focus(
            on: element.normalizedCenter,
            zoomScale: demoZoomSize.autoZoomScale,
            hold: .seconds(4)
        )
    }

    // MARK: - Control inventory

    /// Maximum controls to send — bounds tokens; the screenshot covers the rest.
    private static let demoBrainControlLimit = 70

    private func uniqueBrainControls(from elements: [DemoElement]) -> [DemoBrainControl] {
        var seenLabels = Set<String>()
        var controls: [DemoBrainControl] = []
        for element in elements {
            guard !isNoiseLabel(element.label) else { continue }
            let normalized = DemoText.normalize(element.label) ?? element.label.lowercased()
            guard seenLabels.insert(normalized).inserted else { continue }
            controls.append(
                DemoBrainControl(
                    id: element.id,
                    label: element.label,
                    role: element.role.spokenNoun
                )
            )
            if controls.count >= Self.demoBrainControlLimit { break }
        }
        return controls
    }

    /// Pure-data fragments (amounts, percentages, hex addresses, image paths)
    /// that the accessibility/OCR index sweeps up but that are never targets by
    /// name — the vision model still sees them in the screenshot.
    private func isNoiseLabel(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if !trimmed.contains(where: { $0.isLetter }) { return true }  // numbers, %, $, punctuation
        if trimmed.hasPrefix("0x") { return true }  // hex addresses
        if trimmed.hasPrefix("/") || trimmed.contains(".png") || trimmed.contains(".jpg") {
            return true  // image paths
        }
        return false
    }
}
