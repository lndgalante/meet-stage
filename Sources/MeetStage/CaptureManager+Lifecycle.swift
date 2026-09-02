import AppKit
import CoreMedia
import ScreenCaptureKit

extension CaptureManager {
    // MARK: - Capture lifecycle

    func startSelectionTask() {
        selectionGeneration += 1
        let generation = selectionGeneration
        selectionTask = Task { [weak self] in
            await self?.processPendingSelections(generation: generation)
        }
    }

    func processPendingSelections(generation: Int) async {
        while !Task.isCancelled,
            generation == selectionGeneration,
            let nextSelection = pendingSelection
        {
            pendingSelection = nil
            state = .switching

            do {
                let renderGeneration = try await switchCapture(to: nextSelection)
                guard !Task.isCancelled, generation == selectionGeneration else { break }
                // Starting the source-specific stream confirms capture setup,
                // but only its next complete buffer confirms visible output.
                awaitingLiveSelection = nextSelection
                awaitingLiveSelectionRenderGeneration = renderGeneration
                scheduleFirstFrameTimeout(for: nextSelection.id)
            } catch {
                guard !Task.isCancelled, generation == selectionGeneration else { break }

                if awaitingLiveSelection?.id == nextSelection.id {
                    awaitingLiveSelection = nil
                    awaitingLiveSelectionRenderGeneration = nil
                }
                let message = Self.friendlyMessage(for: error)
                AppLog.capture.error(
                    "Could not switch to window \(nextSelection.id): \(message, privacy: .public)"
                )

                if pendingSelection == nil {
                    pendingWindowID = nil
                    state = isLive ? .capturing : .failed(message)
                }
            }
        }

        guard generation == selectionGeneration else { return }
        selectionTask = nil
    }

