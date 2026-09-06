import AppKit
import ScreenCaptureKit

extension CaptureManager {
    // MARK: - Window discovery

    func startWindowMonitoring() {
        if workspaceMonitor == nil {
            workspaceMonitor = WorkspaceMonitor(
                onApplicationActivated: { [weak self] application in
                    self?.handleApplicationActivation(application)
                },
                onApplicationDeactivated: { [weak self] application in
                    self?.handleApplicationDeactivation(application)
                },
                onSourceListChanged: { [weak self] in
                    self?.refreshWindowsAutomatically()
                }
            )
        }
        guard windowMonitoringTask == nil else { return }

        windowMonitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.refreshWindowsAutomatically()
            }
        }
    }

    func refreshWindows() {
        requestWindowRefresh(isManual: true)
    }

    func refreshWindowsAutomatically() {
        requestWindowRefresh(isManual: false)
    }

    func requestWindowRefresh(isManual: Bool) {
        guard screenRecordingAuthorization.isAuthorized else {
            windows = []
            reconcileShortcuts(with: [])
            state = .permissionRequired

            return
        }

        guard windowRefreshTask == nil else {
            if isManual {
                queuedManualRefresh = true
                isRefreshing = true
            }
            return
        }

        if isManual {
            isRefreshing = true
            if stream == nil && selectionTask == nil && state != .paused {
                state = .loading
            }
        }

        windowRefreshTask = Task { [weak self] in
            await self?.performWindowRefresh(isManual: isManual)
        }
    }

    func requestScreenRecordingPermission() {
        if screenRecordingAuthorization.isAuthorized {
            refreshWindows()
        } else if !requestedPermissionThisLaunch {
            requestedPermissionThisLaunch = true
            if screenRecordingAuthorization.requestAccess() {
                refreshWindows()
            }
        } else {
            openScreenRecordingSettings()
        }
    }

    func performWindowRefresh(isManual: Bool) async {
        defer {
            windowRefreshTask = nil
            if isManual {
                isRefreshing = false
            }

            if queuedManualRefresh {
                queuedManualRefresh = false
                refreshWindows()
            }
        }

        do {
            let existingWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
            let candidates = try await WindowSourceDiscovery.discover(
                reusing: existingWindows
            )

            windows = candidates
            reconcileShortcuts(with: candidates)

            if state == .paused,
                let selectedWindowID,
                !candidates.contains(where: { $0.id == selectedWindowID })
            {
                self.selectedWindowID = nil
            }

            if stream == nil {
                if selectionTask != nil {
                    state = .switching
                } else if state == .paused, selectedWindowID != nil {
                    state = .paused
                } else {
                    state = .idle
                }
            } else if pendingWindowID == nil, selectedWindowID != nil {
                state = .capturing
            }

            handleUnavailableCaptureSources(in: candidates)

            let sourcesNeedingThumbnails =
                isManual
                ? candidates
                : candidates.filter { $0.thumbnail == nil }
            await loadThumbnails(for: sourcesNeedingThumbnails)
        } catch {
            let message = Self.friendlyMessage(for: error)
            AppLog.capture.error(
                "Window discovery failed: \(message, privacy: .public)"
            )
            if isManual, stream == nil {
                state = .failed(message)
            }
        }
    }
}
