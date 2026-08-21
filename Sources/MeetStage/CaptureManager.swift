import AppKit
import CoreMedia
import ScreenCaptureKit

/// Coordinates source discovery, ScreenCaptureKit lifecycle, and UI-facing state.
@MainActor
final class CaptureManager: ObservableObject {
    // SCStreamConfiguration.backgroundColor is an unretained CGColorRef. Keep
    // these objects alive while ScreenCaptureKit copies stream configurations.
    private static let transparentBackground = CGColor(gray: 0, alpha: 0)
    private static let firstFrameTimeout: Duration = .seconds(3)
    private static let unavailableSourceMessage =
        "Window unavailable. Restore it or choose another window."

    // MARK: - Observable state

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
    @Published private(set) var annotationsEnabled = false
    @Published private(set) var isAnnotating = false
    @Published private(set) var annotationLifetimeSeconds: Int
    @Published private(set) var annotationColor: PresentationColor
    @Published private(set) var clickHighlightColor: PresentationColor
    @Published private(set) var clickHighlightSize: PresentationSize
    @Published private(set) var keystrokeHighlightSize: PresentationSize
    @Published private(set) var keystrokeAppearance: KeystrokeAppearance
    @Published private var shortcutPins: [Int: PinnedWindow] = [:]
    @Published private var shortcutExclusions: Set<PinnedWindow> = []

    let renderer = SampleBufferRenderer()
    let annotations: AnnotationSession

    var displayedStageAspectRatio: CGFloat {
        StageWindowAspectRatioPolicy.displayedAspectRatio(
            for: state,
            sourceAspectRatio: stageAspectRatio,
            inactiveAspectRatio: inactiveStageAspectRatio
        )
    }

