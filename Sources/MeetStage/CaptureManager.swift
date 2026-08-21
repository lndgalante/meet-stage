import AppKit
import CoreMedia
import ScreenCaptureKit

/// Coordinates source discovery, ScreenCaptureKit lifecycle, and UI-facing state.
@MainActor
final class CaptureManager: ObservableObject {
    // Stored state is module-internal so responsibility-focused extensions can
    // coordinate it without exposing any API outside the executable target.
    // SCStreamConfiguration.backgroundColor is an unretained CGColorRef. Keep
    // these objects alive while ScreenCaptureKit copies stream configurations.
    static let transparentBackground = CGColor(gray: 0, alpha: 0)
    static let firstFrameTimeout: Duration = .seconds(3)
    static let unavailableSourceMessage =
        "Window unavailable. Restore it or choose another window."

    // MARK: - Observable state

    @Published var windows: [WindowSource] = []
    @Published var selectedWindowID: CGWindowID?
    @Published var pendingWindowID: CGWindowID?
    @Published var state: CaptureState = .idle
    @Published var isRefreshing = false
    @Published var shortcutWindowIDs: [Int: CGWindowID] = [:]
    @Published var unavailableShortcutSlots: Set<Int> = []
    @Published var stageAspectRatio: CGFloat
    @Published var highlightsMouseClicks: Bool
    @Published var highlightsKeystrokes: Bool
    @Published var needsKeystrokeAccessibilityPermission = false
    @Published var keystrokePresentation: KeystrokePresentation?
    @Published var clickPresentations: [ClickPresentation] = []
    @Published var annotationsEnabled = false
    @Published var isAnnotating = false
    @Published var spotlightEnabled = false
    @Published var spotlightSize: PresentationSize
    @Published var spotlightOutsideOpacity: Double
    @Published var autoPresentationEnabled = false
    @Published var stageFrameStyle: StageFrameStyle
    @Published var stageFramePadding: Double
    @Published var stageFrameCornerRadius: Double
    @Published var stageFrameBlur: Double
    @Published var stageFrameShadow: Double
    @Published var autoZoomSize: PresentationSize
    @Published var annotationLifetimeSeconds: Int
    @Published var annotationColor: PresentationColor
    @Published var clickHighlightColor: PresentationColor
    @Published var clickHighlightSize: PresentationSize
    @Published var keystrokeHighlightSize: PresentationSize
    @Published var keystrokeAppearance: KeystrokeAppearance
    @Published var shortcutPins: [Int: PinnedWindow] = [:]
    @Published var shortcutExclusions: Set<PinnedWindow> = []

    let renderer = SampleBufferRenderer()
    let annotations: AnnotationSession
    let spotlight: SpotlightSession
    let autoPresentation = AutoPresentationSession()

    var displayedStageAspectRatio: CGFloat {
        StageWindowAspectRatioPolicy.displayedAspectRatio(
            for: state,
            sourceAspectRatio: stageAspectRatio,
            inactiveAspectRatio: inactiveStageAspectRatio
        )
    }

    let shortcutStore: ShortcutPreferencesStore
    let presentationStore: PresentationPreferencesStore
    let inactiveStageAspectRatio: CGFloat
    let sampleQueue = DispatchQueue(
        label: "dev.poc.meetstage.screen-frames",
        qos: .userInteractive
    )
    lazy var streamOutput = CaptureStreamOutput(
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
    lazy var hotKeyManager = GlobalHotKeyManager { [weak self] slot in
        self?.activateShortcut(slot)
    }

    var stream: SCStream?
    var activeCaptureSource: WindowSource?
    var activeCaptureFormat: StageCaptureFormat?
    var capturesCursor = false
    var desiredCursorVisibility = false
    var isSwitchingStream = false
    var captureConfigurationUpdateTask: Task<Void, Never>?
    var keystrokeDismissTask: Task<Void, Never>?
    var clickDismissTasks: [UUID: Task<Void, Never>] = [:]
    var keystrokeMonitor: GlobalKeystrokeMonitor?
    var mouseClickMonitor: GlobalMouseClickMonitor?
    var spotlightPointerMonitor: GlobalPointerMonitor?
    var autoPresentationPointerMonitor: GlobalPointerMonitor?
    let sourceClickRipplePresenter = SourceClickRipplePresenter()
    let sourceSpotlightPresenter = SourceSpotlightPresenter()
    lazy var sourceAnnotationPresenter = SourceAnnotationPresenter()
    var workspaceMonitor: WorkspaceMonitor?
    var windowMonitoringTask: Task<Void, Never>?
    var windowRefreshTask: Task<Void, Never>?
    var queuedManualRefresh = false
    var awaitingLiveSelection: WindowSource?
    var firstFrameTimeoutTask: Task<Void, Never>?
    var pendingSelection: WindowSource?
    var selectionTask: Task<Void, Never>?
    var selectionGeneration = 0
    var requestedPermissionThisLaunch = false
    var resolvedPinnedWindowIDs: [Int: CGWindowID] = [:]

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
        let spotlightSize = presentationStore.spotlightSize
        let spotlightOutsideOpacity = presentationStore.spotlightOutsideOpacity
        self.spotlightSize = spotlightSize
        self.spotlightOutsideOpacity = spotlightOutsideOpacity
        clickHighlightColor = presentationStore.clickHighlightColor
        clickHighlightSize = presentationStore.clickHighlightSize
        keystrokeHighlightSize = presentationStore.keystrokeHighlightSize
        keystrokeAppearance = presentationStore.keystrokeAppearance
        stageFrameStyle = presentationStore.stageFrameStyle
        stageFramePadding = presentationStore.stageFramePadding
        stageFrameCornerRadius = presentationStore.stageFrameCornerRadius
        stageFrameBlur = presentationStore.stageFrameBlur
        stageFrameShadow = presentationStore.stageFrameShadow
        autoZoomSize = presentationStore.autoZoomSize
        annotations = AnnotationSession(
            lifetimeSeconds: annotationLifetimeSeconds,
            inkColor: annotationColor
        )
        spotlight = SpotlightSession(
            size: spotlightSize,
            outsideOpacity: spotlightOutsideOpacity
        )
        highlightsMouseClicks = presentationStore.highlightsMouseClicks
        highlightsKeystrokes =
            presentationStore.highlightsKeystrokes
            && GlobalKeystrokeMonitor.hasAccessibilityPermission
        shortcutPins = shortcutStore.loadPins()
        shortcutExclusions = shortcutStore.loadExclusions()

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

    var isSpotlightVisible: Bool {
        SpotlightVisibilityPolicy.shouldShow(
            isEnabled: spotlightEnabled,
            captureState: state,
            hasActiveCapture: stream != nil,
            hasSelectedWindow: selectedWindowID != nil
        )
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

}
