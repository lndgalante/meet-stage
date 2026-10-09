import AppKit
import Combine

/// What happens once the app is back at its start.
enum AfterReturn: Equatable, Sendable { case verify, ready, compose, play }

enum PauseReason: Equatable, Sendable {
    case user, userInput, sourceChanged
    case error(DemoError)

    var message: String? {
        switch self {
        case .user: nil
        case .userInput: "Paused because you clicked or typed in the app."
        case .sourceChanged: "Paused because the shared window changed."
        case .error(let error): error.localizedDescription
        }
    }
}

enum DemoPhase: Equatable, Sendable {
    case composing
    case scouting
    case scoutPaused(ScoutStop)
    case returning(then: AfterReturn)
    case needsStart(StartMismatch, then: AfterReturn)
    case ready
    case running(ReplayMode, next: Int, current: Int?)
    case paused(ReplayMode, next: Int, current: Int?, reason: PauseReason)
    case offTrack(ReplayMode, index: Int, Mismatch)
    case finished

    /// Whether BetterMeets is driving the source app right now.
    var isActuating: Bool {
        switch self {
        case .scouting, .returning, .running: true
        default: false
        }
    }

    /// Playing for an audience (running or paused), when the microphone may listen.
    var isPresenting: Bool {
        switch self {
        case .running(.present, _, _), .paused(.present, _, _, _): true
        default: false
        }
    }

    var replayMode: ReplayMode? {
        switch self {
        case .running(let mode, _, _), .paused(let mode, _, _, _), .offTrack(let mode, _, _): mode
        default: nil
        }
    }

    var currentStep: Int? {
        switch self {
        case .running(_, _, let current), .paused(_, _, let current, _): current
        case .offTrack(_, let index, _): index
        default: nil
        }
    }

    var nextStep: Int {
        switch self {
        case .running(_, let next, _), .paused(_, let next, _, _): next
        case .offTrack(_, let index, _): index
        default: 0
        }
    }
}

extension ScoutStop {
    /// Stops that simply interrupted the build, so building can continue.
    var canKeepBuilding: Bool {
        switch self {
        case .user, .userInput, .focusLost, .relaunched, .leftScope, .error: true
        case .needsApproval, .blocked, .limit: false
        }
    }
}

/// Asked inline, the first time Build needs it.
enum BuildSetup: Equatable, Sendable {
    /// An Anthropic API key.
    case key
    /// Permission to show Claude this app and operate it in the background.
    case consent
}

/// Something the Demo menu asks the demo panel to open, since the panel owns its sheet and dialogs.
enum DemoPanelRequest: Sendable {
    case new, edit, rename, delete
}

private struct DemoUserInput: Sendable {
    var windowNumber: Int64
    var location: CGPoint?
    var isKey: Bool
    /// The key pressed without Command, Control or Option, if it was a key.
    var plainKeyCode: UInt16?
}

/// What presentation remotes send: Right, Page Down or Space to go on; Left or Page Up to go back.
private enum RemoteKey {
    static let forward: Set<UInt16> = [124, 121, 49]
    static let back: Set<UInt16> = [123, 116]
}

/// Owns the open demo for the selected app, and every transition between
/// building, returning to the start, checking, presenting and pausing.
/// Building and checking drive the app in the background while the presenter
/// watches the stage; presenting brings the app to the front.
@MainActor
final class DemoSession: ObservableObject {
    @Published var prompt = "" {
        didSet {
            // A draft belongs to the request field; an open demo's request isn't one.
            guard prompt != oldValue, demo == nil, let selectedSource else { return }
            library.savePrompt(prompt, for: selectedSource)
        }
    }
    @Published private(set) var demo: RealTimeDemo?
    @Published private(set) var phase: DemoPhase = .composing {
        didSet {
            guard phase != oldValue else { return }
            phaseChanged(from: oldValue)
        }
    }
    @Published private(set) var activity = ""
    @Published private(set) var selectedSource: DemoSource?
    @Published private var liveSource: DemoSource?
    @Published private(set) var notice: String?
    @Published private(set) var recheckSuggested = false
    /// What Build is waiting for before it can start.
    @Published private(set) var buildSetup: BuildSetup?
    /// Claude's demo ideas for the selected app, built on its own features.
    @Published private(set) var ideas: [DemoIdea] = []
    @Published private(set) var isFindingIdeas = false
    /// The presenter has answered the one-time question about Claude access.
    @Published private(set) var consentAnswered: Bool {
        didSet { defaults.set(consentAnswered, forKey: "demo.consentAnswered") }
    }
    @Published var playbackSpeed: DemoPlaybackSpeed {
        didSet { defaults.set(playbackSpeed.rawValue, forKey: "demo.playbackSpeed") }
    }
    @Published var pausesAfterEachStep: Bool {
        didSet { defaults.set(pausesAfterEachStep, forKey: "demo.pauseEachStep") }
    }
    @Published var allowsAI: Bool {
        didSet {
            defaults.set(allowsAI, forKey: Self.consentKey)
            if !allowsAI, phase == .scouting { stopBuilding(.error(.missingConsent)) }
        }
    }
    @Published private(set) var hasKey: Bool
    /// The demo whose narration Claude is rewriting as one story.
    @Published private var scriptDemoID: UUID?
    /// Why the last script rewrite failed, shown with the script.
    @Published private(set) var scriptError: String?
    @Published var scriptTone: ScriptTone {
        didSet { defaults.set(scriptTone.rawValue, forKey: "demo.scriptTone") }
    }
    /// The language builds and rewrites write the narration in.
    @Published var scriptLanguage: ScriptLanguage {
        didSet {
            guard scriptLanguage != oldValue else { return }
            defaults.set(scriptLanguage.rawValue, forKey: "demo.scriptLanguage")
            findIdeas()
        }
    }
    @Published var scriptAudience: String {
        didSet { defaults.set(scriptAudience, forKey: "demo.scriptAudience") }
    }
    @Published private(set) var teleprompterVisible = false
    /// Set by the Demo menu; the panel handles it and sets it back to nil.
    @Published var panelRequest: DemoPanelRequest?
    @Published var opensTeleprompter: Bool {
        didSet { defaults.set(opensTeleprompter, forKey: "demo.opensNotes") }
    }
    let prompter: PresenterPrompter

    static let consentKey = "demo.allowsAIControl.v2"

