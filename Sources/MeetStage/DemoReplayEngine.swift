import Foundation
import MeetStageCore

enum ReplayMode: Equatable, Sendable { case verify, present }

enum Mismatch: Equatable, Sendable {
    case targetNotFound(String)
    case wrongScreen(onStep: Int)
    case blocked(DemoError)

    var message: String {
        switch self {
        case .targetNotFound(let name): "Couldn’t find “\(name)”."
        case .wrongScreen(let step): "You’re on step \(step + 1)’s screen."
        case .blocked(let error): error.localizedDescription
        }
    }
}

enum StartMismatch: Equatable, Sendable {
    case wrongScreen, togglesDiffer([String]), noAutomaticReturn, webContentUnavailable
}

enum ReplayEnd: Equatable, Sendable {
    case completed
    case pausedAfter(Int)
    case offTrack(index: Int, Mismatch)
}

/// Replays a recorded demo against the live app. Each step waits until its
/// screen has settled and its targets are present, then performs the action
/// and holds. Targets resolve locally through Accessibility; Claude is only
/// asked when a target on the right screen moved or was renamed.
@MainActor
final class DemoReplayEngine {
    struct Options {
        var mode: ReplayMode
        var speed: Double = 1
        var pausesAfterEachStep = false
        var singleStep = false
        /// Presenting: replays the actions before this step quickly and silently,
        /// skipping their highlights, to get back to it from the start.
        var rewindTo: Int?
        /// Test hooks: a fixed hold and gate timeout instead of the paced ones.
        var holdOverride: Double?
        var gateTimeout: Duration?
        /// How long scrolling a target into view may take to settle.
        var framing = DemoFramer.Timing()
        /// Presenting: how long a highlight that had to be scrolled into view stays up at
        /// least, since its line showed first and may already have been said.
        var framedCueMinimum = Duration.milliseconds(1_200)
        /// The presenter always allows the app, so a question trust covers passes
        /// even when the step's approval no longer matches it, as after a rename.
        var trustsApp = false
        /// Testing and going back to the start in the background: how long to wait
        /// for a click that should change the screen to show before clicking once
        /// more on the next route.
        var effectWindow = Duration.milliseconds(1_200)
    }

    /// How much higher, in window fractions, the content sits now than when the
    /// remaining steps were recorded: framing that scrolled differently than while
    /// building, or a demo built before targets were framed. Kept per page.
    struct Drift: Equatable, Sendable {
        var amount = 0.0
        var page: String?
    }

    /// Callbacks for one run. A paused check rebinds them to its new run.
    struct Hooks {
        var check: () throws -> Void
        var onStep: (Int, String) -> Void
        var onCommit: (Int) -> Void
        /// Presenting: holds for a step (by voice or timer). Nil sleeps.
        var hold: ((Int, Double) async throws -> Void)?
        /// Presenting from the first step: the opening line.
        var opening: (() async throws -> Void)?
    }

    private(set) var demo: RealTimeDemo
    private(set) var heals: [UUID: [DemoElementLocator]] = [:]
    private(set) var skippedBeats: [String] = []
    /// Steps that passed during this verification, across pauses.
    private(set) var passedSteps: Set<UUID> = []
    /// By step, the route a second click took when the first showed nothing and the
    /// second did. A passing test saves it on the step.
    private(set) var learnedRoutes: [UUID: DemoStepRoute] = [:]
    private var livePre: [UUID: ScreenSignature] = [:]
    private var liveStart: ScreenSignature?
    /// The look the last step acted on, so the next gate knows which spinners its action started.
    private var actedOn: AXSnapshot?
    /// Carried from one run of a presentation to the next, since each resume is a new engine.
    var drift = Drift()
    /// This run's steps so far, for the line logged when it ends.
    private(set) var timings = DemoRunTimings()
    /// Where the step in progress spends its time, since when, how it ended, and
    /// the driver's pause waits before it.
    private var stepTimings = DemoTurnTimings()
    private var stepBegan: (index: Int, at: ContinuousClock.Instant)?
    private var stepOutcome = "interrupted"
    private var waitedBeforeStep = Duration.zero
    private let source: DemoSource
    private let driver: any DemoDriving
    private let model: any DemoModeling
    private let key: () -> String?
    var options: Options
    private var hooks: Hooks

    init(
        demo: RealTimeDemo, source: DemoSource, driver: any DemoDriving, model: any DemoModeling,
        key: @escaping () -> String?, options: Options, hooks: Hooks
    ) {
        self.demo = demo
        self.source = source
        self.driver = driver
        self.model = model
        self.key = key
        self.options = options
        self.hooks = hooks
    }

    func rebind(_ hooks: Hooks) {
        self.hooks = hooks
    }

    private func check() throws { try hooks.check() }

    /// Whether every step passed during this verification.
    var verifiedAllSteps: Bool { demo.steps.allSatisfy { passedSteps.contains($0.id) } }

