import AppKit
import ScreenCaptureKit

extension CaptureManager {
    // MARK: - Stream callbacks

    func handleFrame(from sourceStreamID: ObjectIdentifier, geometry: CaptureFrameGeometry) {
        guard let stream, ObjectIdentifier(stream) == sourceStreamID else { return }

        let contentAspectRatio = geometry.contentAspectRatio
        if abs(stageAspectRatio - contentAspectRatio) > 0.001 {
            stageAspectRatio = contentAspectRatio
        }

        if let liveSelection = awaitingLiveSelection {
            cancelFirstFrameTimeout()
            selectedWindowID = liveSelection.id
            awaitingLiveSelection = nil
            if pendingWindowID == liveSelection.id {
                pendingWindowID = nil
            }
        }

        if selectedWindowID != nil {
            state = pendingWindowID == nil ? .capturing : .switching
            if state == .capturing {
                activateAnnotationsIfPossible()
            }
        }
    }

    func handleStreamStopped(_ stoppedStreamID: ObjectIdentifier, error: Error) {
        guard let stream, ObjectIdentifier(stream) == stoppedStreamID else { return }

        self.stream = nil
        cancelFirstFrameTimeout()
        resetCursorTracking()
        awaitingLiveSelection = nil
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
        for source in sources {
            do {
                let thumbnail = try await WindowSourceDiscovery.thumbnail(for: source)
                guard let index = windows.firstIndex(where: { $0.id == source.id }) else {
                    continue
                }
                windows[index].thumbnail = thumbnail
            } catch {
                // A window can close during refresh. Its fallback remains useful
                // until the next source-list refresh removes it.
                AppLog.capture.debug(
                    "Could not update thumbnail for window \(source.id): \(error.localizedDescription, privacy: .public)"
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
            Set(shortcutWindowIDs.keys)
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
