import AppKit
import CoreMedia
import ScreenCaptureKit

/// Coordinates source discovery, ScreenCaptureKit lifecycle, and UI-facing state.
@MainActor
final class CaptureManager: ObservableObject {
    // SCStreamConfiguration.backgroundColor is an unretained CGColorRef. Keep
    // these objects alive while ScreenCaptureKit copies stream configurations.
    private static let transparentBackground = CGColor(gray: 0, alpha: 0)
    private static let blackBackground = CGColor(gray: 0, alpha: 1)
    private static let highlightsMouseClicksKey = "presentation.highlightsMouseClicks"
    private static let highlightsKeystrokesKey = "presentation.highlightsKeystrokes"

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
    @Published private(set) var highlightsMouseClicks: Bool
    @Published private(set) var highlightsKeystrokes: Bool
    @Published private(set) var needsKeystrokeAccessibilityPermission = false
    @Published private(set) var keystrokePresentation: KeystrokePresentation?
    @Published private(set) var clickPresentations: [ClickPresentation] = []
    @Published private var shortcutPins: [Int: PinnedWindow] = [:]
    @Published private var shortcutExclusions: Set<PinnedWindow> = []

    let renderer = SampleBufferRenderer()

    private let shortcutStore: ShortcutPreferencesStore
    private let preferencesDefaults: UserDefaults
    private let sampleQueue = DispatchQueue(
        label: "dev.poc.meetstage.screen-frames",
        qos: .userInteractive
    )
    private lazy var streamOutput = CaptureStreamOutput(
        renderer: renderer,
        onFrame: { [weak self] sourceStreamID, geometry in
            Task { @MainActor in
                self?.handleFrame(from: sourceStreamID, geometry: geometry)
            }
        },
        onFailure: { [weak self] sourceStreamID, error in
            Task { @MainActor in
                self?.handleStreamStopped(sourceStreamID, error: error)
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
    private var captureConfigurationUpdateTask: Task<Void, Never>?
    private var keystrokeDismissTask: Task<Void, Never>?
    private var clickDismissTasks: [UUID: Task<Void, Never>] = [:]
    private var keystrokeMonitor: GlobalKeystrokeMonitor?
    private var mouseClickMonitor: GlobalMouseClickMonitor?
    private let sourceClickRipplePresenter = SourceClickRipplePresenter()
    private let workspaceObservationBag: WorkspaceObservationBag
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
        let shortcutStore = ShortcutPreferencesStore(defaults: defaults)
        self.shortcutStore = shortcutStore
        preferencesDefaults = defaults
        stageAspectRatio = StageWindowSizing.currentScreenAspectRatio()
        highlightsMouseClicks = defaults.bool(forKey: Self.highlightsMouseClicksKey)
        highlightsKeystrokes =
            defaults.bool(forKey: Self.highlightsKeystrokesKey)
            && GlobalKeystrokeMonitor.hasAccessibilityPermission
        shortcutPins = shortcutStore.loadPins()
        shortcutExclusions = shortcutStore.loadExclusions()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservationBag = WorkspaceObservationBag(center: workspaceCenter)
        workspaceObservationBag.store([
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                else { return }
                Task { @MainActor [weak self] in
                    self?.handleApplicationActivation(application)
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                else { return }
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
        ])

        if highlightsKeystrokes {
            startKeystrokeMonitor()
        }
        if highlightsMouseClicks {
            startMouseClickMonitor()
        }
    }

    deinit {
        captureConfigurationUpdateTask?.cancel()
        keystrokeDismissTask?.cancel()
        clickDismissTasks.values.forEach { $0.cancel() }
        windowMonitoringTask?.cancel()
        windowRefreshTask?.cancel()
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

    var unassignedDisplayedWindows: [WindowSource] {
        displayedWindows.filter { shortcut(for: $0) == nil }
    }

    func window(forShortcutSlot slot: Int) -> WindowSource? {
        guard let windowID = shortcutWindowIDs[slot] else { return nil }
        return windows.first { $0.id == windowID }
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
            let pendingSource = windows.first(where: { $0.id == pendingWindowID })
        {
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
            if stream == nil && selectionTask == nil && state != .paused {
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

            if state == .paused,
                let selectedWindowID,
                !candidates.contains(where: { $0.id == selectedWindowID })
            {
                self.selectedWindowID = nil
                selectedWindowDescription = "Nothing selected"
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

            let sourcesNeedingThumbnails =
                isManual
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

        if CaptureSelectionPolicy.action(
            for: source.id,
            selectedWindowID: selectedWindowID,
            state: state
        ) == .pause {
            pauseCapture()
            return
        }

        pendingSelection = source
        pendingWindowID = source.id
        errorMessage = nil
        state = .switching

        guard selectionTask == nil else { return }
        startSelectionTask()
    }

    private func pauseCapture() {
        guard isLive else { return }
        endCapture(preservingSelection: true)
    }

    func stopCapture() {
        endCapture(preservingSelection: false)
    }

    private func endCapture(preservingSelection: Bool) {
        pendingSelection = nil
        awaitingLiveSelection = nil
        pendingWindowID = nil
        selectionGeneration += 1
        selectionTask?.cancel()
        selectionTask = nil

        let streamToStop = stream
        self.stream = nil
        resetCursorTracking()
        if !preservingSelection {
            selectedWindowID = nil
            selectedWindowDescription = "Nothing selected"
        }
        errorMessage = nil
        state = preservingSelection && selectedWindowID != nil ? .paused : .idle
        clearKeystrokePresentation()
        renderer.clear()

        guard let streamToStop else { return }
        Task {
            do {
                try await streamToStop.stopCapture()
            } catch where stream == nil && (state == .idle || state == .paused) {
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

    func clearShortcut(_ slot: Int) {
        if let windowID = shortcutWindowIDs[slot],
            let source = windows.first(where: { $0.id == windowID })
        {
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
            let source = windows.first(where: { $0.id == windowID })
        else {
            if let pin = shortcutPins[slot] {
                errorMessage = "Option+\(slot) stays pinned to \(pin.description), but that window is unavailable."
                NSSound.beep()
            }
            return
        }
        select(source)
    }

    func toggleMouseClickHighlighting() {
        highlightsMouseClicks.toggle()
        preferencesDefaults.set(highlightsMouseClicks, forKey: Self.highlightsMouseClicksKey)
        if highlightsMouseClicks {
            startMouseClickMonitor()
        } else {
            mouseClickMonitor?.stop()
            clearClickPresentations()
        }
    }

    func toggleKeystrokeHighlighting() {
        if highlightsKeystrokes {
            highlightsKeystrokes = false
            needsKeystrokeAccessibilityPermission = false
            preferencesDefaults.set(false, forKey: Self.highlightsKeystrokesKey)
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
        preferencesDefaults.set(true, forKey: Self.highlightsKeystrokesKey)
        startKeystrokeMonitor()
    }

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
        configuration.backgroundColor = Self.transparentBackground
        configuration.shouldBeOpaque = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = "BetterDemos — Demo Stage"
        return configuration
    }

    private func shouldCaptureCursor(for source: WindowSource) -> Bool {
        guard source.processIdentifier != 0,
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
        else {
            return false
        }
        return frontmostApplication.processIdentifier == source.processIdentifier
    }

    private func handleApplicationActivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource else { return }
        let selectedSourceIsFocused =
            application.processIdentifier == source.processIdentifier
            && shouldCaptureCursor(for: source)
        updatePresentationFocus(selectedSourceIsFocused)
    }

    private func handleApplicationDeactivation(_ application: NSRunningApplication) {
        refreshWindowsAutomatically()
        guard let source = activeCaptureSource,
            application.processIdentifier == source.processIdentifier
        else { return }
        updatePresentationFocus(false)
    }

    private func synchronizeDesiredCursorVisibility() {
        let selectedSourceIsFocused = activeCaptureSource.map(shouldCaptureCursor(for:)) ?? false
        updatePresentationFocus(selectedSourceIsFocused)
    }

    private func updatePresentationFocus(_ selectedSourceIsFocused: Bool) {
        desiredCursorVisibility = selectedSourceIsFocused
        if !selectedSourceIsFocused {
            clearKeystrokePresentation()
            clearClickPresentations()
        }
        scheduleCaptureConfigurationUpdateIfNeeded()
    }

    private func scheduleCaptureConfigurationUpdateIfNeeded() {
        guard !isSwitchingStream,
            stream != nil,
            activeCaptureSource != nil,
            activeCaptureFormat != nil,
            capturesCursor != desiredCursorVisibility,
            captureConfigurationUpdateTask == nil
        else { return }

        captureConfigurationUpdateTask = Task { [weak self] in
            await self?.applyCaptureConfigurationUpdate()
        }
    }

    private func applyCaptureConfigurationUpdate() async {
        guard !Task.isCancelled,
            let targetStream = stream,
            let source = activeCaptureSource,
            let format = activeCaptureFormat
        else {
            captureConfigurationUpdateTask = nil
            return
        }

        let requestedCursorVisibility = desiredCursorVisibility
        let configuration = makeStreamConfiguration(
            for: format,
            showsCursor: requestedCursorVisibility
        )

        do {
            try await targetStream.updateConfiguration(configuration)
            guard stream === targetStream,
                activeCaptureSource?.id == source.id
            else {
                captureConfigurationUpdateTask = nil
                return
            }

            capturesCursor = requestedCursorVisibility
            captureConfigurationUpdateTask = nil
            scheduleCaptureConfigurationUpdateIfNeeded()
        } catch {
            captureConfigurationUpdateTask = nil
            guard !Task.isCancelled, stream === targetStream else { return }
            errorMessage = "Could not update presentation effects: \(Self.friendlyMessage(for: error))"
        }
    }

    private func resetCursorTracking() {
        captureConfigurationUpdateTask?.cancel()
        captureConfigurationUpdateTask = nil
        activeCaptureSource = nil
        activeCaptureFormat = nil
        capturesCursor = false
        desiredCursorVisibility = false
        clearKeystrokePresentation()
        clearClickPresentations()
        isSwitchingStream = false
    }

    private func startMouseClickMonitor() {
        if mouseClickMonitor == nil {
            mouseClickMonitor = GlobalMouseClickMonitor { [weak self] location in
                self?.showMouseClick(at: location)
            }
        }
        mouseClickMonitor?.start()
    }

    private func showMouseClick(at clickLocation: GlobalClickLocation) {
        guard let source = activeCaptureSource,
            selectedWindowID == source.id,
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: highlightsMouseClicks,
                selectedSourceIsFocused: shouldCaptureCursor(for: source)
            )
        else { return }

        let sourceFrame = WindowFrameResolver.currentFrame(
            for: source.id,
            fallback: source.window.frame
        )
        guard let normalizedLocation = ClickPresentationGeometry.normalizedLocation(
            for: clickLocation.quartzPoint,
            in: sourceFrame
        ) else { return }

        let presentation = ClickPresentation(location: normalizedLocation)
        clickPresentations.append(presentation)
        sourceClickRipplePresenter.show(
            presentation,
            sourceFrame: sourceFrame,
            clickLocation: clickLocation
        )

        clickDismissTasks[presentation.id]?.cancel()
        clickDismissTasks[presentation.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            self?.dismissClickPresentation(presentation.id)
        }
    }

    private func dismissClickPresentation(_ id: UUID) {
        clickDismissTasks[id]?.cancel()
        clickDismissTasks[id] = nil
        clickPresentations.removeAll { $0.id == id }
    }

    private func clearClickPresentations() {
        clickDismissTasks.values.forEach { $0.cancel() }
        clickDismissTasks.removeAll()
        clickPresentations.removeAll()
        sourceClickRipplePresenter.dismissAll()
    }

    private func startKeystrokeMonitor() {
        if keystrokeMonitor == nil {
            keystrokeMonitor = GlobalKeystrokeMonitor { [weak self] label in
                self?.showKeystroke(label)
            }
        }
        keystrokeMonitor?.start()
    }

    private func showKeystroke(_ label: String) {
        let selectedSourceIsFocused = activeCaptureSource.map(shouldCaptureCursor(for:)) ?? false
        guard PresentationEffectFocusPolicy.shouldPresent(
            isEnabled: highlightsKeystrokes,
            selectedSourceIsFocused: selectedSourceIsFocused
        ) else { return }
        keystrokeDismissTask?.cancel()
        let presentation = KeystrokePresentation(label: label)
        keystrokePresentation = presentation
        keystrokeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled,
                self?.keystrokePresentation?.id == presentation.id
            else { return }
            self?.keystrokePresentation = nil
            self?.keystrokeDismissTask = nil
        }
    }

    private func clearKeystrokePresentation() {
        keystrokeDismissTask?.cancel()
        keystrokeDismissTask = nil
        keystrokePresentation = nil
    }

    private func handleFrame(from sourceStreamID: ObjectIdentifier, geometry: CaptureFrameGeometry) {
        guard let stream, ObjectIdentifier(stream) == sourceStreamID else { return }

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

    private func handleStreamStopped(_ stoppedStreamID: ObjectIdentifier, error: Error) {
        guard let stream, ObjectIdentifier(stream) == stoppedStreamID else { return }

        self.stream = nil
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

    private func refreshHotKeyRegistrations() {
        unavailableShortcutSlots = hotKeyManager.updateRegisteredSlots(
            Set(shortcutWindowIDs.keys)
        )
    }

    private func persistShortcutPins() {
        shortcutStore.savePins(shortcutPins)
    }

    private func persistShortcutExclusions() {
        shortcutStore.saveExclusions(shortcutExclusions)
    }

    private func shortcutList(_ slots: Set<Int>) -> String {
        slots.sorted().map { "⌥\($0)" }.joined(separator: ", ")
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain
            || nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
        {
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