    func scheduleFirstFrameTimeout(for sourceID: CGWindowID) {
        cancelFirstFrameTimeout()
        firstFrameTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.firstFrameTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.recoverFromUnavailableSelection(sourceID: sourceID)
        }
    }

    func cancelFirstFrameTimeout() {
        firstFrameTimeoutTask?.cancel()
        firstFrameTimeoutTask = nil
    }

    func handleUnavailableCaptureSources(in sources: [WindowSource]) {
        let availableWindowIDs = sources.map(\.id)

        if let awaitingSourceID = awaitingLiveSelection?.id,
            pendingWindowID == awaitingSourceID,
            selectionTask == nil,
            !availableWindowIDs.contains(awaitingSourceID)
        {
            recoverFromUnavailableSelection(sourceID: awaitingSourceID)
            return
        }

        if let selectedWindowID,
            stream != nil,
            pendingWindowID == nil,
            !availableWindowIDs.contains(selectedWindowID)
        {
            failUnavailableSelection()
        }
    }

    func recoverFromUnavailableSelection(sourceID: CGWindowID) {
        guard awaitingLiveSelection?.id == sourceID,
            pendingWindowID == sourceID
        else { return }

        cancelFirstFrameTimeout()
        awaitingLiveSelection = nil
        awaitingLiveSelectionRenderGeneration = nil
        pendingWindowID = nil

        let recoveryAction = UnavailableSelectionRecoveryPolicy.action(
            failedSourceID: sourceID,
            selectedWindowID: selectedWindowID,
            availableWindowIDs: windows.map(\.id)
        )

        switch recoveryAction {
        case let .restore(windowID):
            guard let source = windows.first(where: { $0.id == windowID }) else {
                failUnavailableSelection()
                return
            }
            pendingSelection = source
            pendingWindowID = source.id
            state = .switching
            guard selectionTask == nil else { return }
            startSelectionTask()

        case .fail:
            failUnavailableSelection()
        }
    }

    func failUnavailableSelection() {
        endCapture(preservingSelection: false)
        AppLog.capture.error("\(Self.unavailableSourceMessage, privacy: .public)")
        state = .failed(Self.unavailableSourceMessage)
    }

    func switchCapture(to source: WindowSource) async throws -> UInt64 {
        isSwitchingStream = true
        handleAutoPresentationSourceChange()
        deactivateSpotlight()
        deactivateAnnotations(clearStrokes: true)
        clearClickPresentations()
        deactivateDemoModeSurfaces()
        defer {
            isSwitchingStream = false
            synchronizeDesiredCursorVisibility()
        }
        if let captureConfigurationUpdateTask {
            captureConfigurationUpdateTask.cancel()
            await captureConfigurationUpdateTask.value
            self.captureConfigurationUpdateTask = nil
        }
        try Task.checkCancellation()

        let filter = SCContentFilter(desktopIndependentWindow: source.window)
        let format = StageWindowSizing.captureFormat(for: filter)
        let showsCursor = shouldCaptureCursor(for: source)
        let configuration = makeStreamConfiguration(
            for: format,
            showsCursor: showsCursor
        )

        let previousStream = stream
        let renderGeneration =
            previousStream == nil
            ? renderer.beginCapture()
            : renderer.prepareForSourceSwitch()

        // A running SCStream doesn't attach the selected window ID to its
        // sample buffers, and updateContentFilter doesn't document a buffer
        // boundary. Recreate the stream so the callback's stream identity is
        // itself proof of the selected source. Suppression plus the serial-queue
        // barrier ensures no callback from the retired stream can be displayed
        // under the new render generation.
        if let previousStream {
            stream = nil
            do {
                try await previousStream.stopCapture()
                do {
                    try previousStream.removeStreamOutput(streamOutput, type: .screen)
                } catch {
                    AppLog.capture.debug(
                        "Could not detach output from retired stream: \(error.localizedDescription, privacy: .public)"
                    )
                }
                await drainSampleQueue()
                try Task.checkCancellation()
            } catch {
                renderer.clear()
                liveRenderGeneration = nil
                throw error
            }
        }

        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: streamOutput
        )
        do {
            try newStream.addStreamOutput(
                streamOutput,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
            stream = newStream
            try await newStream.startCapture()
            try Task.checkCancellation()
            guard stream === newStream else {
                throw CaptureLifecycleError.stoppedBeforeFirstFrame
            }
            if previousStream != nil {
                renderer.commitSourceSwitch(generation: renderGeneration)
            }
        } catch {
            if stream === newStream {
                stream = nil
            }
            renderer.clear()
            do {
                try await newStream.stopCapture()
            } catch {
                AppLog.capture.debug(
                    "Could not stop failed replacement stream: \(error.localizedDescription, privacy: .public)"
                )
            }
            do {
                try newStream.removeStreamOutput(streamOutput, type: .screen)
            } catch {
                AppLog.capture.debug(
                    "Could not detach output from failed stream: \(error.localizedDescription, privacy: .public)"
                )
            }
            throw error
        }

        activeCaptureSource = source
        activeCaptureFormat = format
        capturesCursor = showsCursor
        stageAspectRatio = format.aspectRatio
        return renderGeneration
    }

    /// Drains callbacks already queued for a retired stream while rendering is
    /// suppressed. The replacement stream isn't created until this serial-queue
    /// barrier completes, so its callbacks have an unambiguous source identity.
    private func drainSampleQueue() async {
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                continuation.resume()
            }
        }
    }

    func makeStreamConfiguration(
        for format: StageCaptureFormat,
        showsCursor: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = format.width
        configuration.height = format.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureResolution = .best
        configuration.showsCursor = showsCursor
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.backgroundColor = Self.transparentBackground
        configuration.shouldBeOpaque = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = "BetterMeets — Demo Stage"
        return configuration
    }
}

private enum CaptureLifecycleError: LocalizedError {
    case stoppedBeforeFirstFrame

    var errorDescription: String? {
        "Screen capture stopped before it produced a frame."
    }
}
