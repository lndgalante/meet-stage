import AppKit
import CoreMedia
import ScreenCaptureKit

/// Coordinates source discovery, ScreenCaptureKit lifecycle, and UI-facing state.
@MainActor
final class CaptureManager: ObservableObject {
    static let shared = CaptureManager()
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
    @Published var stageLogo: NSImage?
    @Published var annotationLifetimeSeconds: Int
    @Published var annotationColor: PresentationColor
    @Published var clickHighlightColor: PresentationColor
    @Published var clickHighlightSize: PresentationSize
    @Published var keystrokeHighlightSize: PresentationSize
    @Published var keystrokeAppearance: KeystrokeAppearance
    @Published var shortcutPins: [Int: PinnedWindow] = [:]
    @Published var shortcutExclusions: Set<PinnedWindow> = []
    @Published var globalShortcutModifier: GlobalShortcutModifier

    let annotationUndoManager = UndoManager()

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
    let stageLogoStore: StageLogoStore
    let thumbnailLoader: any WindowThumbnailLoading
    let screenRecordingAuthorization: any ScreenRecordingAuthorizing
    let inactiveStageAspectRatio: CGFloat
    let sampleQueue = DispatchQueue(
        label: "dev.poc.meetstage.screen-frames",
        qos: .userInteractive
    )
    lazy var streamOutput = CaptureStreamOutput(
        renderer: renderer,
        onFrame: { [weak self] sourceStreamID, frame in
            Task { @MainActor in
                self?.handleFrame(from: sourceStreamID, frame: frame)
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
    var presentationPointerMonitor: GlobalPointerMonitor?
    let sourceClickRipplePresenter = SourceClickRipplePresenter()
    let sourceSpotlightPresenter = SourceSpotlightPresenter()
    lazy var sourceAnnotationPresenter = SourceAnnotationPresenter()
    var workspaceMonitor: WorkspaceMonitor?
    var windowMonitoringTask: Task<Void, Never>?
    var windowRefreshTask: Task<Void, Never>?
    var queuedManualRefresh = false
    var awaitingLiveSelection: WindowSource?
    var awaitingLiveSelectionRenderGeneration: UInt64?
    var liveRenderGeneration: UInt64?
    var firstFrameTimeoutTask: Task<Void, Never>?
    var pendingSelection: WindowSource?
    var selectionTask: Task<Void, Never>?
    var selectionGeneration = 0
    var requestedPermissionThisLaunch = false
    var resolvedPinnedWindowIDs: [Int: CGWindowID] = [:]

    // MARK: - Initialization

    init(
        defaults: UserDefaults = .standard,
        stageLogoStore: StageLogoStore = .live(),
        thumbnailLoader: any WindowThumbnailLoading = WindowThumbnailLoader(),
        screenRecordingAuthorization: any ScreenRecordingAuthorizing = SystemScreenRecordingAuthorization()
    ) {
        let shortcutStore = ShortcutPreferencesStore(defaults: defaults)
        let presentationStore = PresentationPreferencesStore(defaults: defaults)
        let inactiveStageAspectRatio = StageWindowSizing.currentScreenAspectRatio()
        self.shortcutStore = shortcutStore
        self.presentationStore = presentationStore
        self.stageLogoStore = stageLogoStore
        self.thumbnailLoader = thumbnailLoader
        self.screenRecordingAuthorization = screenRecordingAuthorization
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
        if let legacyLogoData = presentationStore.legacyStageLogoData {
            if let migratedLogo = try? stageLogoStore.save(importedData: legacyLogoData) {
                stageLogo = migratedLogo
                presentationStore.stageLogoStorageVersion = StageLogoStore.storageVersion
                presentationStore.legacyStageLogoData = nil
            } else {
                stageLogo = nil
                // Corrupt legacy data can never become a logo; clear it so each
                // launch does not repeat an expensive migration attempt. A valid
                // image is retained when only the filesystem write failed.
                if (try? StageLogoStore.normalizedPNG(from: legacyLogoData)) == nil {
                    presentationStore.legacyStageLogoData = nil
                }
            }
        } else if presentationStore.stageLogoStorageVersion == StageLogoStore.storageVersion {
            let storedLogo = stageLogoStore.load()
            stageLogo = storedLogo
            if storedLogo == nil {
                presentationStore.stageLogoStorageVersion = nil
            }
        } else {
            stageLogo = nil
        }
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
        globalShortcutModifier = shortcutStore.loadGlobalShortcutModifier()

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
