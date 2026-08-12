import AppKit
import CoreMedia
import ScreenCaptureKit

@MainActor
final class CaptureManager: ObservableObject {
    // SCStreamConfiguration.backgroundColor is an unretained CGColorRef. Keep
    // this object alive while ScreenCaptureKit copies stream configurations.
    private static let blackBackground = CGColor(gray: 0, alpha: 1)
    // Keep this legacy key stable so rebranding never discards user-pinned shortcuts.
    private static let shortcutDefaultsKey = "MeetStage.shortcutPins.v1"
    private static let shortcutExclusionsDefaultsKey = "MeetStage.shortcutExclusions.v1"

    @Published private(set) var windows: [WindowSource] = []
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var pendingWindowID: CGWindowID?
    @Published private(set) var selectedWindowDescription = "Nothing selected"
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var shortcutWindowIDs: [Int: CGWindowID] = [:]
    @Published private(set) var unavailableShortcutSlots: Set<Int> = []
    @Published private(set) var stageAspectRatio: CGFloat
    @Published private var shortcutPins: [Int: PinnedWindow] = [:]
    @Published private var shortcutExclusions: Set<PinnedWindow> = []

    let renderer = SampleBufferRenderer()

    private let defaults: UserDefaults
    private let sampleQueue = DispatchQueue(
        label: "dev.poc.meetstage.screen-frames",
        qos: .userInteractive
    )
    private lazy var streamOutput = CaptureStreamOutput(
        renderer: renderer,
        onFrame: { [weak self] sourceStream, geometry in
            Task { @MainActor in
                self?.handleFrame(from: sourceStream, geometry: geometry)
            }
        },
        onFailure: { [weak self] sourceStream, error in
            Task { @MainActor in
                self?.handleStreamStopped(sourceStream, error: error)
            }
        }
    )
    private lazy var hotKeyManager = GlobalHotKeyManager { [weak self] slot in
        self?.activateShortcut(slot)
    }