    private let shortcutStore: ShortcutPreferencesStore
    private let presentationStore: PresentationPreferencesStore
    private let inactiveStageAspectRatio: CGFloat
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
    private lazy var sourceAnnotationPresenter = SourceAnnotationPresenter()
    private var workspaceMonitor: WorkspaceMonitor?
    private var windowMonitoringTask: Task<Void, Never>?
    private var windowRefreshTask: Task<Void, Never>?
    private var queuedManualRefresh = false
    private var awaitingLiveSelection: WindowSource?
    private var firstFrameTimeoutTask: Task<Void, Never>?
    private var pendingSelection: WindowSource?
    private var selectionTask: Task<Void, Never>?
    private var selectionGeneration = 0
    private var requestedPermissionThisLaunch = false
    private var resolvedPinnedWindowIDs: [Int: CGWindowID] = [:]

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        let shortcutStore = ShortcutPreferencesStore(defaults: defaults)
        let presentationStore = PresentationPreferencesStore(defaults: defaults)
        let inactiveStageAspectRatio = StageWindowSizing.currentScreenAspectRatio()
        self.shortcutStore = shortcutStore
        self.presentationStore = presentationStore
        self.inactiveStageAspectRatio = inactiveStageAspectRatio
        stageAspectRatio = inactiveStageAspectRatio
        let annotationLifetimeSeconds = presentationStore.annotationLifetimeSeconds
        let annotationColor = presentationStore.annotationColor
        self.annotationLifetimeSeconds = annotationLifetimeSeconds
        self.annotationColor = annotationColor
        clickHighlightColor = presentationStore.clickHighlightColor
        clickHighlightSize = presentationStore.clickHighlightSize
        keystrokeHighlightSize = presentationStore.keystrokeHighlightSize
        keystrokeAppearance = presentationStore.keystrokeAppearance
        annotations = AnnotationSession(
            lifetimeSeconds: annotationLifetimeSeconds,
            inkColor: annotationColor
        )
        highlightsMouseClicks = presentationStore.highlightsMouseClicks
        highlightsKeystrokes =
            presentationStore.highlightsKeystrokes
            && GlobalKeystrokeMonitor.hasAccessibilityPermission
        shortcutPins = shortcutStore.loadPins()
        shortcutExclusions = shortcutStore.loadExclusions()

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
        firstFrameTimeoutTask?.cancel()
        selectionTask?.cancel()
    }

    // MARK: - View state

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

    // MARK: - Window discovery

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

            handleUnavailableCaptureSources(in: candidates)

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

    // MARK: - Capture commands

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
        cancelFirstFrameTimeout()
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
        cancelFirstFrameTimeout()
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
            } catch  where stream == nil && (state == .idle || state == .paused) {
                let message = Self.friendlyMessage(for: error)
                errorMessage = message
                state = .failed(message)
            } catch {
                // A newer stream owns the UI; an old stream's stop error is stale.
            }
        }
    }

    // MARK: - Shortcuts

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

    // MARK: - Presentation commands and preferences

    func toggleMouseClickHighlighting() {
        highlightsMouseClicks.toggle()
        presentationStore.highlightsMouseClicks = highlightsMouseClicks
        if highlightsMouseClicks {
            startMouseClickMonitor()
        } else {
            mouseClickMonitor?.stop()
            clearClickPresentations()
        }
    }

    func toggleAnnotations() {
        annotationsEnabled.toggle()
        if annotationsEnabled {
            focusSelectedSourceForAnnotationsIfPossible()
            activateAnnotationsIfPossible()
        } else {
            deactivateAnnotations(clearStrokes: true)
        }
    }

    func clearAnnotations() {
        annotations.clear()
    }

    func finishAnnotations() {
        guard annotationsEnabled || isAnnotating else { return }
        annotationsEnabled = false
        deactivateAnnotations(clearStrokes: true)
    }

    func setAnnotationLifetimeSeconds(_ value: Int) {
        let normalizedValue = AnnotationTiming.normalizedLifetimeSeconds(value)
        annotationLifetimeSeconds = normalizedValue
        annotations.setLifetimeSeconds(normalizedValue)
        presentationStore.annotationLifetimeSeconds = normalizedValue
    }

    func setAnnotationColor(_ value: PresentationColor) {
        annotationColor = value
        annotations.setInkColor(value)
        presentationStore.annotationColor = value
    }

    func setClickHighlightColor(_ value: PresentationColor) {
        clickHighlightColor = value
        presentationStore.clickHighlightColor = value
    }

    func setClickHighlightSize(_ value: PresentationSize) {
        clickHighlightSize = value
        presentationStore.clickHighlightSize = value
    }

    func setKeystrokeHighlightSize(_ value: PresentationSize) {
        keystrokeHighlightSize = value
        presentationStore.keystrokeHighlightSize = value
    }

    func setKeystrokeAppearance(_ value: KeystrokeAppearance) {
        keystrokeAppearance = value
        presentationStore.keystrokeAppearance = value
    }

    func toggleKeystrokeHighlighting() {
        if highlightsKeystrokes {
            highlightsKeystrokes = false
            needsKeystrokeAccessibilityPermission = false
            presentationStore.highlightsKeystrokes = false
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
        presentationStore.highlightsKeystrokes = true
        startKeystrokeMonitor()
    }

    // MARK: - Application actions

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
            "bettermeets-restart",
            Bundle.main.bundleURL.path
        ]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let message = "Could not restart BetterMeets: \(error.localizedDescription)"
            errorMessage = message
            state = .failed(message)
        }
    }

    // MARK: - Capture lifecycle

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
                scheduleFirstFrameTimeout(for: nextSelection.id)
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

    private func scheduleFirstFrameTimeout(for sourceID: CGWindowID) {
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

    private func cancelFirstFrameTimeout() {
        firstFrameTimeoutTask?.cancel()
        firstFrameTimeoutTask = nil
    }

    private func handleUnavailableCaptureSources(in sources: [WindowSource]) {
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

    private func recoverFromUnavailableSelection(sourceID: CGWindowID) {
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
            errorMessage = Self.unavailableSourceMessage
            state = .switching
            guard selectionTask == nil else { return }
            startSelectionTask()

        case .fail:
            failUnavailableSelection()
        }
    }

    private func failUnavailableSelection() {
        endCapture(preservingSelection: false)
        errorMessage = Self.unavailableSourceMessage
        state = .failed(Self.unavailableSourceMessage)
    }

    private func switchCapture(to source: WindowSource) async throws {
        isSwitchingStream = true
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
        configuration.streamName = "BetterMeets — Demo Stage"
        return configuration
    }

    // MARK: - Focus and cursor capture

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
        if selectedSourceIsFocused {
            activateAnnotationsIfPossible()
        } else {
            clearKeystrokePresentation()
            clearClickPresentations()
            deactivateAnnotations(clearStrokes: false)
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
        cancelFirstFrameTimeout()
        captureConfigurationUpdateTask?.cancel()
        captureConfigurationUpdateTask = nil
        activeCaptureSource = nil
        activeCaptureFormat = nil
        capturesCursor = false
        desiredCursorVisibility = false
        clearKeystrokePresentation()
        clearClickPresentations()
        deactivateAnnotations(clearStrokes: true)
        isSwitchingStream = false
    }

    // MARK: - Presentation monitoring

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
        guard
            let normalizedLocation = ClickPresentationGeometry.normalizedLocation(
                for: clickLocation.quartzPoint,
                in: sourceFrame
            )
        else { return }

        let presentation = ClickPresentation(
            location: normalizedLocation,
            color: clickHighlightColor,
            size: clickHighlightSize
        )
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

    private func activateAnnotationsIfPossible() {
        guard annotationsEnabled,
            !isAnnotating,
            isLive,
            let source = activeCaptureSource,
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: true,
                selectedSourceIsFocused: shouldCaptureCursor(for: source)
            )
        else { return }

        isAnnotating = true
        sourceAnnotationPresenter.show(
            session: annotations,
            sourceWindowID: source.id,
            fallbackSourceFrame: source.window.frame,
            onFinish: { [weak self] in
                self?.finishAnnotations()
            }
        )
    }

    private func focusSelectedSourceForAnnotationsIfPossible() {
        guard isLive,
            let source = activeCaptureSource,
            !shouldCaptureCursor(for: source),
            let application = NSRunningApplication(
                processIdentifier: source.processIdentifier
            )
        else { return }

        application.activate()
    }

    private func deactivateAnnotations(clearStrokes: Bool) {
        isAnnotating = false
        sourceAnnotationPresenter.dismiss()
        if clearStrokes {
            annotations.clear()
        }
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
        guard
            PresentationEffectFocusPolicy.shouldPresent(
                isEnabled: highlightsKeystrokes,
                selectedSourceIsFocused: selectedSourceIsFocused
            )
        else { return }
        keystrokeDismissTask?.cancel()
        let presentation = KeystrokePresentation(
            label: label,
            size: keystrokeHighlightSize,
            appearance: keystrokeAppearance
        )
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

    // MARK: - Stream callbacks

    private func handleFrame(from sourceStreamID: ObjectIdentifier, geometry: CaptureFrameGeometry) {
        guard let stream, ObjectIdentifier(stream) == sourceStreamID else { return }

        let contentAspectRatio = geometry.contentAspectRatio
        if abs(stageAspectRatio - contentAspectRatio) > 0.001 {
            stageAspectRatio = contentAspectRatio
        }

        if let liveSelection = awaitingLiveSelection {
            cancelFirstFrameTimeout()
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
                activateAnnotationsIfPossible()
            }
        }
    }

    private func handleStreamStopped(_ stoppedStreamID: ObjectIdentifier, error: Error) {
        guard let stream, ObjectIdentifier(stream) == stoppedStreamID else { return }

        self.stream = nil
        cancelFirstFrameTimeout()
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

    // MARK: - Thumbnails and shortcut reconciliation

    private func loadThumbnails(for sources: [WindowSource]) async {
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

    // MARK: - Error presentation

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