    private let defaults: UserDefaults
    @Published private var library: DemoLibrary
    private let model: any DemoModeling
    private let driver: any DemoDriving
    private let keyStore: any DemoKeyStore
    private let observesUserInput: Bool
    private let scoutLimits: DemoScout.Limits
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var boundSource: DemoSource?
    private var scout: DemoScout?
    private var verifyEngine: DemoReplayEngine?
    /// A request to build once the app is back at its start (Show … Instead).
    private var pendingRebuild: String?
    /// The demo that was open when New Demo was chosen, for Cancel.
    private var demoBeforeNew: UUID?
    /// The step to present from once the app is back at its start (Previous Step).
    private(set) var rewindTarget: Int?
    private var ideasTask: Task<Void, Never>?
    /// Lets the last highlight of a finished run linger, then fades it.
    private var cueFadeTask: Task<Void, Never>?
    /// How long a finished run's last highlight stays before it fades.
    var finalCueHold = Duration.seconds(2)
    /// Ideas already found, by app and site, so the request field fills at once.
    private var ideasCache: [String: [DemoIdea]]
    private var interactionMonitor: GlobalLocalEventMonitor<DemoUserInput>?
    private var scriptTask: Task<Void, Never>?
    private var prompterChanges: AnyCancellable?
    /// Catches a presentation remote's keys in BetterMeets' own windows while presenting.
    private var remoteKeyMonitor: Any?
    private lazy var toast = DemoToastController()
    /// A build or check is running whose result the presenter should hear about,
    /// even if they've switched to another app meanwhile.
    private var announcesResult = false
    private let opensWindows: Bool
    private lazy var teleprompter: TeleprompterController = {
        let controller = TeleprompterController()
        controller.onClose = { [weak self] in self?.teleprompterVisible = false }
        return controller
    }()
    /// Test hook: fixed holds and gate timeouts for replays.
    var replayTuning: (holdOverride: Double?, gateTimeout: Duration?) = (nil, nil)