    private var stream: SCStream?
    private var activeCaptureSource: WindowSource?
    private var activeCaptureFormat: StageCaptureFormat?
    private var capturesCursor = false
    private var desiredCursorVisibility = false
    private var isSwitchingStream = false
    private var cursorVisibilityUpdateTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var windowMonitoringTask: Task<Void, Never>?
    private var windowRefreshTask: Task<Void, Never>?
    private var queuedManualRefresh = false
    private var awaitingLiveSelection: WindowSource?
    private var pendingSelection: WindowSource?
    private var selectionTask: Task<Void, Never>?
    private var selectionGeneration = 0
    private var requestedPermissionThisLaunch = false
    private var resolvedPinnedWindowIDs: [Int: CGWindowID] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stageAspectRatio = StageWindowSizing.currentScreenAspectRatio()
        shortcutPins = Self.loadShortcutPins(from: defaults)
        shortcutExclusions = Self.loadShortcutExclusions(from: defaults)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.handleApplicationActivation(application)
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.handleApplicationDeactivation(application)
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowsAutomatically()
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowsAutomatically()
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didHideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowsAutomatically()
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowsAutomatically()
                }
            }
        ]
    }

    deinit {
        cursorVisibilityUpdateTask?.cancel()
        windowMonitoringTask?.cancel()
        windowRefreshTask?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var isCapturing: Bool {
        stream != nil
    }

    var isLive: Bool {
        stream != nil && selectedWindowID != nil
    }

    var needsScreenRecordingPermission: Bool {
        state == .permissionRequired
    }

    var displayedWindows: [WindowSource] {
        let slotByWindowID = Dictionary(
            uniqueKeysWithValues: shortcutWindowIDs.map { ($0.value, $0.key) }
        )
        return windows.enumerated()
            .sorted { first, second in
                let firstSlot = slotByWindowID[first.element.id]
                let secondSlot = slotByWindowID[second.element.id]

                switch (firstSlot, secondSlot) {
                case let (left?, right?):
                    return left == right ? first.offset < second.offset : left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return first.offset < second.offset
                }
            }
            .map(\.element)
    }

    var pinnedShortcuts: [ShortcutPin] {
        shortcutPins
            .map { ShortcutPin(slot: $0.key, window: $0.value) }
            .sorted { $0.slot < $1.slot }
    }

    var controllerNotice: String? {
        var details: [String] = []
        if let errorMessage, !errorMessage.isEmpty {
            details.append(errorMessage)
        }

        let unresolvedSlots = Set(shortcutPins.keys).subtracting(shortcutWindowIDs.keys)
        if !unresolvedSlots.isEmpty {
            details.append("Pinned \(shortcutList(unresolvedSlots)) unavailable")
        }
        if !unavailableShortcutSlots.isEmpty {
            details.append("Could not register \(shortcutList(unavailableShortcutSlots))")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    var statusDescription: String {
        [state.label, controllerNotice]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var currentWindowDescription: String {
        if selectedWindowID != nil {
            return selectedWindowDescription
        }
        if let pendingWindowID,
           let pendingSource = windows.first(where: { $0.id == pendingWindowID }) {
            return "Preparing \(pendingSource.applicationName) — \(pendingSource.title)"
        }
        return "No window selected"
    }

    func startWindowMonitoring() {
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

    private func refreshWindowsAutomatically() {
        requestWindowRefresh(isManual: false)
    }

    private func requestWindowRefresh(isManual: Bool) {
        guard CGPreflightScreenCaptureAccess() else {
            windows = []
            reconcileShortcuts(with: [])
            state = .permissionRequired
            errorMessage = nil

            if isManual, !requestedPermissionThisLaunch {
                requestedPermissionThisLaunch = true
                if CGRequestScreenCaptureAccess() {
                    refreshWindows()
                }
            }
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
            errorMessage = nil
            if stream == nil && selectionTask == nil {
                state = .loading
            }
        }

        windowRefreshTask = Task { [weak self] in
            await self?.performWindowRefresh(isManual: isManual)
        }
    }

    private func performWindowRefresh(isManual: Bool) async {
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
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let existingWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let candidates = content.windows
                .filter { window in
                    let frame = window.frame
                    let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let bundleIdentifier = window.owningApplication?.bundleIdentifier

                    return window.windowLayer == 0
                        && frame.width >= 160
                        && frame.height >= 100
                        && !title.isEmpty
                        && window.owningApplication != nil
                        && bundleIdentifier != ownBundleIdentifier
                }
                .map { window in
                    WindowSource(window: window, reusing: existingWindows[window.windowID])
                }
                .sorted {
                    let first = "\($0.applicationName) \($0.title)"
                    let second = "\($1.applicationName) \($1.title)"
                    return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
                }

            windows = candidates
            reconcileShortcuts(with: candidates)
            if stream == nil {
                state = selectionTask == nil ? .idle : .switching
            } else if pendingWindowID == nil, selectedWindowID != nil {
                state = .capturing
            }

            let sourcesNeedingThumbnails = isManual
                ? candidates
                : candidates.filter { $0.thumbnail == nil }
            await loadThumbnails(for: sourcesNeedingThumbnails)
        } catch {
            guard isManual else { return }
            let message = Self.friendlyMessage(for: error)
            errorMessage = message
            if stream == nil {
                state = .failed(message)
            }
        }
    }

    func select(_ source: WindowSource) {
        guard windows.contains(where: { $0.id == source.id }) else {
            errorMessage = "That window is no longer available. Refresh the window list."
            NSSound.beep()
            return
        }
        guard source.id != selectedWindowID || state != .capturing else { return }

        pendingSelection = source
        pendingWindowID = source.id
        errorMessage = nil
        state = .switching

        guard selectionTask == nil else { return }
        startSelectionTask()
    }

    func stopCapture() {
        pendingSelection = nil
        awaitingLiveSelection = nil
        pendingWindowID = nil
        selectionGeneration += 1
        selectionTask?.cancel()
        selectionTask = nil

        let streamToStop = stream
        stream = nil
        resetCursorTracking()
        selectedWindowID = nil
        selectedWindowDescription = "Nothing selected"
        errorMessage = nil
        state = .idle
        renderer.clear()

        guard let streamToStop else { return }
        Task {
            do {
                try await streamToStop.stopCapture()
            } catch where stream == nil && state == .idle {
                let message = Self.friendlyMessage(for: error)
                errorMessage = message
                state = .failed(message)
            } catch {
                // A newer stream owns the UI; an old stream's stop error is stale.
            }
        }
    }

    func shortcut(for source: WindowSource) -> Int? {
        shortcutWindowIDs.first(where: { $0.value == source.id })?.key
    }

    func shortcutOwnerDescription(for slot: Int) -> String? {
        if let pin = shortcutPins[slot] {
            return pin.description
        }
        guard let windowID = shortcutWindowIDs[slot],
              let source = windows.first(where: { $0.id == windowID }) else {
            return nil
        }
        return "\(source.applicationName) — \(source.title)"
    }

    func pin(_ source: WindowSource, to slot: Int) {
        guard (1...9).contains(slot) else { return }

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

    func clearShortcut(_ slot: Int) {
        if let windowID = shortcutWindowIDs[slot],
           let source = windows.first(where: { $0.id == windowID }) {
            shortcutExclusions.insert(PinnedWindow(source: source))
        } else if let pin = shortcutPins[slot] {
            shortcutExclusions.insert(pin)
        }
        shortcutPins.removeValue(forKey: slot)
        resolvedPinnedWindowIDs.removeValue(forKey: slot)
        persistShortcutPins()
        persistShortcutExclusions()
        reconcileShortcuts(with: windows)
    }

    func activateShortcut(_ slot: Int) {
        guard !unavailableShortcutSlots.contains(slot) else {
            errorMessage = "Option+\(slot) is already reserved by another application."
            NSSound.beep()
            return
        }
        guard let windowID = shortcutWindowIDs[slot],
              let source = windows.first(where: { $0.id == windowID }) else {
            if let pin = shortcutPins[slot] {
                errorMessage = "Option+\(slot) stays pinned to \(pin.description), but that window is unavailable."
                NSSound.beep()
            }
            return
        }
        select(source)
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func restartApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 1; /usr/bin/open -n \"$1\"",
            "betterdemos-restart",
            Bundle.main.bundleURL.path
        ]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let message = "Could not restart BetterDemos: \(error.localizedDescription)"
            errorMessage = message
            state = .failed(message)
        }
    }

    private func startSelectionTask() {
        selectionGeneration += 1
        let generation = selectionGeneration
        selectionTask = Task { [weak self] in
            await self?.processPendingSelections(generation: generation)
        }
    }

    private func processPendingSelections(generation: Int) async {
        while !Task.isCancelled,
              generation == selectionGeneration,
              let nextSelection = pendingSelection {
            pendingSelection = nil
            state = .switching

            do {
                try await switchCapture(to: nextSelection)
                guard !Task.isCancelled, generation == selectionGeneration else { break }
                // A successful ScreenCaptureKit call confirms the filter, but
                // only the next complete buffer confirms visible output.
                awaitingLiveSelection = nextSelection
            } catch {
                guard !Task.isCancelled, generation == selectionGeneration else { break }

                if awaitingLiveSelection?.id == nextSelection.id {
                    awaitingLiveSelection = nil
                }
                let message = Self.friendlyMessage(for: error)
                errorMessage = message

                if pendingSelection == nil {
                    pendingWindowID = nil
                    state = isLive ? .capturing : .failed(message)
                }
            }
        }

        guard generation == selectionGeneration else { return }
        selectionTask = nil
    }

    private func switchCapture(to source: WindowSource) async throws {
        isSwitchingStream = true
        defer {
            isSwitchingStream = false
            synchronizeDesiredCursorVisibility()
        }
        if let cursorVisibilityUpdateTask {
            cursorVisibilityUpdateTask.cancel()
            await cursorVisibilityUpdateTask.value
            self.cursorVisibilityUpdateTask = nil
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
            try? newStream.removeStreamOutput(streamOutput, type: .screen)
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

    private func makeStreamConfiguration(
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
        configuration.backgroundColor = Self.blackBackground
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = "BetterDemos — Demo Stage"
        return configuration
    }

    private func shouldCaptureCursor(for source: WindowSource) -> Bool {
        guard source.processIdentifier != 0,
              let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontmostApplication.processIdentifier == source.processIdentifier
    }

    private func handleApplicationActivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource else { return }
        desiredCursorVisibility = application.processIdentifier == source.processIdentifier
            && shouldCaptureCursor(for: source)
        scheduleCursorVisibilityUpdateIfNeeded()
    }

    private func handleApplicationDeactivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource,
              application.processIdentifier == source.processIdentifier else { return }
        desiredCursorVisibility = false
        scheduleCursorVisibilityUpdateIfNeeded()
    }

    private func synchronizeDesiredCursorVisibility() {
        desiredCursorVisibility = activeCaptureSource.map(shouldCaptureCursor(for:)) ?? false
        scheduleCursorVisibilityUpdateIfNeeded()
    }

    private func scheduleCursorVisibilityUpdateIfNeeded() {
        guard !isSwitchingStream,
              stream != nil,
              activeCaptureSource != nil,
              activeCaptureFormat != nil,
              capturesCursor != desiredCursorVisibility,
              cursorVisibilityUpdateTask == nil else { return }

        cursorVisibilityUpdateTask = Task { [weak self] in
            await self?.applyCursorVisibilityUpdate()
        }
    }

    private func applyCursorVisibilityUpdate() async {
        guard !Task.isCancelled,
              let targetStream = stream,
              let source = activeCaptureSource,
              let format = activeCaptureFormat else {
            cursorVisibilityUpdateTask = nil
            return
        }

        let requestedVisibility = desiredCursorVisibility
        let configuration = makeStreamConfiguration(
            for: format,
            showsCursor: requestedVisibility
        )

        do {
            try await targetStream.updateConfiguration(configuration)
            guard stream === targetStream,
                  activeCaptureSource?.id == source.id else {
                cursorVisibilityUpdateTask = nil
                return
            }

            capturesCursor = requestedVisibility
            cursorVisibilityUpdateTask = nil
            scheduleCursorVisibilityUpdateIfNeeded()
        } catch {
            cursorVisibilityUpdateTask = nil
            guard !Task.isCancelled, stream === targetStream else { return }
            errorMessage = "Could not update cursor visibility: \(Self.friendlyMessage(for: error))"
        }
    }

    private func resetCursorTracking() {
        cursorVisibilityUpdateTask?.cancel()
        cursorVisibilityUpdateTask = nil
        activeCaptureSource = nil
        activeCaptureFormat = nil
        capturesCursor = false
        desiredCursorVisibility = false
        isSwitchingStream = false
    }

    private func handleFrame(from sourceStream: SCStream, geometry: CaptureFrameGeometry) {
        guard stream === sourceStream else { return }

        let contentAspectRatio = geometry.contentAspectRatio
        if abs(stageAspectRatio - contentAspectRatio) > 0.001 {
            stageAspectRatio = contentAspectRatio
        }

        if let liveSelection = awaitingLiveSelection {
            selectedWindowID = liveSelection.id
            selectedWindowDescription = "\(liveSelection.applicationName) — \(liveSelection.title)"
            awaitingLiveSelection = nil
            if pendingWindowID == liveSelection.id {
                pendingWindowID = nil
            }
        }

        if selectedWindowID != nil {
            state = pendingWindowID == nil ? .capturing : .switching
            if state == .capturing {
                errorMessage = nil
            }
        }
    }

    private func handleStreamStopped(_ stoppedStream: SCStream, error: Error) {
        guard stream === stoppedStream else { return }

        stream = nil
        resetCursorTracking()
        awaitingLiveSelection = nil
        pendingSelection = nil
        pendingWindowID = nil
        selectedWindowID = nil
        selectedWindowDescription = "Nothing selected"
        selectionGeneration += 1
        selectionTask?.cancel()
        selectionTask = nil
        renderer.clear()

        let message = Self.friendlyMessage(for: error)
        errorMessage = message
        state = .failed(message)
    }

    private func loadThumbnails(for sources: [WindowSource]) async {
        for source in sources {
            guard let index = windows.firstIndex(where: { $0.id == source.id }) else { continue }

            do {
                let filter = SCContentFilter(desktopIndependentWindow: source.window)
                let configuration = SCStreamConfiguration()
                configuration.width = 480
                configuration.height = 270
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = false
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.backgroundColor = Self.blackBackground
                configuration.ignoreShadowsSingleWindow = true
                configuration.ignoreGlobalClipSingleWindow = true

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                windows[index].thumbnail = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            } catch {
                // A window can close during refresh. Its fallback remains useful
                // until the next source-list refresh removes it.
            }
        }
    }

    private func reconcileShortcuts(with sources: [WindowSource]) {
        let oldResolvedIDs = shortcutWindowIDs
        let oldPinnedWindowIDs = resolvedPinnedWindowIDs
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var newResolvedIDs: [Int: CGWindowID] = [:]
        var newPinnedWindowIDs: [Int: CGWindowID] = [:]
        var usedWindowIDs: Set<CGWindowID> = []
        var didUpdatePersistedIdentity = false

        for slot in shortcutPins.keys.sorted() {
            guard let pin = shortcutPins[slot] else { continue }

            var resolvedSource: WindowSource?
            if let oldWindowID = oldPinnedWindowIDs[slot],
               let existingSource = sourcesByID[oldWindowID],
               !usedWindowIDs.contains(oldWindowID) {
                resolvedSource = existingSource
            } else {
                let matches = sources.filter {
                    !usedWindowIDs.contains($0.id) && pin.matches($0)
                }
                if matches.count == 1 {
                    resolvedSource = matches[0]
                }
            }

            guard let resolvedSource else { continue }
            newResolvedIDs[slot] = resolvedSource.id
            newPinnedWindowIDs[slot] = resolvedSource.id
            usedWindowIDs.insert(resolvedSource.id)

            let currentIdentity = PinnedWindow(source: resolvedSource)
            if currentIdentity != pin {
                shortcutPins[slot] = currentIdentity
                didUpdatePersistedIdentity = true
            }
        }

        let reservedSlots = Set(shortcutPins.keys)
        let automaticSlots = (1...9).filter { !reservedSlots.contains($0) }

        // Keep automatic assignments stable while their windows remain available.
        for slot in automaticSlots {
            guard let oldWindowID = oldResolvedIDs[slot],
                  let existingSource = sourcesByID[oldWindowID],
                  !usedWindowIDs.contains(oldWindowID),
                  !shortcutExclusions.contains(PinnedWindow(source: existingSource)) else {
                continue
            }
            newResolvedIDs[slot] = oldWindowID
            usedWindowIDs.insert(oldWindowID)
        }

        var remainingSources = sources.filter {
            !usedWindowIDs.contains($0.id)
                && !shortcutExclusions.contains(PinnedWindow(source: $0))
        }.makeIterator()

        for slot in automaticSlots where newResolvedIDs[slot] == nil {
            guard let source = remainingSources.next() else { break }
            newResolvedIDs[slot] = source.id
            usedWindowIDs.insert(source.id)
        }

        shortcutWindowIDs = newResolvedIDs
        resolvedPinnedWindowIDs = newPinnedWindowIDs
        if didUpdatePersistedIdentity {
            persistShortcutPins()
        }
        refreshHotKeyRegistrations()
    }

    private func refreshHotKeyRegistrations() {
        unavailableShortcutSlots = hotKeyManager.updateRegisteredSlots(
            Set(shortcutWindowIDs.keys)
        )
    }

    private func persistShortcutPins() {
        let pins = shortcutPins
            .map { ShortcutPin(slot: $0.key, window: $0.value) }
            .sorted { $0.slot < $1.slot }
        guard let data = try? JSONEncoder().encode(pins) else { return }
        defaults.set(data, forKey: Self.shortcutDefaultsKey)
    }

    private func persistShortcutExclusions() {
        let exclusions = shortcutExclusions.sorted {
            $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending
        }
        guard let data = try? JSONEncoder().encode(exclusions) else { return }
        defaults.set(data, forKey: Self.shortcutExclusionsDefaultsKey)
    }

    private static func loadShortcutPins(from defaults: UserDefaults) -> [Int: PinnedWindow] {
        guard let data = defaults.data(forKey: shortcutDefaultsKey),
              let pins = try? JSONDecoder().decode([ShortcutPin].self, from: data) else {
            return [:]
        }
        return Dictionary(
            pins.filter { (1...9).contains($0.slot) }.map { ($0.slot, $0.window) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    private static func loadShortcutExclusions(from defaults: UserDefaults) -> Set<PinnedWindow> {
        guard let data = defaults.data(forKey: shortcutExclusionsDefaultsKey),
              let exclusions = try? JSONDecoder().decode([PinnedWindow].self, from: data) else {
            return []
        }
        return Set(exclusions)
    }

    private func shortcutList(_ slots: Set<Int>) -> String {
        slots.sorted().map { "⌥\($0)" }.joined(separator: ", ")
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain
            || nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
            return "Screen capture stopped (\(nsError.code)): \(nsError.localizedDescription)"
        }
        return error.localizedDescription
    }
}

private enum CaptureLifecycleError: LocalizedError {
    case stoppedBeforeFirstFrame

    var errorDescription: String? {
        "Screen capture stopped before it produced a frame."
    }
}

private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let renderer: SampleBufferRenderer
    private let onFrame: @Sendable (SCStream, CaptureFrameGeometry) -> Void
    private let onFailure: @Sendable (SCStream, Error) -> Void

    init(
        renderer: SampleBufferRenderer,
        onFrame: @escaping @Sendable (SCStream, CaptureFrameGeometry) -> Void,
        onFailure: @escaping @Sendable (SCStream, Error) -> Void
    ) {
        self.renderer = renderer
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, Self.isCompleteFrame(sampleBuffer) else { return }
        guard let geometry = renderer.enqueue(sampleBuffer) else { return }
        onFrame(stream, geometry)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(stream, error)
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: statusValue) else {
            return false
        }
        return frameStatus == .complete
    }
}
