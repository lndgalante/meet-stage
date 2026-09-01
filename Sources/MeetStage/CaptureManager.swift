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
    @Published var demoModeEnabled = false
    @Published var needsMicrophonePermission = false
    @Published var demoModeUnavailableReason: String?
    // Cached so the permission badge re-renders when trust changes; AXIsProcessTrusted
    // is only re-read via refreshAccessibilityTrust() (on activation and while listening).
    @Published var isAccessibilityTrustedForDemo = AccessibilityElementIndexer.isAccessibilityTrusted
    @Published var demoVoiceActions: DemoVoiceActions
    @Published var demoHighlightColor: PresentationColor
    @Published var demoZoomSize: PresentationSize
    @Published var demoSmartUnderstanding: Bool
    @Published var demoCloudConsented: Bool
    @Published var demoBrainProvider: DemoBrainProvider
    @Published var shortcutPins: [Int: PinnedWindow] = [:]
    @Published var shortcutExclusions: Set<PinnedWindow> = []
    @Published var globalShortcutModifier: GlobalShortcutModifier

    let annotationUndoManager = UndoManager()

    let renderer = SampleBufferRenderer()
    let annotations: AnnotationSession
    let spotlight: SpotlightSession
    let autoPresentation = AutoPresentationSession()
    let demoMode = DemoModeSession()

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
    let demoBrainRegistry: DemoBrainRegistry
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
        },
        onAnalyzableFrame: { [weak self] buffer, geometry in
            Task { @MainActor in
                self?.handleDemoAnalyzableFrame(buffer, geometry: geometry)
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
    lazy var sourceDemoOverlayPresenter = DemoSourceOverlayPresenter()
    var demoSpeechTranscriber: DemoSpeechListening?
    let demoEmbeddingMatcher = DemoEmbeddingMatcher()
    let demoModelResolver = DemoModelIntentResolver()
    func demoBrain(for provider: DemoBrainProvider) -> any DemoBrain {
        demoBrainRegistry.brain(for: provider)
    }
    var demoConversation = DemoConversation()
    /// In-memory cache of each provider's API key, so a voice command doesn't
    /// re-read the Keychain secret — and re-trigger the access prompt — every time.
    /// Primed on save; read from the Keychain at most once per provider per launch.
    var cachedBrainKeys: [DemoBrainProvider: String] = [:]
    var demoListeningStartTask: Task<Void, Never>?
    var demoIndexRefreshTask: Task<Void, Never>?
    var demoIndexWalkTask: Task<DemoElementIndex, Never>?
    var demoRecognitionTask: Task<Void, Never>?
    var demoRecognitionGeneration: UInt64 = 0
    var demoActionTask: Task<Void, Never>?
    var demoModelTask: Task<Void, Never>?
    var demoBrainTask: Task<Void, Never>?
    /// Invalidates cloud work across consent, provider, focus, and source
    /// changes. A generation is stronger than cancellation alone because a
    /// network stack can race cancellation with a completed response.
    var demoBrainGeneration = 0
    var demoSpotlightTask: Task<Void, Never>?
    var demoCommandGate = DemoCommandGate()
    var demoIndexGeneration = 0
    /// Ownership token for the auto-dismissing voice spotlight. Any manual
    /// spotlight toggle bumps it so the voice dismiss task never turns off a
    /// spotlight the presenter enabled themselves.
    var demoSpotlightGeneration = 0
    /// Label of the last control Demo Mode acted on, so the on-device model can
    /// resolve pronouns like "click it back".
    var lastReferencedControl: String?
    // Real value is set in init once the persisted provider is known.
    @Published var hasDemoBrainKey = false
    var demoBrainRequestGate = DemoBrainRequestGate()
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

    init(
        defaults: UserDefaults = .standard,
        stageLogoStore: StageLogoStore = .live(),
        thumbnailLoader: any WindowThumbnailLoading = WindowThumbnailLoader(),
        demoBrainRegistry: DemoBrainRegistry = .live()
    ) {
        let shortcutStore = ShortcutPreferencesStore(defaults: defaults)
        let presentationStore = PresentationPreferencesStore(defaults: defaults)
        let inactiveStageAspectRatio = StageWindowSizing.currentScreenAspectRatio()
        self.shortcutStore = shortcutStore
        self.presentationStore = presentationStore
        self.stageLogoStore = stageLogoStore
        self.thumbnailLoader = thumbnailLoader
        self.demoBrainRegistry = demoBrainRegistry
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
        demoVoiceActions = presentationStore.demoVoiceActions
        demoHighlightColor = presentationStore.demoHighlightColor
        demoZoomSize = presentationStore.demoZoomSize
        demoSmartUnderstanding = presentationStore.demoSmartUnderstanding
        demoCloudConsented = presentationStore.demoCloudConsented
        let demoBrainProvider = presentationStore.demoBrainProvider
        self.demoBrainProvider = demoBrainProvider
        hasDemoBrainKey = demoBrainProvider.keyStore.hasKey
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
        // Demo Mode requires the microphone; re-gate the persisted flag against
        // live authorization so a revoked permission cannot silently arm it.
        demoModeEnabled =
            presentationStore.demoModeEnabled
            && DemoSpeechTranscriber.isMicrophoneAuthorized
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
        demoListeningStartTask?.cancel()
        demoIndexRefreshTask?.cancel()
        demoIndexWalkTask?.cancel()
        demoRecognitionTask?.cancel()
        demoActionTask?.cancel()
        demoModelTask?.cancel()
        demoBrainTask?.cancel()
        demoSpotlightTask?.cancel()
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