    init(
        driver: any DemoDriving, defaults: UserDefaults = .standard, model: any DemoModeling = DemoModelClient(),
        keyStore: any DemoKeyStore = DemoSession.keyStore, observesUserInput: Bool = true,
        scoutLimits: DemoScout.Limits = DemoScout.Limits(), opensWindows: Bool = true
    ) {
        self.driver = driver
        self.defaults = defaults
        library = DemoLibrary(defaults: defaults)
        self.model = model
        self.keyStore = keyStore
        self.observesUserInput = observesUserInput
        self.scoutLimits = scoutLimits
        self.opensWindows = opensWindows
        prompter = PresenterPrompter(defaults: defaults)
        scriptTone = ScriptTone(rawValue: defaults.string(forKey: "demo.scriptTone") ?? "") ?? .conversational
        scriptLanguage = ScriptLanguage(rawValue: defaults.string(forKey: "demo.scriptLanguage") ?? "") ?? .automatic
        scriptAudience = defaults.string(forKey: "demo.scriptAudience") ?? ""
        opensTeleprompter = defaults.object(forKey: "demo.opensNotes") as? Bool ?? true
        hasKey = keyStore.hasKey
        allowsAI = defaults.bool(forKey: Self.consentKey)
        consentAnswered = defaults.bool(forKey: "demo.consentAnswered")
        ideasCache =
            defaults.data(forKey: Self.ideasCacheKey).flatMap {
                try? JSONDecoder().decode([String: [DemoIdea]].self, from: $0)
            } ?? [:]
        pausesAfterEachStep = defaults.object(forKey: "demo.pauseEachStep") as? Bool ?? false
        playbackSpeed = DemoPlaybackSpeed(rawValue: defaults.double(forKey: "demo.playbackSpeed")) ?? .fast
        selectedSource = driver.selectedSource
        liveSource = driver.source
        loadSelectedDemo()
        // Views that observe the session also show the voice setting and the current line.
        prompterChanges = prompter.$followsVoice.map { _ in () }.merge(with: prompter.$line.map { _ in () })
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    static let keyStore = KeychainSecret(
        service: "com.lndgalante.bettermeets.anthropic", account: "conversational-brain",
        environmentVariable: "ANTHROPIC_API_KEY", legacyServices: ["dev.poc.meetstage.anthropic"]
    )

    deinit {
        task?.cancel()
        scriptTask?.cancel()
    }

    // MARK: Derived state

    var isBusy: Bool { phase.isActuating }

    /// Claude is rewriting the open demo's narration.
    var isWritingScript: Bool { scriptDemoID != nil && scriptDemoID == demo?.id }

    var diagnosticDetails: String? {
        switch phase {
        case .scoutPaused(.error(let error)): error.diagnosticDetails
        case .paused(_, _, _, .error(let error)): error.diagnosticDetails
        default: nil
        }
    }

    var isLiveSourceSelected: Bool { liveSource != nil && liveSource == selectedSource }

    /// Go to Start can take the app there itself, through the start page's address or a sidebar item.
    var canReturnAutomatically: Bool { demo?.start?.url != nil || demo?.start?.returnAnchor != nil }

    /// Every demo saved for the selected app, in the order they were made.
    var savedDemos: [RealTimeDemo] { selectedSource.map(library.demos(for:)) ?? [] }

    var canBuild: Bool {
        !isBusy && isLiveSourceSelected && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && prompt.count <= 4_000
    }

    var canPlay: Bool {
        guard !isBusy, isLiveSourceSelected, let demo, demo.isCompiled, let source = liveSource else { return false }
        return demo.app.matches(source)
    }

    /// True when the last check still applies to this app version, window size,
    /// start, and every action.
    var isChecked: Bool {
        guard let demo, case .checked(let verification) = demo.status, let source = liveSource,
            let info = try? driver.appInfo(for: source)
        else { return false }
        return verification.fingerprint
            == DemoFingerprint.make(
                demo, appVersion: info.appVersion, sizeClass: info.sizeClass, window: info.windowBucket)
    }

    var scoutedSteps: Int {
        guard let draft = demo?.draft else { return demo?.steps.count ?? 0 }
        return ScoutCompaction.compact(draft.records).count
    }

    /// The scout's outline, with a beat counted as covered for each batch of
    /// highlights it recorded.
    var outlineProgress: [(title: String, done: Bool)] {
        guard let demo else { return [] }
        let presented = (demo.draft?.records ?? []).filter { record in
            record.steps.contains { !$0.action.isMutating }
        }.count
        let covered = demo.draft == nil ? demo.outline.count : presented
        return demo.outline.enumerated().map { ($0.element, $0.offset < covered) }
    }

    // MARK: Keys and consent

    @discardableResult
    func saveKey(_ key: String) -> Bool {
        pause()
        guard keyStore.save(key) else {
            notice = DemoError.keychain.localizedDescription
            return false
        }
        hasKey = keyStore.hasKey
        notice = nil
        if buildSetup == .key, hasKey {
            buildSetup = nil
            build()
        }
        findIdeas()
        return true
    }

    private func authorizedKey() throws -> String {
        guard allowsAI else { throw DemoError.missingConsent }
        guard let key = keyStore.key, !key.isEmpty else { throw DemoError.missingKey }
        return key
    }

    /// Asked once, the first time BetterMeets opens, or when Build needs it after "Not Now".
    var asksForConsent: Bool {
        !allowsAI && (buildSetup == .consent || !consentAnswered)
    }

    /// Lets Claude see and operate the selected window for every app, then
    /// builds if Build was waiting for it.
    func allowClaude() {
        allowsAI = true
        consentAnswered = true
        findIdeas()
        guard buildSetup == .consent else { return }
        buildSetup = nil
        build()
    }

    func cancelBuildSetup() {
        if buildSetup == .consent || !allowsAI { consentAnswered = true }
        buildSetup = nil
    }

    // MARK: Building

    func build() {
        sourceDidChange()
        guard canBuild, let source = driver.source else { return }
        ideasTask?.cancel()
        guard hasKey else {
            buildSetup = .key
            return
        }
        guard allowsAI else {
            buildSetup = .consent
            return
        }
        do {
            let key = try authorizedKey()
            let info = try driver.appInfo(for: source)
            let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            cancelWork()
            recheckSuggested = false
            notice = nil
            let title = request.split(whereSeparator: \.isNewline).first.map { String($0.prefix(60)) } ?? "Demo"
            demo = RealTimeDemo(
                prompt: request,
                app: DemoAppKey(
                    bundleID: source.bundleID, appName: source.name, engine: info.engine, isBrowser: info.isBrowser),
                title: title, status: .draft(ScoutDraft()))
            persist()
            announcesResult = true
            startScout(source: source, key: key)
        } catch {
            notice = error.localizedDescription
        }
    }

    func keepBuilding() {
        guard case .scoutPaused(let stop) = phase, stop.canKeepBuilding else { return }
        resumeScout()
    }

    func allowPending() {
        guard case .scoutPaused(.needsApproval(let pending)) = phase else { return }
        resumeScout(approved: pending)
    }

    func skipPending() {
        guard case .scoutPaused(.needsApproval(let pending)) = phase else { return }
        resumeScout(skipped: pending)
    }

    /// Back to the request field, after returning the app to where the build started.
    func editRequest() {
        guard case .scoutPaused = phase else { return }
        if demo?.start != nil, isLiveSourceSelected { returnToStart(then: .compose) } else { finishCompose() }
    }

    /// Builds the closest alternative Claude suggested, from the start.
    func buildAlternative(_ request: String) {
        guard case .scoutPaused = phase else { return }
        pendingRebuild = request
        editRequest()
    }

    /// Accepts the steps recorded so far and checks them.
    func useRecordedSteps() {
        guard case .scoutPaused = phase, isLiveSourceSelected, driver.source != nil, var demo,
            let draft = demo.draft, demo.start != nil
        else { return }
        let steps = ScoutCompaction.compact(draft.records)
        guard !steps.isEmpty else { return }
        demo.steps = steps
        demo.status = .recorded
        demo.revision += 1
        self.demo = demo
        persist()
        if let key = try? authorizedKey() { writeScript(key: key) }
        returnToStart(then: .verify)
    }

    /// Forgets the draft after taking the app back to where the build started.
    func discardDraft() {
        guard case .scoutPaused = phase else { return }
        if demo?.start != nil, isLiveSourceSelected { returnToStart(then: .compose) } else { finishCompose() }
    }

    private func resumeScout(approved: PendingApproval? = nil, skipped: PendingApproval? = nil) {
        guard case .scoutPaused = phase, let source = driver.source, isLiveSourceSelected, demo?.draft != nil else {
            return
        }
        do {
            let key = try authorizedKey()
            driver.show(nil)
            startScout(source: source, key: key, approved: approved, skipped: skipped)
        } catch {
            phase = .scoutPaused(.error(error as? DemoError ?? .invalidResponse))
        }
    }

    private func startScout(
        source: DemoSource, key: String, approved: PendingApproval? = nil, skipped: PendingApproval? = nil
    ) {
        guard let demo else { return }
        cancelWork()
        let id = runID
        boundSource = source
        phase = .scouting
        activity = "Getting ready"
        notice = nil
        watchForInteraction()
        do {
            scout = try DemoScout(
                demo: demo, source: source, driver: driver, model: model, key: key, limits: scoutLimits,
                language: scriptLanguage,
                check: { [weak self] in
                    guard let self else { throw CancellationError() }
                    try self.checkRun(id, source: source)
                },
                onUpdate: { [weak self] demo, activity in
                    guard let self, self.runID == id else { return }
                    self.demo = demo
                    if !activity.isEmpty { self.activity = activity }
                    self.persist()
                })
        } catch {
            phase = .scoutPaused(.error(error as? DemoError ?? .invalidResponse))
            return
        }
        let scout = scout
        task = Task { [weak self] in
            guard let self, let scout else { return }
            do {
                let result = try await scout.run(approved: approved, skipped: skipped)
                try checkRun(id, source: source)
                stopMonitoring()
                driver.show(nil)
                task = nil
                switch result {
                case .finished:
                    var demo = scout.demo
                    demo.steps = ScoutCompaction.compact(demo.draft?.records ?? [])
                    demo.status = .recorded
                    demo.revision += 1
                    self.demo = demo
                    persist()
                    // Words don't affect the check, so the script is written while it runs.
                    writeScript(key: key)
                    returnToStart(then: .verify)
                case .stopped(let stop):
                    self.demo = scout.demo
                    persist()
                    phase = .scoutPaused(stop)
                    if case .needsApproval(let pending) = stop, let rect = pending.rect {
                        driver.show(DemoCue(effect: .draw, rect: rect))
                    }
                }
            } catch {
                guard runID == id else { return }
                stopMonitoring()
                task = nil
                scout.interrupt(byUserInput: false)
                self.demo = scout.demo
                persist()
                phase = .scoutPaused(scoutStop(for: error))
            }
        }
    }

    private func scoutStop(for error: Error) -> ScoutStop {
        switch error {
        case DemoError.focusChanged: .focusLost
        case let error as DemoError: .error(error)
        case is CancellationError: .user
        default: .error(.invalidResponse)
        }
    }

    private func stopBuilding(_ stop: ScoutStop) {
        guard phase == .scouting else { return }
        cancelWork()
        scout?.interrupt(byUserInput: stop == .userInput)
        if let scout { demo = scout.demo }
        persist()
        driver.show(nil)
        phase = .scoutPaused(stop)
        activity = ""
    }

    // MARK: Start

    /// Takes the app back to the start, keeping whatever was meant to happen there.
    func returnToStart() {
        switch phase {
        case .needsStart(_, let then): returnToStart(then: then)
        case .ready, .finished, .paused, .offTrack: returnToStart(then: .ready)
        default: break
        }
    }

    func checkAgain() {
        guard !isBusy, demo?.isCompiled == true, isLiveSourceSelected else { return }
        recheckSuggested = false
        announcesResult = true
        returnToStart(then: .verify)
    }

    /// Re-checks whether the presenter reached the start by hand.
    func checkStart() {
        guard case .needsStart(let current, let then) = phase, let source = driver.source, isLiveSourceSelected,
            let demo
        else { return }
        cancelWork()
        let id = runID
        notice = nil
        activity = "Looking for the starting screen"
        task = Task { [weak self] in
            guard let self else { return }
            let engine = makeEngine(demo: demo, source: source, mode: .present, id: id)
            do {
                let mismatch = try await engine.readiness()
                try checkRun(id, source: source)
                task = nil
                activity = ""
                if let mismatch {
                    notice = "Still not at the start."
                    enterNeedsStart(keeping(current, over: mismatch, demo: demo), then: then, source: source)
                } else {
                    proceed(then)
                }
            } catch {
                guard runID == id else { return }
                task = nil
                activity = ""
                if !(error is CancellationError) { notice = error.localizedDescription }
                enterNeedsStart(current, then: then, source: source)
            }
        }
    }

    private func returnToStart(then: AfterReturn) {
        guard let source = driver.source, isLiveSourceSelected, let demo, demo.start != nil else {
            if then == .compose {
                finishCompose()
            } else if case .needsStart = phase {
            } else {
                phase = .needsStart(.noAutomaticReturn, then: then)
            }
            return
        }
        cancelWork()
        let id = runID
        boundSource = source
        verifyEngine = nil
        notice = nil
        phase = .returning(then: then)
        activity = "Going back to the start"
        watchForInteraction()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let engine = makeEngine(demo: demo, source: source, mode: .present, id: id)
                let mismatch = try await engine.returnToStart()
                try checkRun(id, source: source)
                stopMonitoring()
                task = nil
                driver.movePointer(to: nil, duration: 0)
                if let mismatch {
                    enterNeedsStart(mismatch, then: then, source: source)
                } else {
                    proceed(then)
                }
            } catch {
                guard runID == id else { return }
                stopMonitoring()
                task = nil
                if then == .compose {
                    finishCompose()
                } else {
                    if !(error is CancellationError) { notice = error.localizedDescription }
                    enterNeedsStart(.noAutomaticReturn, then: then, source: source)
                }
            }
        }
    }

    /// A manual-return mismatch stays manual: a later poll seeing "wrong screen"
    /// must not swap Check for an automatic return that can't work.
    private func keeping(_ current: StartMismatch, over next: StartMismatch, demo: RealTimeDemo) -> StartMismatch {
        if current == .noAutomaticReturn, next == .wrongScreen { return .noAutomaticReturn }
        if next == .wrongScreen, demo.start?.url == nil, demo.start?.returnAnchor == nil { return .noAutomaticReturn }
        return next
    }

    private func enterNeedsStart(_ mismatch: StartMismatch, then: AfterReturn, source: DemoSource) {
        phase = .needsStart(mismatch, then: then)
        activity = ""
        pollForStart(then: then, source: source)
    }

    /// While waiting at needsStart, notices when the presenter gets there by hand.
    private func pollForStart(then: AfterReturn, source: DemoSource) {
        guard let demo else { return }
        let id = runID
        task?.cancel()
        task = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.runID == id, case .needsStart(let current, _) = self.phase else { return }
                let engine = self.makeEngine(demo: demo, source: source, mode: .present, id: id)
                do {
                    let mismatch = try await engine.readiness()
                    guard self.runID == id, (try? self.checkRun(id, source: source)) != nil else { return }
                    if let mismatch {
                        let next = self.keeping(current, over: mismatch, demo: demo)
                        if next != current { self.phase = .needsStart(next, then: then) }
                    } else {
                        self.task = nil
                        self.proceed(then)
                        return
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func proceed(_ then: AfterReturn) {
        switch then {
        case .verify: startReplay(mode: .verify, from: 0)
        case .play:
            let target = rewindTarget ?? 0
            rewindTarget = nil
            startReplay(mode: .present, from: 0, startsFromTop: target == 0, rewindTo: target > 0 ? target : nil)
        case .ready:
            phase = .ready
            activity = ""
        case .compose: finishCompose()
        }
    }

    private func finishCompose() {
        cancelWork()
        announcesResult = false
        let request = demo?.prompt
        if let demo, demo.draft != nil { library.remove(id: demo.id) }
        demo = nil
        if let selectedSource { library.selectNewDemo(for: selectedSource) }
        if let request { prompt = request }
        driver.show(nil)
        driver.movePointer(to: nil, duration: 0)
        phase = .composing
        activity = ""
        if let rebuild = pendingRebuild {
            pendingRebuild = nil
            prompt = rebuild
            build()
        }
    }

    // MARK: Playback

    func play(singleStep: Bool = false) {
        sourceDidChange()
        rewindTarget = nil
        switch phase {
        case .ready, .finished:
            startReplay(mode: .present, from: 0, singleStep: singleStep, checkStart: true, startsFromTop: true)
        case .needsStart(_, .ready), .needsStart(_, .play):
            startReplay(mode: .present, from: 0, singleStep: singleStep, startsFromTop: true)
        case .paused(let mode, let next, _, _):
            startReplay(mode: mode, from: next, singleStep: singleStep && mode == .present)
        case .offTrack(let mode, let index, _):
            startReplay(mode: mode, from: index, singleStep: singleStep && mode == .present)
        case .scoutPaused(let stop) where stop.canKeepBuilding:
            keepBuilding()
        default:
            break
        }
    }

    /// Presents the step before the current one again. Steps change the app, so
    /// it goes back to the start and quickly replays the actions up to there.
    func previousStep() {
        guard let demo, demo.isCompiled, phase == .finished || phase.replayMode == .present else { return }
        let current = phase == .finished ? demo.steps.count : phase.currentStep ?? phase.nextStep
        rewind(to: max(0, current - 1))
    }

    /// Presents the demo again from the opening line.
    func startOver() {
        guard phase == .ready || phase == .finished || phase.replayMode == .present else { return }
        rewind(to: 0)
    }

    private func rewind(to step: Int) {
        guard isLiveSourceSelected, let demo, demo.isCompiled, let source = driver.source else { return }
        cancelWork()
        bringToFront(source)
        rewindTarget = step
        if step > 0 { showLine(for: step, in: demo) }
        returnToStart(then: .play)
    }

    /// Presenting happens in the app itself, so Play brings its window to the front.
    /// Building and testing stay in the background while the presenter watches the stage.
    private func bringToFront(_ source: DemoSource) {
        Task { [driver] in await driver.bringToFront(source) }
    }

    func skipStep() {
        guard case .offTrack(.present, let index, _) = phase else { return }
        startReplay(mode: .present, from: index + 1)
    }

    func continueFromScreen() {
        guard case .offTrack(.present, _, .wrongScreen(let step)) = phase else { return }
        startReplay(mode: .present, from: step)
    }

    func pause() {
        switch phase {
        case .scouting:
            stopBuilding(.user)
        case .running(let mode, let next, let current):
            cancelWork()
            phase = .paused(mode, next: next, current: current, reason: .user)
            activity = ""
        case .returning(let then):
            cancelWork()
            stopReturning(then: then)
        default:
            break
        }
    }

    /// Leaves an interrupted return for the presenter to finish by hand, and
    /// notices when they get there. The presenter stopped it, so getting there
    /// only makes the demo ready; it never starts playing or testing by itself.
    private func stopReturning(then: AfterReturn) {
        let then: AfterReturn = then == .compose ? .compose : .ready
        if let source = boundSource ?? driver.source {
            enterNeedsStart(.noAutomaticReturn, then: then, source: source)
        } else {
            phase = .needsStart(.noAutomaticReturn, then: then)
            activity = ""
        }
    }

    private func startReplay(
        mode: ReplayMode, from index: Int, singleStep: Bool = false, checkStart: Bool = false,
        startsFromTop: Bool = false, rewindTo: Int? = nil
    ) {
        guard let source = driver.source, isLiveSourceSelected, let demo, demo.isCompiled, demo.app.matches(source),
            index <= demo.steps.count
        else { return }
        guard index < demo.steps.count else {
            if mode == .present { phase = .finished }
            return
        }
        cancelWork()
        let id = runID
        boundSource = source
        notice = nil
        if mode == .present { bringToFront(source) }
        phase = .running(mode, next: index, current: nil)
        activity = mode == .verify ? "Step \(index + 1) of \(demo.steps.count)" : ""
        watchForInteraction()
        let engine: DemoReplayEngine
        if mode == .verify, index > 0, let existing = verifyEngine {
            // Keep what this check already learned; only the run changes.
            existing.rebind(hooks(id: id, source: source, steps: demo.steps.count))
            engine = existing
        } else {
            // The opening line belongs to a performance from the top, not to a resume.
            engine = makeEngine(
                demo: demo, source: source, mode: mode, id: id, singleStep: singleStep,
                playsOpening: mode == .present && index == 0 && startsFromTop, rewindTo: rewindTo)
            if mode == .verify { verifyEngine = engine }
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if checkStart, try await engine.readiness() != nil {
                    // Not at the start: go back there first, then perform from the top.
                    try checkRun(id, source: source)
                    stopMonitoring()
                    task = nil
                    returnToStart(then: .play)
                    return
                }
                let end = try await engine.run(from: index)
                try checkRun(id, source: source)
                stopMonitoring()
                task = nil
                if !engine.skippedBeats.isEmpty {
                    notice =
                        "Skipped \(engine.skippedBeats.map { "“\($0)”" }.joined(separator: ", ")); couldn’t find it."
                }
                if mode == .present, !engine.heals.isEmpty { recheckSuggested = true }
                switch end {
                case .completed:
                    if mode == .verify {
                        finishVerification(engine, source: source)
                    } else {
                        phase = .finished
                    }
                case .pausedAfter(let step):
                    phase = .paused(mode, next: step + 1, current: step, reason: .user)
                case .offTrack(let step, let mismatch):
                    phase = .offTrack(mode, index: step, mismatch)
                }
            } catch {
                guard runID == id else { return }
                stopMonitoring()
                task = nil
                let reason: PauseReason =
                    switch error {
                    case DemoError.sourceChanged: .sourceChanged
                    case let error as DemoError: .error(error)
                    case is CancellationError: .user
                    default: .error(.invalidResponse)
                    }
                if case .running(let mode, let next, let current) = phase {
                    phase = .paused(mode, next: next, current: current, reason: reason)
                }
            }
        }
    }

    private func hooks(
        id: UUID, source: DemoSource, steps: Int, playsOpening: Bool = false, rewindTo: Int? = nil
    ) -> DemoReplayEngine.Hooks {
        DemoReplayEngine.Hooks(
            check: { [weak self] in
                guard let self else { throw CancellationError() }
                try self.checkRun(id, source: source)
            },
            onStep: { [weak self] index, title in
                guard let self, self.runID == id, case .running(let mode, let next, _) = self.phase else { return }
                self.phase = .running(mode, next: next, current: index)
                if mode == .verify {
                    self.activity = "Step \(index + 1) of \(steps): \(title)"
                } else if let rewindTo, index < rewindTo {
                    // Catching up quietly; the line it's going back to is already showing.
                } else if let demo = self.demo, self.prompter.line != .step(index) {
                    self.showLine(for: index, in: demo)
                }
            },
            onCommit: { [weak self] next in
                guard let self, self.runID == id, case .running(let mode, _, let current) = self.phase else { return }
                self.phase = .running(mode, next: next, current: current)
            },
            hold: { [weak self] _, seconds in
                guard let self else { throw CancellationError() }
                try await self.prompter.hold(seconds: seconds)
            },
            opening: playsOpening
                ? { [weak self] in
                    guard let self, self.replayTuning.holdOverride == nil, let demo = self.demo,
                        let opening = demo.openingScript, !opening.isEmpty
                    else { return }
                    self.prompter.show(
                        .opening, text: opening, heading: "Opening", upNext: demo.steps.first?.title, position: nil)
                    try await self.prompter.hold(seconds: DemoStep.speakingTime(for: opening) + 0.6)
                } : nil)
    }

    private func makeEngine(
        demo: RealTimeDemo, source: DemoSource, mode: ReplayMode, id: UUID, singleStep: Bool = false,
        playsOpening: Bool = false, rewindTo: Int? = nil
    ) -> DemoReplayEngine {
        DemoReplayEngine(
            demo: demo, source: source, driver: driver, model: model,
            key: { [weak self] in
                guard let self, self.allowsAI else { return nil }
                return self.keyStore.key
            },
            options: .init(
                mode: mode, speed: playbackSpeed.rawValue,
                pausesAfterEachStep: mode == .present && pausesAfterEachStep, singleStep: singleStep,
                rewindTo: rewindTo, holdOverride: replayTuning.holdOverride, gateTimeout: replayTuning.gateTimeout),
            hooks: hooks(
                id: id, source: source, steps: demo.steps.count, playsOpening: playsOpening, rewindTo: rewindTo))
    }

    private func finishVerification(_ engine: DemoReplayEngine, source: DemoSource) {
        verifyEngine = nil
        guard engine.verifiedAllSteps, var checked = demo, checked.id == engine.demo.id,
            checked.steps.map(\.id) == engine.demo.steps.map(\.id), let info = try? driver.appInfo(for: source)
        else {
            notice = "The test run didn’t reach every step. Test it again from the start."
            phase = .ready
            return
        }
        // Take what the check learned (confirmed screens, healed targets, the
        // start) onto the current demo, keeping any script written meanwhile.
        for index in checked.steps.indices {
            checked.steps[index].pre = engine.demo.steps[index].pre
            checked.steps[index].action = engine.demo.steps[index].action
        }
        if let signature = engine.demo.start?.signature { checked.start?.signature = signature }
        checked.revision += 1
        checked.status = .checked(
            DemoVerification(
                checkedAt: Date(),
                fingerprint: DemoFingerprint.make(
                    checked, appVersion: info.appVersion, sizeClass: info.sizeClass, window: info.windowBucket)))
        demo = checked
        persist()
        returnToStart(then: .ready)
    }

    // MARK: Script

    /// Has Claude rewrite every line so the demo reads as one story. Only words
    /// change, so a check in progress or already passed still holds.
    func rewriteScript() {
        do {
            writeScript(key: try authorizedKey())
        } catch {
            scriptError = error.localizedDescription
        }
    }

    private func writeScript(key: String) {
        guard let demo, demo.isCompiled else { return }
        scriptTask?.cancel()
        let ids = demo.steps.map(\.id)
        let original = Dictionary(uniqueKeysWithValues: demo.steps.map { ($0.id, $0) })
        let originalLines = (opening: demo.openingScript, closing: demo.closingScript, label: demo.start?.label)
        let request = ScriptRequest(
            prompt: demo.prompt, appName: demo.app.appName, start: demo.start?.description ?? "",
            outline: demo.outline,
            steps: demo.steps.map { step in
                ScriptRequest.Step(
                    kind: step.action.kindLabel,
                    target: step.action.locators.map(\.displayName).joined(separator: ", "),
                    title: step.title, script: step.script, isNavigation: step.action.isMutating)
            }, tone: scriptTone, audience: scriptAudience, language: scriptLanguage)
        scriptDemoID = demo.id
        scriptError = nil
        scriptTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.scriptDemoID = nil } }
            do {
                let draft = try await model.writeScript(request, key: key)
                try Task.checkCancellation()
                applyScript(draft, to: ids, original: original, originalLines: originalLines, demoID: demo.id)
            } catch is CancellationError {
            } catch {
                AppLog.demoMode.error("Script rewrite failed: \(error.localizedDescription, privacy: .public)")
                if self.demo?.id == demo.id {
                    scriptError = "Couldn’t rewrite the script: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyScript(
        _ draft: ScriptDraft, to ids: [UUID], original: [UUID: DemoStep],
        originalLines: (opening: String?, closing: String, label: String?), demoID: UUID
    ) {
        // The presenter may have opened another demo meanwhile; the lines still go to this one.
        let isOpen = demo?.id == demoID
        guard var live = isOpen ? demo : library.demo(id: demoID) else { return }
        // Apply by step ID, and only to lines nobody edited while Claude was writing.
        let lines = Dictionary(uniqueKeysWithValues: zip(ids, zip(draft.titles, draft.scripts)))
        for index in live.steps.indices {
            let step = live.steps[index]
            guard let (title, script) = lines[step.id], let before = original[step.id],
                before.title == step.title, before.script == step.script, before.holdSeconds == step.holdSeconds
            else { continue }
            if !title.isEmpty { live.steps[index].title = title }
            live.steps[index].script = script
            live.steps[index].holdSeconds = DemoStep.hold(for: script, action: live.steps[index].action)
        }
        if live.openingScript == originalLines.opening { live.openingScript = draft.opening }
        if live.closingScript == originalLines.closing { live.closingScript = draft.closing }
        if !draft.startLabel.isEmpty, live.start?.label == originalLines.label { live.start?.label = draft.startLabel }
        live.revision += 1
        guard isOpen else {
            library.save(live)
            return
        }
        demo = live
        persist()
        if phase == .ready { previewPrompter() }
        // A check in progress keeps its own copy; it merges structure, not words.
    }

    // MARK: Ideas

    /// Asks Claude for demo ideas built on the core features the window shows,
    /// once per app (and per site, in a browser) unless `again`. Only with
    /// Claude access on, a saved key, and the request field showing.
    func findIdeas(again: Bool = false) {
        guard phase == .composing, demo == nil, hasKey, isLiveSourceSelected, let source = driver.source,
            let key = try? authorizedKey()
        else { return }
        ideasTask?.cancel()
        if !again { ideas = [] }
        ideasTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isFindingIdeas = false } }
            do {
                let snapshot = try await driver.snapshot(source, waitForContent: true)
                let cacheKey = Self.ideasKey(source, url: snapshot.webURL, language: scriptLanguage)
                if !again, let cached = ideasCache[cacheKey] {
                    ideas = cached
                    return
                }
                isFindingIdeas = true
                let screenshot = try await driver.screenshot(source)
                let request = IdeasRequest(
                    appName: source.name, screenshot: screenshot, elements: DemoSceneEncoder.encode(snapshot).text,
                    language: scriptLanguage)
                let found = try await model.ideas(request, key: key)
                try Task.checkCancellation()
                guard driver.source == source, !found.isEmpty else { return }
                ideas = found
                ideasCache[cacheKey] = found
                defaults.set(try? JSONEncoder().encode(ideasCache), forKey: Self.ideasCacheKey)
            } catch is CancellationError {
            } catch {
                AppLog.demoMode.error("Demo ideas failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static let ideasCacheKey = "demo.ideas.v1"

    private static func ideasKey(_ source: DemoSource, url: URL?, language: ScriptLanguage) -> String {
        [DemoLibrary.appKey(source), url?.host ?? "", language.rawValue].joined(separator: "|")
    }

    // MARK: Teleprompter

    func toggleTeleprompter() {
        teleprompterVisible ? hideTeleprompter() : showTeleprompter()
    }

    func showTeleprompter() {
        guard opensWindows else { return }
        teleprompter.show(demo: self)
        teleprompterVisible = true
        previewPrompter()
    }

    func hideTeleprompter() {
        guard opensWindows else { return }
        teleprompter.hide()
        teleprompterVisible = false
    }

    /// Moves past the current line now, while the demo waits for the presenter's voice.
    func skipLine() {
        prompter.skipLine()
    }

    /// Turns voice following on or off, and starts or stops the microphone to match.
    var followsVoice: Bool {
        get { prompter.followsVoice }
        set {
            prompter.followsVoice = newValue
            updateListening()
        }
    }

    /// Starts or stops listening to match voice following and what the demo is doing.
    func updateListening() {
        guard opensWindows, prompter.followsVoice, phase.isPresenting else {
            prompter.listener.stop()
            return
        }
        guard !prompter.listener.wantsToListen else { return }
        let script = scriptText
        let vocabulary = Array(
            Set(
                script.split(whereSeparator: \.isWhitespace)
                    .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                    .filter { $0.count > 3 })
        ).sorted()
        prompter.listener.requestStart(vocabulary: vocabulary, script: script)
    }

    private var scriptText: String {
        ([demo?.openingScript ?? "", demo?.closingScript ?? ""] + (demo?.steps.map(\.script) ?? []))
            .joined(separator: " ")
    }

    private func phaseChanged(from old: DemoPhase) {
        fadeFinalCueIfRunEnded(from: old)
        switch phase {
        case .running(.present, _, _):
            if old.replayMode != .present, opensTeleprompter { showTeleprompter() }
        case .finished:
            if let closing = demo?.closingScript, !closing.isEmpty {
                prompter.show(.closing, text: closing, heading: "Wrap up", upNext: nil, position: nil)
            } else {
                prompter.clear()
            }
        case .ready, .composing, .needsStart:
            previewPrompter()
            if phase == .composing { findIdeas() }
            if phase == .ready, old != .ready { prepareListener() }
        default:
            break
        }
        // Only a change between presenting and not presenting touches the microphone and the remote keys.
        if old.isPresenting != phase.isPresenting {
            updateListening()
            updateRemoteKeys()
        }
        announceIfAway()
    }

    /// Asks for the microphone and fetches the speech model now, not in front of an audience.
    private func prepareListener() {
        guard prompter.followsVoice, opensWindows else { return }
        let script = scriptText
        Task { await prompter.listener.prepare(script: script) }
    }

    /// A presentation or test run that ends keeps its last highlight on screen for
    /// a moment, then fades it, instead of leaving it up until the next action.
    private func fadeFinalCueIfRunEnded(from old: DemoPhase) {
        cueFadeTask?.cancel()
        cueFadeTask = nil
        let ended = phase == .finished || (phase == .ready && old.replayMode == .verify)
        guard ended else { return }
        let ending = phase
        cueFadeTask = Task { [weak self] in
            try? await Task.sleep(for: self?.finalCueHold ?? .zero)
            guard let self, !Task.isCancelled, self.phase == ending else { return }
            self.driver.fadeOutCue()
        }
    }

    /// When a build or check finishes, or needs the presenter, while they're in
    /// another app: come back to the front, or show a notice over that app.
    private func announceIfAway() {
        guard opensWindows, announcesResult, let content = announcement else { return }
        if content.kind == .ready || phase.isPresenting { announcesResult = false }
        guard !NSApp.isActive else { return }
        if content.kind == .ready {
            BetterMeetsWindowActions.showStage()
            // macOS may refuse to bring BetterMeets forward on its own; then say so where they are.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !NSApp.isActive else { return }
                self.toast.show(content)
            }
        } else {
            toast.show(content)
        }
    }

    private var announcement: DemoToastContent? {
        let title = demo?.title ?? "Your demo"
        switch phase {
        case .ready:
            let steps = demo?.steps.count ?? 0
            return DemoToastContent(
                kind: .ready, title: "Demo ready",
                detail: "\(title) · \(isChecked ? "Tested" : "Not tested") · \(steps) steps")
        case .scoutPaused(let stop) where stop != .user:
            return DemoToastContent(kind: .attention, title: "Your demo build needs you", detail: stop.message)
        case .needsStart(_, .verify):
            let start = demo?.start?.description ?? "the screen where the build started"
            return DemoToastContent(
                kind: .attention, title: "Go back to the start to finish the test run", detail: start)
        case .offTrack(.verify, let index, let mismatch):
            return DemoToastContent(
                kind: .attention, title: "The test run stopped at step \(index + 1)", detail: mismatch.message)
        default:
            return nil
        }
    }

    private func updateRemoteKeys() {
        if phase.isPresenting, opensWindows {
            guard remoteKeyMonitor == nil else { return }
            remoteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                    !(NSApp.keyWindow?.firstResponder is NSText)
                else { return event }
                return self.handleRemoteKey(event.keyCode) ? nil : event
            }
        } else if let remoteKeyMonitor {
            NSEvent.removeMonitor(remoteKeyMonitor)
            self.remoteKeyMonitor = nil
        }
    }

    /// Moves the demo for a presentation remote's key. False when the key means
    /// nothing now, so it goes on to the app.
    private func handleRemoteKey(_ keyCode: UInt16) -> Bool {
        guard phase.isPresenting else { return false }
        if RemoteKey.back.contains(keyCode) {
            previousStep()
            return true
        }
        // Going on only means something while the demo runs; going back works while paused too.
        guard RemoteKey.forward.contains(keyCode), case .running = phase else { return false }
        skipLine()
        return true
    }

    /// Before playing, the notes show the opening line (or the first step's).
    private func previewPrompter() {
        guard let demo, demo.isCompiled else {
            prompter.clear()
            return
        }
        switch phase {
        case .ready, .needsStart:
            if let opening = demo.openingScript, !opening.isEmpty {
                prompter.show(
                    .opening, text: opening, heading: "Opening", upNext: demo.steps.first?.title, position: nil)
            } else if !demo.steps.isEmpty {
                showLine(for: 0, in: demo)
            }
        default:
            break
        }
    }

    private func showLine(for index: Int, in demo: RealTimeDemo) {
        guard demo.steps.indices.contains(index) else { return }
        let step = demo.steps[index]
        let next = demo.steps.indices.contains(index + 1) ? demo.steps[index + 1].title : nil
        prompter.show(
            .step(index), text: step.script, heading: step.title, upNext: next,
            position: (index + 1, demo.steps.count))
    }

    // MARK: Editing

    /// Applies edited words, timing and removals onto the live demo, so a check
    /// that finished while the editor was open isn't overwritten.
    @discardableResult
    func updateDemo(_ edited: RealTimeDemo, base: RealTimeDemo? = nil) -> Bool {
        guard !isBusy, var live = demo, edited.id == live.id else { return false }
        // Apply only what the presenter changed in the editor, so a script rewritten
        // meanwhile survives for the lines they didn't touch.
        let base = base ?? live
        if edited.title != base.title { live.title = edited.title }
        if edited.openingScript != base.openingScript { live.openingScript = edited.openingScript }
        if edited.closingScript != base.closingScript { live.closingScript = edited.closingScript }
        if let description = edited.start?.description, description != base.start?.description {
            live.start?.description = description
        }
        if let start = edited.start, start.label != base.start?.label {
            let label = start.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            live.start?.label = label.isEmpty ? nil : label
        }
        let edits = Dictionary(uniqueKeysWithValues: edited.steps.map { ($0.id, $0) })
        let originals = Dictionary(uniqueKeysWithValues: base.steps.map { ($0.id, $0) })
        live.steps = live.steps.compactMap { step in
            guard let edit = edits[step.id] else { return originals[step.id] == nil ? step : nil }
            let original = originals[step.id] ?? step
            var step = step
            if edit.title != original.title { step.title = edit.title }
            if edit.script != original.script {
                step.script = edit.script
                // A step holds for as long as its line takes to say.
                step.holdSeconds = DemoStep.hold(for: edit.script, action: step.action)
            }
            return step
        }
        guard let validated = try? live.validated(), !validated.steps.isEmpty else { return false }
        live = validated
        live.revision += 1
        demo = live
        persist()
        switch phase {
        case .finished, .paused, .offTrack: phase = .ready
        default: break
        }
        if phase == .ready { previewPrompter() }
        return true
    }

    /// Renames the open demo without leaving its phase. Titles aren't part of the
    /// test's fingerprint, so a tested demo stays tested.
    func renameDemo(to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, var live = demo, live.isCompiled, !title.isEmpty else { return }
        live.title = String(title.prefix(80))
        live.revision += 1
        demo = live
        persist()
    }

    /// Opens the request field for another demo of this app. Saved demos stay.
    func newDemo() {
        // Again while composing would forget the request and the demo to go back to.
        guard !isBusy, phase != .composing else { return }
        keepOrDropOpenDemo()
        demoBeforeNew = demo?.id
        closeDemo()
        if let selectedSource { library.selectNewDemo(for: selectedSource) }
        prompt = ""
        phase = .composing
    }

    /// Opens a saved demo of the selected app.
    func openDemo(_ id: UUID) {
        guard !isBusy, let selectedSource, id != demo?.id, savedDemos.contains(where: { $0.id == id }) else { return }
        keepOrDropOpenDemo()
        library.select(id, for: selectedSource)
        loadSelectedDemo()
    }

    /// Leaves the request field for the demo that was open before it.
    func cancelNewDemo() {
        guard phase == .composing, demo == nil, let selectedSource, !savedDemos.isEmpty else { return }
        library.select(demoBeforeNew, for: selectedSource)
        loadSelectedDemo()
    }

    func deleteDemo(_ id: UUID) {
        guard id != demo?.id || !isBusy else { return }
        library.remove(id: id)
        guard id == demo?.id else { return }
        closeDemo()
        if let selectedSource { library.select(nil, for: selectedSource) }
        loadSelectedDemo()
    }

    /// Saves the open demo, or forgets it if it's a build that stopped before it began.
    private func keepOrDropOpenDemo() {
        guard let demo else { return }
        if demo.isEmptyDraft { library.remove(id: demo.id) } else { persist() }
    }

    /// Stops everything tied to the open demo. A script Claude is still writing
    /// keeps going and lands on its own demo.
    private func closeDemo() {
        cancelWork()
        announcesResult = false
        pendingRebuild = nil
        rewindTarget = nil
        buildSetup = nil
        verifyEngine = nil
        scriptError = nil
        demo = nil
        recheckSuggested = false
        notice = nil
        driver.show(nil)
        driver.movePointer(to: nil, duration: 0)
    }

    // MARK: Source changes

    func sourceDidChange() {
        let selection = driver.selectedSource
        liveSource = driver.source
        if let boundSource, isBusy, liveSource != boundSource {
            switch phase {
            case .scouting: stopBuilding(.error(.sourceChanged))
            case .running(let mode, let next, let current):
                cancelWork()
                phase = .paused(mode, next: next, current: current, reason: .sourceChanged)
            case .returning(let then):
                cancelWork()
                phase = .needsStart(.noAutomaticReturn, then: then)
                activity = ""
            default: break
            }
        }
        guard selectedSource != selection else {
            // The same window going live (or the first one) can now be read for ideas.
            if ideas.isEmpty, !isFindingIdeas { findIdeas() }
            return
        }
        if isBusy { pause() }
        cancelWork()
        keepOrDropOpenDemo()
        boundSource = nil
        selectedSource = selection
        loadSelectedDemo()
    }

    private func loadSelectedDemo() {
        // A start check still waiting on the app must not land on the demo opened next.
        cancelWork()
        let previous = phase
        announcesResult = false
        demoBeforeNew = nil
        rewindTarget = nil
        var demo = selectedSource.flatMap { library.demo(for: $0) }
        while let stale = demo, stale.isEmptyDraft {
            library.remove(id: stale.id)
            demo = selectedSource.flatMap { library.demo(for: $0) }
        }
        self.demo = demo
        prompt = demo?.prompt ?? selectedSource.map { library.prompt(for: $0) } ?? ""
        notice = nil
        recheckSuggested = false
        buildSetup = nil
        verifyEngine = nil
        pendingRebuild = nil
        driver.show(nil)
        driver.movePointer(to: nil, duration: 0)
        if let demo, demo.isCompiled {
            phase = .ready
        } else if let demo, demo.draft != nil, demo.start != nil {
            phase = .scoutPaused(.relaunched)
        } else {
            phase = .composing
        }
        // When the phase stays the same (between two ready demos, say), phaseChanged doesn't run.
        if phase == previous {
            previewPrompter()
            if phase == .ready { prepareListener() }
            if phase == .composing { findIdeas() }
        }
    }

    // MARK: Runs

    private func checkRun(_ id: UUID, source: DemoSource) throws {
        try Task.checkCancellation()
        guard id == runID else { throw CancellationError() }
        guard driver.source == source else { throw DemoError.sourceChanged }
    }

    private func cancelWork() {
        stopMonitoring()
        task?.cancel()
        task = nil
        runID = UUID()
    }

    private func persist() {
        guard let demo else { return }
        library.save(demo)
        if let selectedSource, demo.app.matches(selectedSource) { library.select(demo.id, for: selectedSource) }
    }

    // MARK: Presenter input

    private func stopMonitoring() {
        interactionMonitor?.stop()
    }

    /// Pauses when the presenter clicks, scrolls or types in the source app
    /// itself. BetterMeets' own windows, other apps and the meeting are ignored,
    /// since the demo runs in the background.
    private func watchForInteraction() {
        guard observesUserInput else { return }
        if interactionMonitor == nil {
            interactionMonitor = GlobalLocalEventMonitor(
                eventMask: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel],
                transform: { event in
                    // Events delivered to BetterMeets' own windows are never input to the source.
                    guard event.window == nil, !DemoInputSynthesizer.isSynthetic(event.cgEvent) else { return nil }
                    let isKey = event.type == .keyDown
                    return DemoUserInput(
                        windowNumber: event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointer) ?? 0,
                        location: event.cgEvent?.location, isKey: isKey,
                        plainKeyCode: isKey && event.modifierFlags.isDisjoint(with: [.command, .control, .option])
                            ? event.keyCode : nil)
                },
                handler: { [weak self] input in
                    self?.handleUserInput(input)
                }
            )
        }
        interactionMonitor?.start()
    }

    private func handleUserInput(_ input: DemoUserInput) {
        guard phase.isActuating, let source = boundSource, let info = try? driver.appInfo(for: source) else { return }
        let sourceIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == info.pid
        let isInSource: Bool
        if input.isKey {
            isInSource = sourceIsFrontmost
        } else if input.windowNumber != 0 {
            isInSource = input.windowNumber == Int64(source.windowID)
        } else {
            let frame = WindowFrameResolver.currentSnapshot(for: source.windowID)?.frame
            isInSource = sourceIsFrontmost && input.location.map { frame?.contains($0) ?? false } ?? false
        }
        guard isInSource else { return }
        // Presenting from the app itself, a remote's keys reach the app: they move the demo, not stop it.
        if let key = input.plainKeyCode, handleRemoteKey(key) { return }
        AppLog.demoMode.info("Demo paused by presenter input in the source app")
        switch phase {
        case .scouting: stopBuilding(.userInput)
        case .running(let mode, let next, let current):
            cancelWork()
            phase = .paused(mode, next: next, current: current, reason: .userInput)
        case .returning(let then):
            cancelWork()
            stopReturning(then: then)
        default: break
        }
    }

    // MARK: Testing

    /// Test hook: opens `demo` in `phase` without running anything, so snapshots can draw any state.
    func showForTesting(
        _ demo: RealTimeDemo, in phase: DemoPhase, activity: String = "", notice: String? = nil,
        teleprompterVisible: Bool = false
    ) {
        cancelWork()
        self.demo = demo
        persist()
        self.phase = phase
        self.activity = activity
        self.notice = notice
        self.teleprompterVisible = teleprompterVisible
        if phase.replayMode == .present, let step = phase.currentStep { showLine(for: step, in: demo) }
    }
}