    // MARK: Readiness and return to start

    /// Nil when the app shows the demo's starting view, otherwise why not.
    func readiness() async throws -> StartMismatch? {
        guard let start = demo.start else { return .noAutomaticReturn }
        let snapshot: AXSnapshot
        do {
            snapshot = try await driver.snapshot(source, waitForContent: true)
        } catch DemoError.webContentUnavailable {
            return .webContentUnavailable
        }
        let live = ScreenSignatures.make(snapshot)
        guard ScreenSignatures.matches(start.signature, live: live, strict: true) else { return .wrongScreen }
        let differing = start.toggles.filter { toggle in
            guard let id = DemoLocatorMatcher.match(toggle.locator, in: snapshot).nodeID else { return false }
            return snapshot.node(id)?.toggleValue != toggle.isOn
        }
        if !differing.isEmpty { return .togglesDiffer(differing.map(\.locator.displayName)) }
        if let first = demo.steps.first, first.action.isMutating,
            first.action.locators.contains(where: { DemoLocatorMatcher.match($0, in: snapshot).nodeID == nil })
        {
            return .wrongScreen
        }
        liveStart = live
        return nil
    }

    /// Returns the app to the start without asking a model. Browsers go Back
    /// through their history (or open the start address in the same tab);
    /// other apps close dialogs, click the recorded start anchor and restore toggles.
    /// In the background, it clicks a dialog's close button or the anchor once more
    /// on the next route when the first click showed nothing, and presses Escape
    /// rather than a close button that never showed.
    func returnToStart(inBackground background: Bool = false) async throws -> StartMismatch? {
        guard let start = demo.start else { return .noAutomaticReturn }
        driver.show(nil)
        if let url = start.url {
            if try await !goBack(to: ScreenSignatures.urlKey(url)) {
                try await driver.perform(.navigate(url), on: source, pace: .scout) {}
                try check()
            }
            try await Task.sleep(for: .milliseconds(400))
            _ = try? await driver.snapshot(source, waitForContent: true)
        } else {
            var snapshot = try await driver.snapshot(source, waitForContent: true)
            var escapes = 0
            var closeShowed = true
            while snapshot.dialogOpen, !start.signature.dialogOpen, escapes < 2 {
                escapes += 1
                if closeShowed, let close = closeButton(in: snapshot) {
                    closeShowed = try await press(
                        close, in: snapshot, name: "Close", again: background ? { self.closeButton(in: $0) } : nil)
                } else {
                    try await driver.perform(.press(.escape), on: source, pace: .scout) {}
                }
                try await Task.sleep(for: .milliseconds(400))
                try check()
                snapshot = try await driver.snapshot(source, waitForContent: true)
            }
            if let anchor = start.returnAnchor, let id = anchorTarget(anchor, in: snapshot),
                let node = snapshot.node(id)
            {
                // Already selected, the anchor may well show nothing, so it's never clicked twice.
                try await press(
                    id, in: snapshot, name: anchor.displayName,
                    again: background && !node.isSelected ? { self.anchorTarget(anchor, in: $0) } : nil)
                try await Task.sleep(for: .milliseconds(600))
                try check()
                snapshot = try await driver.snapshot(source, waitForContent: true)
            }
            for toggle in start.toggles {
                guard let id = DemoLocatorMatcher.match(toggle.locator, in: snapshot).nodeID,
                    let node = snapshot.node(id), let value = node.toggleValue, value != toggle.isOn,
                    DemoScout.policy(
                        for: .click(toggle.locator), node: node, snapshot: snapshot, prompt: "", startHost: nil,
                        approved: false) == .allow
                else { continue }
                try await press(id, in: snapshot, name: toggle.locator.displayName)
                try await Task.sleep(for: .milliseconds(400))
                try check()
                snapshot = try await driver.snapshot(source, waitForContent: true)
            }
        }
        let mismatch = try await readiness()
        if mismatch == .wrongScreen, start.url == nil, start.returnAnchor == nil { return .noAutomaticReturn }
        return mismatch
    }

