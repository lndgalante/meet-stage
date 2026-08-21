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
                try await switchCapture(to: nextSelection)
                guard !Task.isCancelled, generation == selectionGeneration else { break }
                // A successful ScreenCaptureKit call confirms the filter, but
                // only the next complete buffer confirms visible output.
                awaitingLiveSelection = nextSelection
                scheduleFirstFrameTimeout(for: nextSelection.id)
            } catch {
                guard !Task.isCancelled, generation == selectionGeneration else { break }

                if awaitingLiveSelection?.id == nextSelection.id {
                    awaitingLiveSelection = nil
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

    func switchCapture(to source: WindowSource) async throws {
        isSwitchingStream = true
        handleAutoPresentationSourceChange()
        deactivateSpotlight()
        deactivateAnnotations(clearStrokes: true)
        clearClickPresentations()
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

        if let stream {
            let renderGeneration = renderer.prepareForSourceSwitch()
            do {
                try await stream.updateConfiguration(configuration)
                try await stream.updateContentFilter(filter)
                try Task.checkCancellation()
                guard self.stream === stream else {
                    throw CaptureLifecycleError.stoppedBeforeFirstFrame
                }
                renderer.commitSourceSwitch(generation: renderGeneration)
            } catch {
                renderer.cancelSourceSwitch(generation: renderGeneration)
                throw error
            }
            activeCaptureSource = source
            activeCaptureFormat = format
            capturesCursor = showsCursor
            stageAspectRatio = format.aspectRatio
            return
        }

        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: streamOutput
        )
        try newStream.addStreamOutput(
            streamOutput,
            type: .screen,
            sampleHandlerQueue: sampleQueue
        )
        renderer.beginCapture()
        stream = newStream

        do {
            try await newStream.startCapture()
        } catch {
            if stream === newStream {
                stream = nil
                renderer.clear()
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

        guard stream === newStream else {
            throw CaptureLifecycleError.stoppedBeforeFirstFrame
        }
        activeCaptureSource = source
        activeCaptureFormat = format
        capturesCursor = showsCursor
        stageAspectRatio = format.aspectRatio
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
