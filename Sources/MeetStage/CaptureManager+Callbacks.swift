import AppKit
import MeetStageCore
import ScreenCaptureKit

extension CaptureManager {
    // MARK: - Stream callbacks

    func handleFrame(from sourceStreamID: ObjectIdentifier, frame: RenderedCaptureFrame) {
        guard let stream, ObjectIdentifier(stream) == sourceStreamID else { return }

        if awaitingLiveSelection != nil {
            guard
                CaptureFrameAcceptancePolicy.confirmsSelection(
                    expectedGeneration: awaitingLiveSelectionRenderGeneration,
                    frameGeneration: frame.renderGeneration
                )
            else { return }
        } else {
            guard liveRenderGeneration == frame.renderGeneration else { return }
        }

        let contentAspectRatio = frame.geometry.contentAspectRatio
        if abs(stageAspectRatio - contentAspectRatio) > 0.001 {
            stageAspectRatio = contentAspectRatio
        }

        if let liveSelection = awaitingLiveSelection {
            cancelFirstFrameTimeout()
            selectedWindowID = liveSelection.id
            awaitingLiveSelection = nil
            awaitingLiveSelectionRenderGeneration = nil
            liveRenderGeneration = frame.renderGeneration
            if pendingWindowID == liveSelection.id {
                pendingWindowID = nil
            }
        }

        guard selectedWindowID != nil else { return }
        let nextState: CaptureState = pendingWindowID == nil ? .capturing : .switching
        guard state != nextState else { return }

        state = nextState
        if nextState == .capturing {
            activateSpotlightIfPossible()
            activateAnnotationsIfPossible()
            activateAutoPresentationIfPossible()
            startDemoModeIfPossible()
        }
    }

    func handleStreamStopped(_ stoppedStreamID: ObjectIdentifier, error: Error) {
        guard let stream, ObjectIdentifier(stream) == stoppedStreamID else { return }

        self.stream = nil
        cancelFirstFrameTimeout()
        resetCursorTracking()
        awaitingLiveSelection = nil
        awaitingLiveSelectionRenderGeneration = nil
        liveRenderGeneration = nil
        pendingSelection = nil
        pendingWindowID = nil
        selectedWindowID = nil
        selectionGeneration += 1
        selectionTask?.cancel()
        selectionTask = nil
        renderer.clear()

        let message = Self.friendlyMessage(for: error)
        AppLog.capture.error("Capture stream stopped: \(message, privacy: .public)")
        state = .failed(message)
    }

    // MARK: - Thumbnails and shortcut reconciliation

    func loadThumbnails(for sources: [WindowSource]) async {
        let results = await thumbnailLoader.load(for: sources)
        for result in results {
            if let image = result.image,
                let index = windows.firstIndex(where: { $0.id == result.windowID })
            {
                windows[index].thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            } else if let errorDescription = result.errorDescription {
                // A window can close during refresh. Its fallback remains useful
                // until the next source-list refresh removes it.
                AppLog.capture.debug(
                    "Could not update thumbnail for window \(result.windowID): \(errorDescription, privacy: .public)"
                )
            }
        }
    }

    func reconcileShortcuts(with sources: [WindowSource]) {
        let resolution = ShortcutAssignmentPolicy.resolve(
            candidates: sources.map(ShortcutCandidate.init(source:)),
            pins: shortcutPins,
            exclusions: shortcutExclusions,
            previousAssignments: shortcutWindowIDs,
            previousPinnedAssignments: resolvedPinnedWindowIDs
        )
        let pinsChanged = resolution.pins != shortcutPins

        shortcutPins = resolution.pins
        shortcutWindowIDs = resolution.assignments
        resolvedPinnedWindowIDs = resolution.pinnedAssignments
        if pinsChanged {
            persistShortcutPins()
        }
        refreshHotKeyRegistrations()
    }

    func refreshHotKeyRegistrations() {
        unavailableShortcutSlots = hotKeyManager.updateRegisteredSlots(
            Set(shortcutWindowIDs.keys),
            modifier: globalShortcutModifier
        )
        if !unavailableShortcutSlots.isEmpty {
            let slots = unavailableShortcutSlots.sorted().map(String.init).joined(separator: ", ")
            AppLog.shortcuts.warning(
                "Could not register shortcut slots: \(slots, privacy: .public)"
            )
        }
    }

    func persistShortcutPins() {
        shortcutStore.savePins(shortcutPins)
    }

    func persistShortcutExclusions() {
        shortcutStore.saveExclusions(shortcutExclusions)
    }

    // MARK: - Error presentation

    static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain
            || nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
        {
            return "Screen capture stopped (\(nsError.code)): \(nsError.localizedDescription)"
        }
        return error.localizedDescription
    }
}