    /// Presses the browser's Back button until the start address shows. Works
    /// with the browser in the background and never opens a tab.
    private func goBack(to startKey: String?) async throws -> Bool {
        guard let startKey else { return false }
        for _ in 0..<10 {
            let snapshot = try await driver.snapshot(source, waitForContent: false)
            try check()
            let current = ScreenSignatures.urlKey(snapshot.webURL)
            if current == startKey { return true }
            guard let back = backButton(in: snapshot), snapshot.node(back)?.isEnabled == true else { return false }
            try await press(back, in: snapshot, name: "Back")
            var moved = false
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(100))
                let next = try await driver.snapshot(source, waitForContent: false)
                if ScreenSignatures.urlKey(next.webURL) != current {
                    moved = true
                    break
                }
            }
            guard moved else { return false }
        }
        return false
    }

    private func backButton(in snapshot: AXSnapshot) -> Int? {
        let names = #"^(back|go back|atrás|atras|retroceder|volver|retour|précédent|zurück|indietro|voltar)$"#
        return snapshot.nodes.first { node in
            node.roleClass == .button && !node.inWebArea
                && (node.label.range(of: names, options: [.regularExpression, .caseInsensitive]) != nil
                    || node.identifier?.range(of: "back", options: .caseInsensitive) != nil)
        }?.id
    }

    private func closeButton(in snapshot: AXSnapshot) -> Int? {
        let names = #"^(close|cancel|dismiss|done|cerrar|cancelar|fermer|annuler|schließen|abbrechen|chiudi|×|x)$"#
        return snapshot.nodes.first { node in
            node.inDialog && node.roleClass == .button && node.isVisible
                && node.label.range(of: names, options: [.regularExpression, .caseInsensitive]) != nil
        }?.id
    }

    /// The start anchor, while the policy allows clicking it without asking.
    private func anchorTarget(_ anchor: DemoElementLocator, in snapshot: AXSnapshot) -> Int? {
        guard let id = DemoLocatorMatcher.match(anchor, in: snapshot).nodeID, let node = snapshot.node(id),
            DemoScout.policy(
                for: .click(anchor), node: node, snapshot: snapshot, prompt: "", startHost: nil, approved: false)
                == .allow
        else { return nil }
        return id
    }

    /// Clicks `id` on the way back to the start. With `again`, which finds the
    /// target on a later look, clicks once more on the next route when the first
    /// click showed nothing. False only when it checked and nothing showed.
    @discardableResult
    private func press(
        _ id: Int, in snapshot: AXSnapshot, name: String, again target: ((AXSnapshot) -> Int?)? = nil
    ) async throws -> Bool {
        let windows = driver.scopeBaseline(source)
        let used = try await driver.perform(
            .click(ElementHandle(generation: snapshot.generation, id: id), name: name), on: source, pace: .scout
        ) {}
        guard let target else { return true }
        let outcome = try await clickAgainIfSilent(
            after: used, delivery: driver.lastDelivery, on: snapshot, windows: windows, name: name, pace: .scout,
            target: target)
        return outcome != .showedNothing
    }

    // MARK: Steps

    func run(from index: Int) async throws -> ReplayEnd {
        var index = index
        timings = DemoRunTimings()
        defer { endTimings() }
        if options.mode == .verify, index == 0 {
            // The start screen as the check found it, to confirm the start signature.
            liveStart = ScreenSignatures.make(try await driver.snapshot(source, waitForContent: true))
        }
        if options.mode == .present, index == 0, let opening = hooks.opening {
            try await opening()
            try check()
        }
        while index < demo.steps.count {
            endStep()
            try check()
            let step = demo.steps[index]
            scrolledBefore(step)
            if isRewinding(index), !step.action.isMutating {
                unframed(step)
                hooks.onCommit(index + 1)
                index += 1
                continue
            }
            beginStep(index)
            hooks.onStep(index, step.title)
            let previous = index > 0 ? demo.steps[index - 1].action : nil
            let gate = try await self.gate(index, after: previous)
            try check()

            switch gate {
            case .failure(let mismatch):
                if case .present = step.action, options.mode == .present {
                    // Never stop a live demo for a highlight: skip it and keep the previous view.
                    stepOutcome = "skipped"
                    skippedBeats.append(step.title)
                    unframed(step)
                    hooks.onCommit(index + 1)
                    index += 1
                    continue
                }
                stepOutcome = "offTrack"
                return .offTrack(index: index, mismatch)
            case .resolved(let snapshot, let ids):
                if options.mode == .verify { livePre[step.id] = ScreenSignatures.make(snapshot) }
                if let end = try await perform(index, snapshot: snapshot, ids: ids) {
                    stepOutcome = "offTrack"
                    return end
                }
                stepOutcome = "done"
                if options.mode == .verify { passedSteps.insert(step.id) }
            }

            if options.singleStep || options.pausesAfterEachStep, index + 1 < demo.steps.count, !isRewinding(index + 1)
            {
                return .pausedAfter(index)
            }
            index += 1
        }
        if options.mode == .verify { confirmVerification() }
        return .completed
    }

    private enum Gate {
        case resolved(AXSnapshot, [Int])
        case failure(Mismatch)
    }

    /// Waits for the step's screen to settle, for any work the last step started to
    /// finish, and for every target to be present and unique, revealing off-screen
    /// targets and healing renamed ones.
    private func gate(_ index: Int, after previous: DemoAction?) async throws -> Gate {
        let step = demo.steps[index]
        let locators = heals[step.id] ?? step.action.locators
        let longWait: Bool =
            switch previous {
            case .navigate: true
            case .typeText(_, _, let submit): submit
            default: false
            }
        let timeout: Duration =
            options.gateTimeout ?? (longWait ? .seconds(10) : step.action.isMutating ? .seconds(4) : .seconds(3))
        // Right after an action the app may still be redrawing (stale suggestions,
        // a list filling in), so resolve only once two looks agree.
        let needsSettle = previous?.isMutating == true
        let started = ContinuousClock.now
        var hintScrolls = 0
        var revealedTarget = false
        var lastDigest: Int?
        var lastSnapshot: AXSnapshot?
        // The look the last step acted on, or else, in an engine that hasn't acted yet
        // (a resumed presentation, the next step played on its own), this gate's first
        // look, so an indicator that was already there never holds the step up.
        var busyBaseline = actedOn

        while true {
            let snapshot = try await settleLook()
            stepTimings.nodes = snapshot.nodes.count
            try check()
            lastSnapshot = snapshot
            if ScreenSignatures.urlKey(snapshot.webURL) != drift.page { drift = Drift() }
            if busyBaseline == nil { busyBaseline = snapshot }
            let settled = !needsSettle || snapshot.digest == lastDigest
            lastDigest = snapshot.digest
            // A spinner or progress bar the last step's look didn't show means the app is
            // still working on that step: wait for it, but for at most half the timeout,
            // so one that never stops still leaves time to find the targets.
            let working =
                needsSettle && snapshot.isBusier(than: busyBaseline) && ContinuousClock.now - started < timeout / 2
            let live = ScreenSignatures.make(snapshot)
            // Headings can be below the fold, so they only identify the screen in diagnostics.
            let onScreen = ScreenSignatures.matches(step.pre, live: live, includeHeadings: false)
            if onScreen, settled, !working, snapshot.webContent.map(\.isReady) ?? true {
                let ids = locators.map { resolve($0, in: snapshot) }
                // Targets found by position were recorded after the scout's scroll,
                // so repeat that scroll before trusting what sits in that spot now.
                if let hint = step.reveal, hintScrolls < (hint.count ?? 1),
                    ids.contains(nil) || locators.contains(where: DemoLocatorMatcher.isPositional)
                {
                    hintScrolls += 1
                    try await scroll(hint: hint, in: snapshot)
                    lastDigest = nil
                    continue
                }
                if ids.allSatisfy({ $0 != nil }) {
                    let nodes = ids.compactMap { $0 }
                    if nodes.allSatisfy({ snapshot.node($0)?.isVisible == true }) {
                        stepTimings.settle += ContinuousClock.now - started
                        return .resolved(snapshot, nodes)
                    }
                    if !revealedTarget, let first = nodes.first(where: { snapshot.node($0)?.isVisible != true }) {
                        revealedTarget = true
                        try await reveal(nodeID: first, in: snapshot, hint: step.reveal)
                        lastDigest = nil
                        continue
                    }
                }
            }
            if ContinuousClock.now - started >= timeout {
                stepTimings.settle += ContinuousClock.now - started
                stepTimings.unsettled += 1
                break
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        guard let snapshot = lastSnapshot else { return .failure(.targetNotFound(step.title)) }
        let live = ScreenSignatures.make(snapshot)
        if !ScreenSignatures.matches(step.pre, live: live, includeHeadings: false) {
            if let other = demo.steps.indices.first(where: {
                $0 != index && demo.steps[$0].pre.confirmed && ScreenSignatures.matches(demo.steps[$0].pre, live: live)
            }) {
                return .failure(.wrongScreen(onStep: other))
            }
            return .failure(.targetNotFound(locators.first?.displayName ?? step.title))
        }
        if let healed = try await heal(index, locators: locators, snapshot: snapshot) {
            // Kept where the steps were recorded, like every other locator.
            heals[step.id] = healed.locators.map { $0.shifted(by: drift.amount) }
            return .resolved(healed.snapshot, healed.ids)
        }
        return .failure(
            .targetNotFound(locators.first(where: { resolve($0, in: snapshot) == nil })?.displayName ?? step.title))
    }

    /// One look while waiting for the app to settle, counted in the step's timings.
    private func settleLook() async throws -> AXSnapshot {
        let started = ContinuousClock.now
        let look = try await driver.snapshot(source, waitForContent: false)
        stepTimings.walk += ContinuousClock.now - started
        stepTimings.settlePolls += 1
        return look
    }

    /// Finds a recorded target where the content sits now, moved by the drift,
    /// or else where it was recorded.
    private func resolve(_ locator: DemoElementLocator, in snapshot: AXSnapshot) -> Int? {
        if abs(drift.amount) * snapshot.windowFrame.height >= 1,
            let id = DemoLocatorMatcher.match(locator.shifted(by: -drift.amount), in: snapshot).nodeID
        {
            return id
        }
        return DemoLocatorMatcher.match(locator, in: snapshot).nodeID
    }

    /// Scrolls a resolved but off-screen target into view: first by asking the
    /// element itself (works in the background), then with the scroll wheel.
    private func reveal(nodeID: Int, in snapshot: AXSnapshot, hint: RevealHint?) async throws {
        guard let node = snapshot.node(nodeID), let locator = DemoLocatorFactory.locator(for: nodeID, in: snapshot)
        else { return }
        do {
            stepTimings.routes.append(
                try await driver.perform(
                    .scrollToVisible(ElementHandle(generation: snapshot.generation, id: nodeID)), on: source,
                    pace: .scout
                ) {})
        } catch DemoError.targetNotFound {
            return
        }
        try await Task.sleep(for: .milliseconds(250))
        try check()
        var latest = try await driver.snapshot(source, waitForContent: false)
        if let id = DemoLocatorMatcher.match(locator, in: latest).nodeID, latest.node(id)?.isVisible == true { return }

        let down = hint?.directionDown ?? (node.rect.midY > 0.5)
        let container = hint.flatMap { containerRect(for: $0, in: latest) } ?? latest.containerNode(of: node)?.rect
        // Real at once where the scout found Accessibility's scrolling moved nothing.
        let wheel = DemoInput.wheel(around: container, down: down, increments: 1, from: hint?.route ?? .accessibility)
        for _ in 0..<8 {
            do {
                stepTimings.routes.append(try await driver.perform(wheel, on: source, pace: .scout) {})
            } catch DemoError.inputNotDelivered {
                return
            }
            try await Task.sleep(for: .milliseconds(120))
            try check()
            latest = try await driver.snapshot(source, waitForContent: false)
            if let id = DemoLocatorMatcher.match(locator, in: latest).nodeID, latest.node(id)?.isVisible == true {
                return
            }
        }
    }

    /// Repeats one of the scout's scrolls: the next element past the fold is
    /// scrolled into view, falling back to the scroll wheel, real at once when the
    /// scout found Accessibility's scrolling moved nothing.
    private func scroll(hint: RevealHint, in snapshot: AXSnapshot) async throws {
        let container = hint.container.flatMap { key in
            snapshot.nodes.first { $0.isContainer && AXSnapshot.key(for: $0) == key }
        }
        let input: DemoInput =
            DemoScout.scrollTarget(in: snapshot, container: container, down: hint.directionDown)
            .map { .scrollToVisible(ElementHandle(generation: snapshot.generation, id: $0)) }
            ?? .wheel(
                around: container?.rect, down: hint.directionDown, increments: 4, from: hint.route ?? .accessibility)
        do {
            stepTimings.routes.append(try await driver.perform(input, on: source, pace: .scout) {})
        } catch DemoError.inputNotDelivered {
            return
        }
        try await Task.sleep(for: .milliseconds(300))
    }

    private func containerRect(for hint: RevealHint, in snapshot: AXSnapshot) -> NormRect? {
        guard let key = hint.container else { return nil }
        return snapshot.nodes.first { $0.isContainer && AXSnapshot.key(for: $0) == key }?.rect
    }

    // MARK: Perform

    private func perform(_ index: Int, snapshot: AXSnapshot, ids: [Int]) async throws -> ReplayEnd? {
        let step = demo.steps[index]
        let locators = heals[step.id] ?? step.action.locators
        var snapshot = snapshot
        var ids = ids
        var nodes = ids.compactMap { snapshot.node($0) }
        var framed: DemoFramer.Result?
        let pace: DemoPace = options.mode == .present ? .present : .verify
        let hooks = hooks
        let commit: @MainActor () throws -> Void = {
            try hooks.check()
            hooks.onCommit(index + 1)
        }
        // A route that committed and reached nothing hands the step back, so a pause
        // before the next route delivers resumes at this step.
        let uncommit: @MainActor () -> Void = { hooks.onCommit(index) }

        let action: DemoAction =
            switch step.action {
            case .click: .click(locators[0])
            case .typeText(_, let text, let submit): .typeText(field: locators[0], text: text, submit: submit)
            case .present(let beat): .present(DemoBeat(effect: beat.effect, targets: locators))
            default: step.action
            }
        func policy(for node: AXNode?, in look: AXSnapshot) -> DemoPolicyDecision {
            DemoScout.policy(
                for: action, node: node, snapshot: look, prompt: demo.prompt, startHost: demo.start?.url?.host,
                approved: step.approved, approvedReason: step.approvedReason, trusted: options.trustsApp)
        }
        switch policy(for: nodes.first, in: snapshot) {
        case .allow: break
        case .deny(let reason): return .offTrack(index: index, .blocked(.policyDenied(reason)))
        case .needsApproval(let approval): return .offTrack(index: index, .blocked(.policyDenied(approval.message)))
        }

        if !ids.isEmpty {
            // Bring a target the viewport cuts into view, as the scout did before recording what followed.
            let framer = DemoFramer(driver: driver, source: source, timing: options.framing, check: hooks.check)
            let result = try await framer.frame(ids, in: snapshot, for: step.action.isMutating ? .action : .highlight)
            try check()
            drift.amount += result.shift - (step.framing ?? 0)
            drift.page = ScreenSignatures.urlKey(result.snapshot.webURL)
            snapshot = result.snapshot
            ids = result.ids ?? []
            nodes = ids.compactMap { snapshot.node($0) }
            framed = result
            if ids.isEmpty {
                let name = locators.first?.displayName ?? step.title
                guard !step.action.isMutating, options.mode == .present else {
                    return .offTrack(index: index, .targetNotFound(name))
                }
                // Lost while scrolling it into view: like a highlight that can't be found, skipped.
                skippedBeats.append(step.title)
                try commit()
                return nil
            }
        }

        actedOn = snapshot
        do {
            switch action {
            case .present(let beat):
                let rect = DemoFraming.cueRect(
                    for: nodes, in: snapshot, effect: beat.effect, coveredTop: framed?.coveredTop)
                driver.show(DemoCue(effect: beat.effect, rect: rect))
                let shown = ContinuousClock.now
                try await hold(index)
                if framed?.scrolled == true, options.mode == .present, options.holdOverride == nil {
                    // Its line showed before the scrolling, so it may already be said: never just a flash.
                    let left = options.framedCueMinimum - (ContinuousClock.now - shown)
                    if left > .zero { try await Task.sleep(for: left) }
                }
                try commit()
                return nil

            case .click(let locator):
                driver.show(nil)
                if let expected = locator.toggleValueAfter, nodes.first?.toggleValue == expected {
                    // Already in the state this click produced; clicking again would undo it.
                    try commit()
                } else {
                    let windows = driver.scopeBaseline(source)
                    // In the background, from the route building found worked; presenting keeps real input.
                    let used = try await driver.perform(
                        .click(
                            ElementHandle(generation: snapshot.generation, id: ids[0]), name: locator.displayName,
                            from: step.route),
                        on: source, pace: pace, commit: commit, uncommit: uncommit)
                    let delivery = driver.lastDelivery
                    stepTimings.routes.append(used)
                    if options.mode == .verify, Self.mayClickAgain(step, locator: locator, node: nodes.first) {
                        // Found again where the content sits now: framing moved it from where it was recorded.
                        let moved = locator.shifted(by: -(step.framing ?? 0))
                        let outcome = try await clickAgainIfSilent(
                            after: used, delivery: delivery, on: snapshot, windows: windows,
                            name: locator.displayName, pace: pace, progress: index
                        ) { look in
                            guard let id = self.resolve(moved, in: look), policy(for: look.node(id), in: look) == .allow
                            else { return nil }
                            return id
                        }
                        if case .retried(let route) = outcome { learnedRoutes[step.id] = route }
                    }
                }

            case .typeText(let field, let text, let submit):
                driver.show(nil)
                stepTimings.routes.append(
                    try await driver.perform(
                        .type(
                            ElementHandle(generation: snapshot.generation, id: ids[0]), name: field.displayName,
                            text: text, submit: submit), on: source, pace: pace, commit: commit, uncommit: uncommit))

            case .press(let key):
                stepTimings.routes.append(
                    try await driver.perform(
                        .press(key, from: step.route), on: source, pace: pace, commit: commit, uncommit: uncommit))

            case .navigate(let url):
                driver.show(nil)
                stepTimings.routes.append(
                    try await driver.perform(.navigate(url), on: source, pace: pace, commit: commit))
            }
        } catch let error as DemoError {
            switch error {
            case .occluded, .typingFailed, .targetNotFound, .policyDenied, .addressBarUnavailable, .inputNotDelivered:
                return .offTrack(index: index, .blocked(error))
            default:
                throw error
            }
        }
        try check()
        try await hold(index)
        if case .press = step.action { driver.show(nil) }
        return nil
    }

    // MARK: Checking clicks

    /// What a checked click came to.
    private enum ClickOutcome: Equatable {
        /// It showed, or it went through real input and no route is left to try.
        case showed
        /// It showed nothing, and clicking once more through this route did show.
        case retried(DemoStepRoute)
        /// Neither click showed anything, or the target couldn't be clicked again.
        case showedNothing
    }

    /// Whether testing checks this step's click right after it and clicks once more,
    /// on the next route, when nothing shows: only a click that changed the screen
    /// while building, and never a switch, a control that saves, submits, adds or
    /// searches, or one the presenter approved, which a second click could do twice.
    private static func mayClickAgain(_ step: DemoStep, locator: DemoElementLocator, node: AXNode?) -> Bool {
        guard step.changedScreen == true, !step.approved, !locator.clickingAgainCouldRepeat(node: node) else {
            return false
        }
        return !DemoActionPolicy.isSearchLike(locator.words(with: node))
    }

    /// Waits up to `Options.effectWindow` for a click that went through `used` to
    /// show, and when nothing did, clicks once more on the next route (the page's own
    /// click, else a borrowed real one) at the element `target` finds on the latest
    /// look, which checks the policy again. The driver hit-tests it and checks its
    /// denials again too. Never more than once, so even an app too slow to show the
    /// first click in time gets at most two, and never after a click that may have
    /// acted (`DemoDelivery.uncertain`). `progress` is the step to say so on.
    private func clickAgainIfSilent(
        after used: DemoInputRoute?, delivery: DemoDelivery, on before: AXSnapshot, windows: DemoScopeBaseline,
        name: String, pace: DemoPace, progress: Int? = nil, target: (AXSnapshot) -> Int?
    ) async throws -> ClickOutcome {
        guard delivery != .uncertain, let next = DemoStepRoute.afterSilentClick(used) else { return .showed }
        let first = try await awaitEffect(from: before, windows: windows)
        if first.showed { return .showed }
        guard let id = target(first.look), first.look.node(id)?.isVisible == true else { return .showedNothing }
        try check()
        AppLog.demoMode.info("A click showed nothing; clicking once more on the next route")
        let hooks = hooks
        if let progress { hooks.onStep(progress, DemoScout.retryActivity(clicking: name, from: next)) }
        let again = try await driver.perform(
            .click(ElementHandle(generation: first.look.generation, id: id), name: name, from: next), on: source,
            pace: pace
        ) { try hooks.check() }
        stepTimings.routes.append(again)
        try check()
        let second = try await awaitEffect(from: first.look, windows: windows)
        return second.showed ? .retried(DemoStepRoute(click: again)) : .showedNothing
    }

    /// Looks at the window until a click shows (the digest, address or focused field
    /// changed, a spinner or progress bar `before` didn't have appeared, or the app
    /// opened a window) or `Options.effectWindow` runs out. The last look, and whether it showed.
    private func awaitEffect(from before: AXSnapshot, windows: DemoScopeBaseline) async throws
        -> (look: AXSnapshot, showed: Bool)
    {
        let started = ContinuousClock.now
        defer { stepTimings.settle += ContinuousClock.now - started }
        while true {
            let look = try await settleLook()
            try check()
            if DemoScout.changed(from: before, to: look) || look.isBusier(than: before)
                || driver.scopeViolation(source, since: windows) != nil
            {
                return (look, true)
            }
            if ContinuousClock.now - started >= options.effectWindow { return (look, false) }
            try await Task.sleep(for: min(.milliseconds(150), options.effectWindow))
        }
    }

    /// A step skipped without its framing leaves the content where it was before the
    /// scout scrolled it, so the steps after it sit lower than recorded.
    private func unframed(_ step: DemoStep) {
        moveDrift(by: -(step.framing ?? 0), on: step)
    }

    /// While building, framing for actions left out of the demo scrolled the content
    /// before this step was recorded. Replay never did, so it sits lower.
    private func scrolledBefore(_ step: DemoStep) {
        moveDrift(by: -(step.priorFraming ?? 0), on: step)
    }

    private func moveDrift(by amount: Double, on step: DemoStep) {
        guard amount != 0 else { return }
        if step.pre.urlKey != drift.page { drift = Drift() }
        drift.amount += amount
        drift.page = step.pre.urlKey
    }

    private func isRewinding(_ index: Int) -> Bool {
        index < (options.rewindTo ?? 0)
    }

    private func hold(_ index: Int) async throws {
        let step = demo.steps[index]
        if isRewinding(index) {
            try await Task.sleep(for: .milliseconds(150))
            return
        }
        if let fixed = options.holdOverride {
            try await Task.sleep(for: .seconds(fixed))
            return
        }
        if options.mode == .verify {
            try await Task.sleep(for: .seconds(min(step.holdSeconds, step.action.isMutating ? 0.3 : 0.6)))
            return
        }
        // Speed shortens pauses and silent steps, never the time a line takes to say.
        let speaking = DemoStep.speakingTime(for: step.script)
        let seconds =
            speaking > 0
            ? max(step.holdSeconds / max(options.speed, 0.5), speaking + 0.4)
            : step.holdSeconds / max(options.speed, 0.5)
        if let hold = hooks.hold {
            try await hold(index, seconds)
        } else {
            try await Task.sleep(for: .seconds(seconds))
        }
    }

    // MARK: Heal

    private func heal(_ index: Int, locators: [DemoElementLocator], snapshot: AXSnapshot) async throws
        -> (locators: [DemoElementLocator], snapshot: AXSnapshot, ids: [Int])?
    {
        let step = demo.steps[index]
        if options.mode == .present, step.action.isMutating { return nil }
        guard let key = key() else { return nil }
        let shot = ContinuousClock.now
        let screenshot = try await driver.screenshot(source)
        stepTimings.screenshot += ContinuousClock.now - shot
        let encoded = DemoSceneEncoder.encode(snapshot)
        let description = locators.map { locator in
            var parts = ["\(locator.roleClass.noun)"]
            if locator.labelIsStable { parts.append("labelled “\(locator.label)”") }
            if let container = locator.container, !container.label.isEmpty { parts.append("in “\(container.label)”") }
            if let index = locator.visualIndex, DemoLocatorMatcher.ordersByIndex(locator.container) {
                parts.append("item \(index + 1) in visual order")
            }
            let r = locator.rect
            parts.append("last seen near \(Int(r.midX * 999)),\(Int(r.midY * 999))")
            return parts.joined(separator: " ")
        }.joined(separator: "; ")
        // Claude's own note on the target, recorded on a beat's first one; only ever a hint for finding it.
        let note = locators.lazy.compactMap(\.note).first
        hooks.onStep(index, "Looking for \(locators.first?.displayName ?? step.title)")
        let asked = ContinuousClock.now
        let result = try await model.relocate(
            RelocateRequest(
                stepTitle: step.title, description: description, screenshot: screenshot, elements: encoded.text,
                note: note),
            key: key)
        stepTimings.model += ContinuousClock.now - asked
        stepTimings.modelCalls += 1
        stepTimings.tokens += result.tokens
        try check()
        guard let ids = result.ids, ids.allSatisfy(encoded.listed.contains) else { return nil }
        let isSingle = step.action.isMutating
        guard isSingle ? ids.count == 1 : (1...6).contains(ids.count) else { return nil }
        let nodes = ids.compactMap { snapshot.node($0) }
        guard nodes.count == ids.count else { return nil }
        if isSingle, nodes[0].roleClass != locators[0].roleClass { return nil }

        // The healed description must find the same elements again on a fresh look.
        let fresh = try await driver.snapshot(source, waitForContent: false)
        var healed: [DemoElementLocator] = []
        var freshIDs: [Int] = []
        for node in nodes {
            guard var locator = DemoLocatorFactory.locator(for: node.id, in: snapshot),
                let id = DemoLocatorMatcher.match(locator, in: fresh).nodeID
            else { return nil }
            if let old = locators.first(where: { $0.roleClass == locator.roleClass }) {
                locator.toggleValueAfter = old.toggleValueAfter
            }
            if healed.isEmpty { locator.note = note }
            healed.append(locator)
            freshIDs.append(id)
        }
        AppLog.demoMode.info("Healed step \(index + 1) target")
        return (healed, fresh, freshIDs)
    }

    // MARK: Timings

    private func beginStep(_ index: Int) {
        stepTimings = DemoTurnTimings()
        stepBegan = (index, .now)
        stepOutcome = "interrupted"
        waitedBeforeStep = driver.waitedForPause
    }

    /// Logs the step that just ended, if one began, and adds it to the run's.
    private func endStep() {
        guard let began = stepBegan else { return }
        stepBegan = nil
        stepTimings.total = ContinuousClock.now - began.at
        stepTimings.pauseWait = driver.waitedForPause - waitedBeforeStep
        timings.add(stepTimings)
        let action = demo.steps.indices.contains(began.index) ? demo.steps[began.index].action.logName : "none"
        let line = stepTimings.line("\(runName) step=\(began.index + 1) action=\(action) outcome=\(stepOutcome)")
        AppLog.demoTimings.info("\(line, privacy: .public)")
    }

    /// Logs the last step and the run's totals, however the run ended.
    private func endTimings() {
        endStep()
        let summary = timings.summary("\(runName) ended")
        AppLog.demoTimings.info("\(summary, privacy: .public)")
    }

    private var runName: String { options.mode == .verify ? "test" : "play" }

    // MARK: Verification

    /// Keeps only screen evidence that held in both scouting and checking, and
    /// folds healed targets and learned routes into the steps.
    private func confirmVerification() {
        for index in demo.steps.indices {
            let id = demo.steps[index].id
            if let live = livePre[id] {
                demo.steps[index].pre = ScreenSignatures.confirm(demo.steps[index].pre, with: live)
            }
            if let route = learnedRoutes[id] { demo.steps[index].route = route }
            if let healed = heals[id] {
                switch demo.steps[index].action {
                case .click: demo.steps[index].action = .click(healed[0])
                case .typeText(_, let text, let submit):
                    demo.steps[index].action = .typeText(field: healed[0], text: text, submit: submit)
                case .present(let beat):
                    demo.steps[index].action = .present(DemoBeat(effect: beat.effect, targets: healed))
                default: break
                }
            }
        }
        if let liveStart, var start = demo.start {
            start.signature = ScreenSignatures.confirm(start.signature, with: liveStart)
            demo.start = start
        }
    }
}
