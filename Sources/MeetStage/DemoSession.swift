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
        case .userInput: "Paused because you used the mouse or keyboard in the app."
        case .sourceChanged: "Paused because the source window changed."
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

private struct DemoUserInput: Sendable {
    var windowNumber: Int64
    var location: CGPoint?
    var isKey: Bool
}

/// Owns one app's demo and every transition between building, returning to
/// the start, checking, presenting and pausing. BetterMeets drives the source
/// app in the background, so the presenter stays here and watches the stage.
@MainActor
final class DemoSession: ObservableObject {
    @Published var prompt = "" {
        didSet {
            guard prompt != oldValue, let selectedSource else { return }
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
    @Published private(set) var needsActuationConsent = false
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
    /// Claude is rewriting the narration as one story.
    @Published private(set) var isWritingScript = false
    /// Why the last script rewrite failed, shown with the script.
    @Published private(set) var scriptError: String?
    @Published var scriptTone: ScriptTone {
        didSet { defaults.set(scriptTone.rawValue, forKey: "demo.scriptTone") }
    }
    @Published var scriptAudience: String {
        didSet { defaults.set(scriptAudience, forKey: "demo.scriptAudience") }
    }
    @Published private(set) var notesVisible = false
    @Published var opensNotesWhenPlaying: Bool {
        didSet { defaults.set(opensNotesWhenPlaying, forKey: "demo.opensNotes") }
    }
    let prompter: PresenterPrompter

    static let consentKey = "demo.allowsAIControl.v2"

    private let defaults: UserDefaults
    private var library: DemoLibrary
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
    private var interactionMonitor: GlobalLocalEventMonitor<DemoUserInput>?
    private var scriptTask: Task<Void, Never>?
    private var prompterChanges: AnyCancellable?
    private let opensWindows: Bool
    private lazy var notesController: PresenterNotesController = {
        let controller = PresenterNotesController()
        controller.onClose = { [weak self] in self?.notesVisible = false }
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
        scriptAudience = defaults.string(forKey: "demo.scriptAudience") ?? ""
        opensNotesWhenPlaying = defaults.object(forKey: "demo.opensNotes") as? Bool ?? true
        hasKey = keyStore.hasKey
        allowsAI = defaults.bool(forKey: Self.consentKey)
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

    var diagnosticDetails: String? {
        switch phase {
        case .scoutPaused(.error(let error)): error.diagnosticDetails
        case .paused(_, _, _, .error(let error)): error.diagnosticDetails
        default: nil
        }
    }

    var isLiveSourceSelected: Bool { liveSource != nil && liveSource == selectedSource }

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
            == DemoFingerprint.make(demo, appVersion: info.appVersion, sizeClass: info.sizeClass, window: info.windowBucket)
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

    func saveKey(_ key: String) {
        pause()
        guard keyStore.save(key) else {
            notice = DemoError.keychain.localizedDescription
            return
        }
        hasKey = keyStore.hasKey
        notice = nil
    }

    private func authorizedKey() throws -> String {
        guard allowsAI else { throw DemoError.missingConsent }
        guard let key = keyStore.key, !key.isEmpty else { throw DemoError.missingKey }
        return key
    }

    private func consentKey(for source: DemoSource) -> String {
        "demo.actuationApproved.\(source.bundleID.isEmpty ? source.name : source.bundleID)"
    }

    func confirmActuation() {
        guard let source = driver.source else { return }
        defaults.set(true, forKey: consentKey(for: source))
        needsActuationConsent = false
        build()
    }

    func cancelActuationConsent() {
        needsActuationConsent = false
    }

    // MARK: Building

    func build() {
        sourceDidChange()
        guard canBuild, let source = driver.source else { return }
        do {
            let key = try authorizedKey()
            guard defaults.bool(forKey: consentKey(for: source)) else {
                needsActuationConsent = true
                return
            }
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
        activity = "Checking the start"
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
        case .play: startReplay(mode: .present, from: 0, startsFromTop: true)
        case .ready:
            phase = .ready
            activity = ""
        case .compose: finishCompose()
        }
    }

    private func finishCompose() {
        cancelWork()
        scriptTask?.cancel()
        isWritingScript = false
        if let selectedSource { library.remove(for: selectedSource) }
        if let demo { prompt = demo.prompt }
        demo = nil
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
            phase = .needsStart(.noAutomaticReturn, then: then)
            activity = ""
        default:
            break
        }
    }

    private func startReplay(
        mode: ReplayMode, from index: Int, singleStep: Bool = false, checkStart: Bool = false,
        startsFromTop: Bool = false
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
        phase = .running(mode, next: index, current: nil)
        activity = mode == .verify ? "Checking step \(index + 1) of \(demo.steps.count)" : ""
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
                playsOpening: mode == .present && index == 0 && startsFromTop)
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

    private func hooks(id: UUID, source: DemoSource, steps: Int, playsOpening: Bool = false) -> DemoReplayEngine.Hooks {
        DemoReplayEngine.Hooks(
            check: { [weak self] in
                guard let self else { throw CancellationError() }
                try self.checkRun(id, source: source)
            },
            onStep: { [weak self] index, title in
                guard let self, self.runID == id, case .running(let mode, let next, _) = self.phase else { return }
                self.phase = .running(mode, next: next, current: index)
                if mode == .verify {
                    self.activity = "Checking step \(index + 1) of \(steps): \(title)"
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
        playsOpening: Bool = false
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
                holdOverride: replayTuning.holdOverride, gateTimeout: replayTuning.gateTimeout),
            hooks: hooks(id: id, source: source, steps: demo.steps.count, playsOpening: playsOpening))
    }

    private func finishVerification(_ engine: DemoReplayEngine, source: DemoSource) {
        verifyEngine = nil
        guard engine.verifiedAllSteps, var checked = demo, checked.id == engine.demo.id,
            checked.steps.map(\.id) == engine.demo.steps.map(\.id), let info = try? driver.appInfo(for: source)
        else {
            notice = "The check didn’t cover every step. Check it again from the start."
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
        let originalLines = (opening: demo.openingScript, closing: demo.closingScript)
        let request = ScriptRequest(
            prompt: demo.prompt, appName: demo.app.appName, start: demo.start?.description ?? "",
            outline: demo.outline,
            steps: demo.steps.map { step in
                ScriptRequest.Step(
                    kind: step.action.kindLabel, target: step.action.locators.map(\.displayName).joined(separator: ", "),
                    title: step.title, script: step.script, isNavigation: step.action.isMutating)
            }, tone: scriptTone, audience: scriptAudience)
        isWritingScript = true
        scriptError = nil
        scriptTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isWritingScript = false } }
            do {
                let draft = try await model.writeScript(request, key: key)
                try Task.checkCancellation()
                applyScript(draft, to: ids, original: original, originalLines: originalLines, demoID: demo.id)
            } catch is CancellationError {
            } catch {
                AppLog.demoMode.error("Script rewrite failed: \(error.localizedDescription, privacy: .public)")
                scriptError = "Couldn’t rewrite the script: \(error.localizedDescription)"
            }
        }
    }

    private func applyScript(
        _ draft: ScriptDraft, to ids: [UUID], original: [UUID: DemoStep],
        originalLines: (opening: String?, closing: String), demoID: UUID
    ) {
        guard var live = demo, live.id == demoID else { return }
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
        live.revision += 1
        demo = live
        persist()
        if phase == .ready { previewPrompter() }
        // A check in progress keeps its own copy; it merges structure, not words.
    }

    // MARK: Presenter notes

    func toggleNotes() {
        notesVisible ? hideNotes() : showNotes()
    }

    func showNotes() {
        guard opensWindows else { return }
        notesController.show(demo: self)
        notesVisible = true
        previewPrompter()
    }

    func hideNotes() {
        guard opensWindows else { return }
        notesController.hide()
        notesVisible = false
    }

    /// Moves past the current line now, while the demo waits for the presenter's voice.
    func skipLine() {
        prompter.skipLine()
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
        switch phase {
        case .running(.present, _, _):
            if old.replayMode != .present, opensNotesWhenPlaying { showNotes() }
        case .finished:
            if let closing = demo?.closingScript, !closing.isEmpty {
                prompter.show(.closing, text: closing, heading: "Wrap up", upNext: nil, position: nil)
            } else {
                prompter.clear()
            }
        case .ready, .composing, .needsStart:
            previewPrompter()
            if phase == .ready, old != .ready, prompter.followsVoice, opensWindows {
                // Ask for the microphone and fetch the speech model now, not in front of an audience.
                let script = scriptText
                Task { await prompter.listener.prepare(script: script) }
            }
        default:
            break
        }
        // Only a change between presenting and not presenting touches the microphone.
        if old.isPresenting != phase.isPresenting { updateListening() }
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
                prompter.show(.opening, text: opening, heading: "Opening", upNext: demo.steps.first?.title, position: nil)
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
        if edited.closingScript != base.closingScript { live.closingScript = edited.closingScript }
        if let description = edited.start?.description, description != base.start?.description {
            live.start?.description = description
        }
        let edits = Dictionary(uniqueKeysWithValues: edited.steps.map { ($0.id, $0) })
        let originals = Dictionary(uniqueKeysWithValues: base.steps.map { ($0.id, $0) })
        live.steps = live.steps.compactMap { step in
            guard let edit = edits[step.id] else { return originals[step.id] == nil ? step : nil }
            let original = originals[step.id] ?? step
            var step = step
            if edit.title != original.title { step.title = edit.title }
            if edit.script != original.script { step.script = edit.script }
            if edit.holdSeconds != original.holdSeconds { step.holdSeconds = edit.holdSeconds }
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

    func newDemo() {
        guard !isBusy else { return }
        cancelWork()
        scriptTask?.cancel()
        isWritingScript = false
        if let demo { prompt = demo.prompt }
        if let selectedSource { library.remove(for: selectedSource) }
        demo = nil
        recheckSuggested = false
        notice = nil
        driver.show(nil)
        driver.movePointer(to: nil, duration: 0)
        phase = .composing
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
            default: break
            }
        }
        guard selectedSource != selection else { return }
        if isBusy { pause() }
        cancelWork()
        persist()
        boundSource = nil
        selectedSource = selection
        loadSelectedDemo()
    }

    private func loadSelectedDemo() {
        scriptTask?.cancel()
        isWritingScript = false
        demo = selectedSource.flatMap { library.demo(for: $0) }
        prompt = demo?.prompt ?? selectedSource.map { library.prompt(for: $0) } ?? ""
        notice = nil
        recheckSuggested = false
        needsActuationConsent = false
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
                    return DemoUserInput(
                        windowNumber: event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointer) ?? 0,
                        location: event.cgEvent?.location, isKey: event.type == .keyDown)
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
        AppLog.demoMode.info("Demo paused by presenter input in the source app")
        switch phase {
        case .scouting: stopBuilding(.userInput)
        case .running(let mode, let next, let current):
            cancelWork()
            phase = .paused(mode, next: next, current: current, reason: .userInput)
        case .returning(let then):
            cancelWork()
            phase = .needsStart(.noAutomaticReturn, then: then)
        default: break
        }
    }
}
