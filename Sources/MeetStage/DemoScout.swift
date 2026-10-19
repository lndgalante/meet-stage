import Foundation
import MeetStageCore

enum ScoutLimit: String, Equatable, Sendable {
    case turns, steps, time, budget, stuck
    /// Claude chose action after action the policy turned down.
    case denied

    var message: String {
        switch self {
        case .turns: "Stopped after the maximum number of turns."
        case .steps: "Reached the 40-step limit."
        case .time: "Stopped after four minutes."
        case .budget: "Stopped at the $2 build limit."
        case .stuck: "Stopped because the last few actions didn’t get the demo anywhere."
        case .denied: "Stopped because Claude kept choosing actions BetterMeets won’t do."
        }
    }
}

/// Counts the turns in a row that got a build nowhere, and the ones whose action
/// the policy turned down, each toward its own stop.
struct ScoutProgress: Equatable, Sendable {
    static let limit = 3

    /// Turns that changed nothing, were rejected, or changed what Claude then said was the wrong thing.
    private(set) var unchanged = 0
    /// Turns whose action the policy denied, with nothing carried out since.
    private(set) var denials = 0
    /// `unchanged` as it was before the last change reset it.
    private var beforeChange = 0

    var isStuck: Bool { unchanged >= Self.limit }
    var keepsBeingDenied: Bool { denials >= Self.limit }

    /// An action, scroll or highlight was carried out.
    mutating func acted(changed: Bool) {
        denials = 0
        if changed {
            beforeChange = unchanged
            unchanged = 0
        } else {
            unchanged += 1
        }
    }

    /// The turn's choice was turned down before anything ran, for a reason other than the policy.
    mutating func rejected() {
        unchanged += 1
    }

    /// The policy turned the turn's action down. It never counts as getting nowhere.
    mutating func denied() {
        denials += 1
    }

    /// Claude said the change its last action made went the wrong way, so that
    /// action counts as one that changed nothing.
    mutating func wentWrong() {
        unchanged = beforeChange + 1
    }
}

/// An action the policy wants the presenter to approve before the scout runs it.
struct PendingApproval: Equatable, Sendable {
    var action: DemoAction
    var title: String
    var script: String
    var message: String
    /// What kind of question it is, which decides whether Always Allow can answer it.
    var kind: DemoApproval.Kind
    var rect: NormRect?
    /// What Claude said the action would do, for the fact once it runs.
    var expected: String?
}

enum ScoutStop: Equatable, Sendable {
    case user, userInput, focusLost, relaunched
    /// The Mac's displays slept or the person switched users; the build goes on once they're back.
    case away(DemoAwayReason)
    case leftScope(String)
    case needsApproval(PendingApproval)
    case blocked(reason: String, alternative: String)
    case limit(ScoutLimit)
    case error(DemoError)
}

extension ScoutStop {
    /// Why the build stopped, written for the presenter.
    var message: String {
        switch self {
        case .user: "Build paused."
        case .userInput: "Paused because you clicked or typed in the app."
        case .focusLost: "Paused because the app lost focus."
        case .relaunched: "This build was interrupted. Resume it from the current screen, or use the steps so far."
        case .away(let reason): reason.message(resuming: "build")
        case .leftScope(let reason): reason + " Close it and come back to the app to resume."
        case .needsApproval(let pending): pending.message
        case .blocked(let reason, _): reason
        case .limit(let limit): limit.message
        case .error(let error): error.localizedDescription
        }
    }

    /// The Mac's sleep or a user switch paused it, and it goes on by itself, so it never calls the presenter back.
    var isAway: Bool {
        if case .away = self { true } else { false }
    }
}

enum ScoutResult: Equatable, Sendable {
    case finished
    case stopped(ScoutStop)
}

/// Builds a demo by operating the real app: observe, ask Claude for one action,
/// check it, perform it, wait for the app to settle, and record what happened.
/// Every step it records targets an element it actually saw.
@MainActor
final class DemoScout {
    struct Limits {
        var maxTurns = 24
        var maxDuration = Duration.seconds(240)
        var maxSpendMicroUSD = 2_000_000
        /// How many windows the app may open, each closed again, before the build stops.
        var maxClosedWindows = 3
        var settleMinimum = Duration.milliseconds(400)
        var settlePoll = Duration.milliseconds(250)
        /// How long an input that showed nothing gets to show, with a fresh look after it,
        /// before the same input goes out again by another route.
        var effectWindow = Duration.milliseconds(1_200)
        /// How long each chosen highlight is shown while building.
        var beatPreview = Duration.milliseconds(650)
        /// How long scrolling a target into view may take to settle.
        var framing = DemoFramer.Timing()
    }

    private(set) var demo: RealTimeDemo
    private let source: DemoSource
    private let driver: any DemoDriving
    private let model: any DemoModeling
    private let key: String
    private let limits: Limits
    private let language: ScriptLanguage
    /// The presenter always allows this app, which answers the questions trust covers.
    private let trustsApp: Bool
    /// When the presenter last clicked, scrolled or typed outside BetterMeets.
    private let lastPresenterInput: () -> ContinuousClock.Instant?
    private let check: () throws -> Void
    private let onUpdate: (RealTimeDemo, String) -> Void
    private var info: DemoAppInfo
    private var baseline: DemoScopeBaseline
    /// When the scout last looked for windows outside the baseline.
    private var scopeLookedAt = ContinuousClock.now
    /// Windows the app opened that the scout closed again, so the build could go on.
    private var closedWindows = 0
    private(set) var progress = ScoutProgress()
    private var interrupted = false
    /// The look the last action settled on, which the next turn takes as its own
    /// while nothing has happened since.
    private var settledLook: SettledLook?
    /// This run's turns so far, for the line logged when it ends.
    private(set) var timings = DemoRunTimings()
    /// Where the turn in progress spends its time, since when, what it did, and
    /// the driver's pause waits before it.
    private var turnTimings = DemoTurnTimings()
    private var turnBegan: ContinuousClock.Instant?
    private var turnAction = "look"
    private var waitedBeforeTurn = Duration.zero
    /// When this run began, for its time limit.
    private var runStarted = ContinuousClock.now

    /// A look two in a row agreed on, ready and not newly busy, with what it needs to
    /// stand in for the next turn's.
    struct SettledLook {
        var snapshot: AXSnapshot
        /// When the first of the two agreeing looks began: input after it may not show.
        var since: ContinuousClock.Instant
        /// The app's windows right after it.
        var scope: DemoScopeBaseline
    }

    init(
        demo: RealTimeDemo, source: DemoSource, driver: any DemoDriving, model: any DemoModeling, key: String,
        limits: Limits = Limits(), language: ScriptLanguage = .automatic, trustsApp: Bool = false,
        lastPresenterInput: @escaping () -> ContinuousClock.Instant? = { nil }, check: @escaping () throws -> Void,
        onUpdate: @escaping (RealTimeDemo, String) -> Void
    ) throws {
        self.demo = demo
        self.source = source
        self.driver = driver
        self.model = model
        self.key = key
        self.limits = limits
        self.language = language
        self.trustsApp = trustsApp
        self.lastPresenterInput = lastPresenterInput
        self.check = check
        self.onUpdate = onUpdate
        info = try driver.appInfo(for: source)
        baseline = driver.scopeBaseline(source)
    }

    private var framer: DemoFramer {
        DemoFramer(driver: driver, source: source, timing: limits.framing, check: check)
    }

    private var draft: ScoutDraft {
        get { demo.draft ?? ScoutDraft() }
        set { demo.status = .draft(newValue) }
    }

    private var startHost: String? { demo.start?.url?.host }

    /// Marks the in-flight action after the presenter stopped the build.
    func interrupt(byUserInput: Bool) {
        interrupted = true
        guard var last = draft.records.last else { return }
        switch last.outcome {
        case .pending:
            // Never dispatched.
            dropLastRecord()
        case .unobserved where byUserInput:
            last.outcome = .contaminated
            last.fact += " The presenter used the mouse or keyboard while it ran; check the screen."
            draft.records[draft.records.count - 1] = last
        default:
            break
        }
        onUpdate(demo, "")
    }

    func run(approved approval: PendingApproval? = nil, skipped: PendingApproval? = nil) async throws -> ScoutResult {
        let started = ContinuousClock.now
        runStarted = started
        timings = DemoRunTimings()
        defer { endTimings() }
        // A stopped run's last look is stale by the time anyone resumes it.
        settledLook = nil
        if let skipped {
            appendFact(turn: draft.turn, "Presenter declined: \(skipped.message) Choose another way or call blocked.")
        }
        var approval = approval
        while true {
            endTurn()
            try check()
            if draft.turn >= limits.maxTurns { return .stopped(.limit(.turns)) }
            if ContinuousClock.now - started >= limits.maxDuration { return .stopped(.limit(.time)) }
            if draft.spentMicroUSD >= limits.maxSpendMicroUSD { return .stopped(.limit(.budget)) }
            if ScoutCompaction.compact(draft).count >= RealTimeDemo.maximumSteps {
                return .stopped(.limit(.steps))
            }
            if progress.isStuck { return .stopped(.limit(.stuck)) }
            if progress.keepsBeingDenied { return .stopped(.limit(.denied)) }

            beginTurn()
            update(draft.turn == 0 ? "Looking at \(source.name)" : "Looking at the screen")
            let snapshot = try await look()
            try check()
            resolveUnobservedRecord()
            if demo.start == nil { demo.start = startPoint(from: snapshot) }

            if let pending = approval {
                approval = nil
                turnAction = pending.action.logName
                if let result = try await perform(
                    pending.action, title: pending.title, script: pending.script, expected: pending.expected,
                    snapshot: snapshot, approved: true, approvedReason: pending.message)
                {
                    return result
                }
                continue
            }

            let shot = ContinuousClock.now
            let screenshot = try await driver.screenshot(source)
            turnTimings.screenshot += ContinuousClock.now - shot
            try check()
            let encoded = DemoSceneEncoder.encode(snapshot)
            update(draft.turn == 0 ? "Planning the demo" : "Deciding what’s next")
            let reply = try await ask(snapshot: snapshot, screenshot: screenshot, encoded: encoded)
            try check()
            draft.turn += 1
            turnAction = reply.decision.logName
            draft.spentMicroUSD += reply.costMicroUSD
            if draft.outline.isEmpty, !reply.outline.isEmpty {
                draft.outline = Array(reply.outline.prefix(7))
                demo.outline = draft.outline
            }
            judge(reply.previous)
            if let result = try await handle(reply, snapshot: snapshot, listed: encoded.listed) {
                return result
            }
        }
    }

    // MARK: Model

    /// Asks for the turn's action. A reply with no tool call, an element that isn't
    /// listed or can't be found again, or arguments that can't work is asked again
    /// once, about the same look and screenshot, with what was wrong: it costs no
    /// turn, never counts toward the stuck limit, and keeps the cached prefix. When
    /// that second reply has no tool call, the first is rejected instead, spending the turn.
    private func ask(
        snapshot: AXSnapshot, screenshot: DemoWindowScreenshot.Capture, encoded: (text: String, listed: Set<Int>)
    ) async throws -> ScoutReply {
        var request = ScoutTurnRequest(
            prompt: demo.prompt, appName: source.name, engine: info.engine,
            start: demo.start?.url.map { "\($0.host ?? "")\($0.path)" } ?? "native app", outline: draft.outline,
            facts: facts(), turn: draft.turn + 1, maxTurns: limits.maxTurns, screenshot: screenshot,
            elements: encoded.text, correction: nil, language: language)
        var setAside: ScoutReply?
        for attempt in 0..<2 {
            let asked = ContinuousClock.now
            do {
                var reply = try await model.scoutTurn(request, key: key)
                noteModelCall(since: asked, tokens: reply.tokens)
                if reply.outline.isEmpty { reply.outline = setAside?.outline ?? [] }
                guard attempt == 0, let problem = problem(with: reply.decision, in: snapshot, listed: encoded.listed)
                else { return reply }
                try check()
                AppLog.demoMode.info("The scout's reply couldn't be used; asking again about the same screen")
                // Set aside, but paid for.
                draft.spentMicroUSD += reply.costMicroUSD
                reply.costMicroUSD = 0
                setAside = reply
                request.correction =
                    "Your previous reply couldn’t be used: \(problem) Choose again for this same screen."
                continue
            } catch let failure as DemoModelFailure {
                noteModelCall(since: asked, tokens: failure.tokens)
                // Failed calls still cost money and count toward the build limit.
                draft.spentMicroUSD += failure.costMicroUSD
                guard case DemoModelError.noToolCall(let text) = failure.underlying else { throw failure.underlying }
                try check()
                if attempt == 0 {
                    request.correction = "Your previous reply had no tool call. Call exactly one of the tools."
                    continue
                }
                // Prose in answer to the correction ends nothing: the reply it corrected is rejected instead.
                if let setAside { return setAside }
                let reason = text.isEmpty ? "Claude couldn’t decide on a next step." : String(text.prefix(200))
                return ScoutReply(decision: .blocked(reason: reason, alternative: ""), outline: [], costMicroUSD: 0)
            }
        }
        throw DemoError.invalidResponse
    }

    private func noteModelCall(since asked: ContinuousClock.Instant, tokens: DemoTokenUsage) {
        turnTimings.model += ContinuousClock.now - asked
        turnTimings.modelCalls += 1
        turnTimings.tokens += tokens
    }

    // MARK: Decisions

    /// A listed element's locator, proven to find it again.
    static func target(_ id: Int, in snapshot: AXSnapshot, listed: Set<Int>) -> (DemoElementLocator, AXNode)? {
        guard listed.contains(id), let node = snapshot.node(id),
            let locator = DemoLocatorFactory.locator(for: id, in: snapshot)
        else { return nil }
        return (locator, node)
    }

    /// What a click on `id` clicks: text or an icon inside a link or button stands for that control.
    static func clickTarget(_ id: Int, in snapshot: AXSnapshot, listed: Set<Int>) -> (DemoElementLocator, AXNode)? {
        guard listed.contains(id), let node = snapshot.node(id) else { return nil }
        if !node.roleClass.isInteractive, node.roleClass != .row, node.roleClass != .cell,
            let ancestor = node.interactiveAncestorID,
            let locator = DemoLocatorFactory.locator(for: ancestor, in: snapshot),
            let parent = snapshot.node(ancestor)
        {
            return (locator, parent)
        }
        return target(id, in: snapshot, listed: listed)
    }

    /// Why `decision` can't be carried out on this look, before anything is tried:
    /// an element that isn't listed or can't be found again, or arguments that
    /// can't work. Nil when it can be tried.
    func problem(with decision: ScoutDecision, in snapshot: AXSnapshot, listed: Set<Int>) -> String? {
        func unusable(_ id: Int) -> String {
            listed.contains(id)
                ? "element \(id) can’t be found again reliably; choose a uniquely labelled element or its row."
                : "element \(id) isn’t in the current list; use an ID from it."
        }
        switch decision {
        case .click(let id, _, _):
            return Self.clickTarget(id, in: snapshot, listed: listed) == nil ? unusable(id) : nil
        case .typeText(let id, let text, _, _, _):
            guard let (_, node) = Self.target(id, in: snapshot, listed: listed) else { return unusable(id) }
            guard node.roleClass == .field, (1...80).contains(text.count),
                !DemoActionPolicy.containsControlCharacters(text)
            else { return "type_text needs a text field and 1–80 characters with no line breaks or tabs." }
            return nil
        case .openURL(let address, _, _):
            guard info.isBrowser, address.count <= 300, let url = URL(string: address), url.host != nil else {
                return "open_url only works in a browser, with a full http(s) address."
            }
            return nil
        case .scroll(let containerID?, _) where snapshot.node(containerID) == nil:
            return unusable(containerID)
        case .present(let beats):
            let targets = beats.prefix(4).flatMap { $0.elementIDs.prefix(6) }
            guard targets.contains(where: { Self.target($0, in: snapshot, listed: listed) != nil }) else {
                return "none of those element IDs could be highlighted reliably."
            }
            return nil
        case .press, .scroll, .finish, .blocked:
            return nil
        }
    }

    private func handle(_ reply: ScoutReply, snapshot: AXSnapshot, listed: Set<Int>) async throws -> ScoutResult? {
        let turn = draft.turn
        let decision = reply.decision
        func locator(_ id: Int) -> (DemoElementLocator, AXNode)? { Self.target(id, in: snapshot, listed: listed) }
        let expected = ScoutNote.expectation(reply.expect)
        let note = ScoutNote.target(reply.target)
        // Asked again once already when it couldn't be tried; now the turn is spent on it.
        if let problem = problem(with: decision, in: snapshot, listed: listed) {
            reject(turn, problem)
            return nil
        }

        switch decision {
        case .finish(let title, let startDescription, let startLabel, let closingScript):
            // Compiled as the demo will be: detours cut, except where Claude says a turn shows a beat.
            draft.coverage = reply.coverage
            let kept = ScoutCompaction.kept(draft.records, keeping: draft.citedTurns)
            let steps = ScoutCompaction.steps(from: draft.records, kept: kept)
            guard !steps.isEmpty else {
                return .stopped(.blocked(reason: "Claude finished without recording any steps.", alternative: ""))
            }
            if let toggle = Self.unrestoredToggle(in: steps),
                !draft.records.contains(where: {
                    $0.fact.contains("restore") && $0.turn == turn - 1
                })
            {
                // Replays must leave the app as they found it, or the next run starts flipped.
                reject(turn, "restore “\(toggle)” to how it was at the start before finishing.")
                return nil
            }
            // Turned back once per build, and only with a turn left to act on it. It never
            // counts toward the stuck limit, which would end a build that was about to finish.
            if draft.finishTurnedBack != true, hasTurnLeft(steps: steps.count),
                let gap = ScoutCoverage.gap(
                    outline: draft.outline, coverage: reply.coverage,
                    shown: Set(kept.filter { !draft.records[$0].steps.isEmpty }.map { draft.records[$0].turn }),
                    highlighted: steps.contains { !$0.action.isMutating }, prompt: demo.prompt)
            {
                draft.finishTurnedBack = true
                appendFact(turn: turn, "rejected finish: \(gap)")
                return nil
            }
            demo.title = String((title.isEmpty ? demo.title : title).prefix(80))
            demo.closingScript = String(closingScript.prefix(300))
            demo.start?.description = String(startDescription.prefix(200))
            demo.start?.label = startLabel.isEmpty ? nil : String(startLabel.prefix(32))
            update("Recorded \(steps.count) steps")
            return .finished

        case .blocked(let reason, let alternative):
            return .stopped(.blocked(reason: String(reason.prefix(300)), alternative: String(alternative.prefix(120))))

        case .click(let id, let title, let script):
            // Every unwrap from here on was checked by `problem(with:in:listed:)`.
            guard var (locator, _) = Self.clickTarget(id, in: snapshot, listed: listed) else { return nil }
            locator.note = note
            return try await perform(
                .click(locator), title: title, script: script, expected: expected, snapshot: snapshot, approved: false)

        case .typeText(let id, let text, let submit, let title, let script):
            guard var (field, _) = locator(id) else { return nil }
            field.note = note
            return try await perform(
                .typeText(field: field, text: text, submit: submit), title: title, script: script, expected: expected,
                snapshot: snapshot, approved: false)

        case .press(let key, let title, let script):
            return try await perform(
                .press(key), title: title, script: script, expected: expected, snapshot: snapshot, approved: false)

        case .openURL(let address, let title, let script):
            guard let url = URL(string: address) else { return nil }
            return try await perform(
                .navigate(url), title: title, script: script, expected: expected, snapshot: snapshot, approved: false)

        case .scroll(let containerID, let down):
            let container = containerID.flatMap { snapshot.node($0) }
            let hint = RevealHint(container: container.map(AXSnapshot.key(for:)), directionDown: down)
            var record = ScoutRecord(
                turn: turn, steps: [], scroll: hint, outcome: .pending, fact: "", screen: snapshot.screenKey)
            save(record)
            update("Scrolling \(down ? "down" : "up")")
            let input: DemoInput =
                Self.scrollTarget(in: snapshot, container: container, down: down)
                .map { .scrollToVisible(ElementHandle(generation: snapshot.generation, id: $0)) }
                ?? .wheel(around: container?.rect, down: down, increments: 4)
            let route = try await driver.perform(input, on: source, pace: .scout) { [weak self] in
                try self?.markDispatched()
            } uncommit: { [weak self] in
                self?.markUndispatched()
            }
            turnTimings.routes.append(route)
            let delivery = driver.lastDelivery
            var settled = try await settle(after: snapshot, maximum: .milliseconds(1_500))
            if settled.digest == snapshot.digest, route == .accessibility, delivery == .sent, case .wheel = input {
                // Accessibility's stand-in read nothing back and the app showed nothing; real scrolling may.
                update("Trying real scrolling")
                let retried = try await driver.perform(
                    .wheel(around: container?.rect, down: down, increments: 4, from: .realWheel), on: source,
                    pace: .scout
                ) {}
                turnTimings.routes.append(retried)
                try check()
                let moved = try await settle(after: settled, maximum: .milliseconds(1_500))
                if moved.digest != settled.digest { record.scroll?.route = .realWheel }
                settled = moved
            }
            // A scroll bar that moved scrolled, though a text view's elements read the same after it.
            record.outcome = settled.digest != snapshot.digest || delivery == .confirmed ? .changed : .noEffect
            let needed = record.scroll?.route?.neededNote.map { " (\($0))" } ?? ""
            record.fact =
                "#\(turn) scrolled \(down ? "down" : "up")\(needed) → "
                + (record.outcome == .changed ? "more content is visible" : "nothing moved")
            replaceLast(record)
            progress.acted(changed: record.outcome == .changed)
            return nil

        case .present(let beats):
            let beats = Array(beats.prefix(4))
            // Each beat's targets, followed from this turn's look through earlier beats' scrolling.
            var pending: [[Int?]] = beats.map { beat in beat.elementIDs.prefix(6).filter { locator($0) != nil } }
            var current = snapshot
            var record = ScoutRecord(turn: turn, steps: [], outcome: .changed, fact: "", screen: snapshot.screenKey)
            var shown: [String] = []
            for (index, beat) in beats.enumerated() {
                // Recorded the way replay meets it: after earlier beats' scrolling, before this one's.
                let targets = pending[index].compactMap { id in
                    id.flatMap { id in DemoLocatorFactory.locator(for: id, in: current).map { (id, $0) } }
                }
                guard !targets.isEmpty else { continue }
                var locators = targets.map(\.1)
                // The note describes the beat's region, so it rides on its first target.
                locators[0].note = ScoutNote.target(beat.target)
                let action = DemoAction.present(DemoBeat(effect: beat.effect, targets: locators))
                let script = String(beat.script.prefix(240))
                let pre = ScreenSignatures.make(current)
                update("Highlighting \(clean(title: beat.title, fallback: "a detail"))")
                let framed = try await framer.frame(
                    targets.map(\.0), in: current, for: .highlight, carrying: pending[(index + 1)...].flatMap { $0 })
                var carried = framed.carried.makeIterator()
                for later in pending.indices.dropFirst(index + 1) {
                    pending[later] = pending[later].map { _ in carried.next() ?? nil }
                }
                current = framed.snapshot
                record.steps.append(
                    DemoStep(
                        title: clean(title: beat.title, fallback: beat.effect.label), script: script,
                        holdSeconds: DemoStep.hold(for: script, action: action), action: action, pre: pre,
                        framing: framed.shift))
                let scrolled = abs(framed.shift) * current.windowFrame.height >= 1 ? " (scrolled into view)" : ""
                shown.append(
                    "\(beat.effect.rawValue) "
                        + targets.map { "“\(String($0.1.displayName.prefix(40)))”" }
                        .joined(separator: " + ") + scrolled)
                record.fact = "#\(turn) showed " + shown.joined(separator: "; ")
                // Kept at once, so a pause during a later beat never loses the scrolling this one did.
                if record.steps.count == 1 { save(record) } else { replaceLast(record) }
                let nodes = framed.ids?.compactMap { current.node($0) } ?? []
                driver.show(
                    DemoCue(
                        effect: beat.effect,
                        rect: DemoFraming.cueRect(
                            for: nodes, in: current, effect: beat.effect, coveredTop: framed.coveredTop)))
                try await Task.sleep(for: limits.beatPreview)
                try check()
            }
            driver.show(nil)
            guard !record.steps.isEmpty else {
                reject(turn, "none of those element IDs could be highlighted reliably.")
                return nil
            }
            progress.acted(changed: true)
            return nil
        }
    }

    /// Whether a turn spent now still leaves another before a limit stops the build.
    private func hasTurnLeft(steps: Int) -> Bool {
        draft.turn < limits.maxTurns && ContinuousClock.now - runStarted < limits.maxDuration
            && draft.spentMicroUSD < limits.maxSpendMicroUSD && steps < RealTimeDemo.maximumSteps
    }

    /// Checks policy, records the step, performs it, and observes the result
    /// against what Claude `expected`.
    private func perform(
        _ action: DemoAction, title: String, script: String, expected: String?, snapshot: AXSnapshot,
        approved: Bool, approvedReason: String? = nil
    ) async throws -> ScoutResult? {
        let turn = draft.turn
        var node: AXNode?
        for locator in action.locators {
            guard let id = DemoLocatorMatcher.match(locator, in: snapshot).nodeID else {
                reject(turn, "the element for “\(title)” is no longer on screen.")
                return nil
            }
            node = snapshot.node(id)
        }

        if let previous = draft.records.last, previous.outcome == .noEffect,
            let previousAction = previous.steps.first?.action, previousAction.isMutating,
            Self.sameTarget(previousAction, action)
        {
            reject(turn, "that is the same action that just had no visible change.")
            return nil
        }

        var approved = approved
        var approvedReason = approvedReason
        let decision = Self.policy(
            for: action, node: node, snapshot: snapshot, prompt: demo.prompt, startHost: startHost, approved: approved,
            approvedReason: approvedReason)
        switch decision {
        case .deny(let reason):
            deny(turn, reason + " Present it instead if it matters.")
            return nil
        case .needsApproval(let approval) where trustsApp && approval.kind.isCoveredByTrust:
            // Always Allow answers it, and the step records it as if the presenter had.
            approved = true
            approvedReason = approval.message
        case .needsApproval(let approval):
            return .stopped(
                .needsApproval(
                    PendingApproval(
                        action: action, title: title, script: script, message: approval.message, kind: approval.kind,
                        rect: node?.rect, expected: expected)))
        case .allow:
            break
        }

        let pre = ScreenSignatures.make(snapshot)
        // A target the viewport cuts is scrolled into view first, as replay will. The step
        // is still recorded from the screen before, which is what replay resolves it on.
        var look = snapshot
        var target = node?.id
        var framing: Double?
        if let node {
            let framed = try await framer.frame([node.id], in: snapshot, for: .action)
            look = framed.snapshot
            target = framed.ids?.first
            framing = framed.shift
        }
        let step = DemoStep(
            title: clean(title: title, fallback: action.kindLabel), script: String(script.prefix(240)),
            holdSeconds: DemoStep.hold(for: script, action: action), action: action, pre: pre, approved: approved,
            approvedReason: approvedReason, framing: framing)
        guard node == nil || target != nil else {
            // Left out of the demo, with the scrolling it did, which replay accounts for.
            reject(turn, "the element for “\(title)” moved out of reach while scrolling it into view.", keeping: [step])
            return nil
        }
        // Where framing moved the target, for looking it up again after the action.
        let framedOffset = -(framing ?? 0)
        save(
            ScoutRecord(
                turn: turn, steps: [step], outcome: .pending, fact: "", expected: expected, screen: snapshot.screenKey))
        update(progressText(for: action, title: step.title))

        let input: DemoInput
        let name = action.locators.first?.displayName ?? step.title
        switch action {
        case .click: input = .click(ElementHandle(generation: look.generation, id: target ?? -1), name: name)
        case .typeText(_, let text, let submit):
            input = .type(
                ElementHandle(generation: look.generation, id: target ?? -1), name: name, text: text, submit: submit)
        case .press(let key): input = .press(key)
        case .navigate(let url): input = .navigate(url)
        case .present: return nil
        }

        let route: DemoInputRoute?
        do {
            route = try await driver.perform(input, on: source, pace: .scout) { [weak self] in
                try self?.markDispatched()
            } uncommit: { [weak self] in
                self?.markUndispatched()
            }
            turnTimings.routes.append(route)
        } catch let error as DemoError {
            switch error {
            case .occluded, .typingFailed, .targetNotFound, .policyDenied, .addressBarUnavailable, .inputNotDelivered:
                // Nothing reached the app (or the app refused), so the record never happened.
                let last = draft.records.last?.outcome
                if last == .pending || (last == .unobserved && error.wasNotDelivered) {
                    dropLastRecord()
                    if case .policyDenied = error {
                        // The driver's own check of the element it hit, which is the policy too.
                        deny(turn, "\(describe(action)) failed: \(error.localizedDescription)")
                    } else {
                        reject(turn, "\(describe(action)) failed: \(error.localizedDescription)")
                    }
                    return nil
                }
                throw error
            default:
                throw error
            }
        }
        var delivery = driver.lastDelivery
        var deliveredAt = ContinuousClock.now
        try check()

        let maximum: Duration =
            switch action {
            case .navigate: .seconds(10)
            case .typeText(_, _, let submit): submit ? .seconds(8) : .seconds(2)
            case .press: .seconds(2)
            default: .seconds(4)
            }
        var settled = try await settle(after: look, maximum: maximum)
        try check()
        // Compared with the framed look, so scrolling the target in never counts as the action's effect.
        var changed = Self.changed(from: look, to: settled) || delivery == .confirmed
        var record =
            draft.records.last
            ?? ScoutRecord(
                turn: turn, steps: [step], outcome: .pending, fact: "", expected: expected, screen: snapshot.screenKey)
        // The app showed nothing, as some controls that close at once while their window
        // isn't focused do: try the next route, once each, before telling Claude it failed.
        // Never once a window opened, even one the presenter may have, since a click that
        // opened one changed nothing here and clicking again would open another; never for
        // input that may already have acted; and never for a control a second click could
        // do twice. Windows the presenter may have opened join the baseline only after.
        var used = route
        while !changed, delivery == .sent, driver.scopeViolation(source, since: baseline) == nil,
            Self.triesAgain(action, node: node, approved: approved),
            let next = Self.retryRoute(after: used, for: action)
        {
            // An app slow to show the last try gets the whole effect window, and a fresh look, first.
            let left = limits.effectWindow - (ContinuousClock.now - deliveredAt)
            if left > .zero {
                try await Task.sleep(for: left)
                try check()
                let later = try await settle(after: settled, maximum: maximum)
                try check()
                changed = Self.changed(from: settled, to: later)
                settled = later
                if changed || driver.scopeViolation(source, since: baseline) != nil { break }
            }
            guard let retry = retryInput(for: action, from: next, in: settled, offset: framedOffset, name: name)
            else { break }
            update(Self.retryActivity(for: action, from: next))
            do {
                used = try await driver.perform(retry, on: source, pace: .scout) {}
            } catch let error as DemoError where error.wasNotDelivered {
                // Something else is where the target was, perhaps what the first try opened while
                // the retry waited for a pause: nothing went out, so look again instead.
                try check()
                let later = try await settle(after: settled, maximum: maximum)
                changed = Self.changed(from: settled, to: later)
                settled = later
                break
            }
            delivery = driver.lastDelivery
            deliveredAt = .now
            turnTimings.routes.append(used)
            try check()
            let retried = try await settle(after: settled, maximum: maximum)
            try check()
            changed = Self.changed(from: settled, to: retried) || delivery == .confirmed
            settled = retried
            if changed { record.steps[0].route = Self.recordedRoute(used, for: action) }
        }
        record.outcome = changed ? .changed : .noEffect
        if case .click(var locator) = action, locator.roleClass == .checkbox,
            let id = DemoLocatorMatcher.match(locator.shifted(by: framedOffset), in: settled).nodeID,
            let value = settled.node(id)?.toggleValue
        {
            locator.toggleValueAfter = value
            record.steps[0].action = .click(locator)
        }
        let needed = record.steps.first?.route.neededNote.map { " (\($0))" } ?? ""
        let observed =
            changed ? ScoutObservation.summary(from: look, to: settled) : "no visible change; don’t repeat it"
        record.fact =
            "#\(turn) \(describe(action))\(needed) → " + (expected.map { "expected: \($0) / " } ?? "") + "observed: "
            + observed
        replaceLast(record)
        progress.acted(changed: changed)

        adoptPresenterWindows()
        if let violation = driver.scopeViolation(source, since: baseline) {
            // A window the action just opened can't be on the stage. Close it, leave the
            // action out of the demo and let Claude find another way.
            guard closedWindows < limits.maxClosedWindows, await driver.closeWindows(source, openedSince: baseline)
            else {
                return .stopped(.leftScope(violation))
            }
            settledLook = nil
            closedWindows += 1
            try check()
            record.outcome = .rejected
            record.fact =
                "#\(turn) \(describe(action)) → opened a separate window, which BetterMeets closed. The demo can only "
                + "show this window, so reach it another way or move on."
            replaceLast(record)
        }
        return nil
    }

    /// Whether an input that showed nothing may go out again by another route: any key,
    /// and any click but one the presenter approved, which they approved once, or one
    /// a second click could do twice (`DemoElementLocator.clickingAgainCouldRepeat`).
    private static func triesAgain(_ action: DemoAction, node: AXNode?, approved: Bool) -> Bool {
        switch action {
        case .click(let locator): !approved && !locator.clickingAgainCouldRepeat(node: node)
        case .press: true
        case .typeText, .navigate, .present: false
        }
    }

    /// The route to try again for an input that reached the app through `used` and
    /// changed nothing on screen: the page's own click after Accessibility's press
    /// (the driver gives a real click where the page can't), a real click after the
    /// page's, and the real key after Accessibility's stand-in. Nil after real input.
    static func retryRoute(after used: DemoInputRoute?, for action: DemoAction) -> DemoStepRoute? {
        switch (action, used) {
        case (.click, _): DemoStepRoute.afterSilentClick(used)
        case (.press, .accessibility): .realKey
        default: nil
        }
    }

    /// What a retry that changed the screen through `used` records on the step, so replay starts there.
    static func recordedRoute(_ used: DemoInputRoute?, for action: DemoAction) -> DemoStepRoute {
        switch (action, used) {
        case (.click, _): DemoStepRoute(click: used)
        case (.press, .borrowedScreen), (.press, .foreground): .realKey
        default: .accessibility
        }
    }

    private static func retryActivity(for action: DemoAction, from route: DemoStepRoute) -> String {
        if case .press(let key) = action { return "Trying the real \(key.badge) key" }
        return retryActivity(clicking: action.locators.first?.displayName ?? "", from: route)
    }

    /// What the panel's progress says while a click on `name` is tried again from `route`.
    static func retryActivity(clicking name: String, from route: DemoStepRoute) -> String {
        let name = String(name.prefix(40))
        return route == .pointer ? "Trying a real click on \(name)" : "Trying another click on \(name)"
    }

    /// `action` again from `route`, aimed at its target as the settled screen has it.
    private func retryInput(
        for action: DemoAction, from route: DemoStepRoute, in settled: AXSnapshot, offset: Double, name: String
    ) -> DemoInput? {
        switch action {
        case .click(let locator):
            guard let id = DemoLocatorMatcher.match(locator.shifted(by: offset), in: settled).nodeID else { return nil }
            return .click(ElementHandle(generation: settled.generation, id: id), name: name, from: route)
        case .press(let key):
            return .press(key, from: route)
        case .typeText, .navigate, .present:
            return nil
        }
    }

    /// The presenter keeps using their Mac while the demo builds, so a window of the
    /// app that appeared after their own input since the last look (or a second
    /// before it) may be one they opened: it joins the baseline and is never
    /// closed. Only a window that appeared with no input from them is the demo's.
    private func adoptPresenterWindows() {
        defer { scopeLookedAt = .now }
        guard let input = lastPresenterInput(), input >= scopeLookedAt.advanced(by: .seconds(-1)),
            driver.scopeViolation(source, since: baseline) != nil
        else { return }
        AppLog.demoMode.info("A new window of the demo's app appeared while the presenter was busy; leaving it open")
        baseline = driver.scopeBaseline(source)
    }

    static func changed(from before: AXSnapshot, to after: AXSnapshot) -> Bool {
        after.digest != before.digest || after.webURL != before.webURL
            || after.focusedID.map { after.node($0)?.label } != before.focusedID.map { before.node($0)?.label }
    }

    // MARK: Settling

    /// Waits until two consecutive snapshots agree, web content has loaded, and no
    /// spinner or progress bar shows that `previous`, the look before the action,
    /// didn't, up to `maximum`. A look that settles is kept for the next turn.
    func settle(after previous: AXSnapshot, maximum: Duration) async throws -> AXSnapshot {
        let start = ContinuousClock.now
        var polls = 0
        defer {
            turnTimings.settle += ContinuousClock.now - start
            turnTimings.settlePolls += polls
        }
        settledLook = nil
        try await Task.sleep(for: limits.settleMinimum)
        var began = ContinuousClock.now
        var last = try await read()
        polls += 1
        while ContinuousClock.now - start < maximum {
            try await Task.sleep(for: limits.settlePoll)
            try check()
            let looked = ContinuousClock.now
            let next = try await read()
            polls += 1
            let ready = next.webContent.map(\.isReady) ?? true
            if next.digest == last.digest, ready, !next.isBusier(than: previous) {
                settledLook = SettledLook(snapshot: next, since: began, scope: driver.scopeBaseline(source))
                return next
            }
            last = next
            began = looked
        }
        turnTimings.unsettled += 1
        return last
    }

    /// The turn's look: the one the last action settled on when nothing has happened
    /// since, else a fresh one. A settled look is the newest snapshot taken, so its
    /// element handles still resolve.
    private func look() async throws -> AXSnapshot {
        let settled = settledLook
        settledLook = nil
        if let settled,
            Self.reuses(
                settled, lastPresenterInput: lastPresenterInput(), scope: driver.scopeBaseline(source),
                windowFrame: driver.windowFrame(source))
        {
            turnTimings.reusedLook = true
            turnTimings.nodes = settled.snapshot.nodes.count
            return settled.snapshot
        }
        return try await read(waitForContent: true)
    }

    /// Reads the window, timed for the turn's line.
    private func read(waitForContent: Bool = false) async throws -> AXSnapshot {
        let started = ContinuousClock.now
        let snapshot = try await driver.snapshot(source, waitForContent: waitForContent)
        turnTimings.walk += ContinuousClock.now - started
        turnTimings.walks += 1
        turnTimings.nodes = snapshot.nodes.count
        return snapshot
    }

    /// Whether a settled look still shows the app: the presenter hasn't clicked,
    /// scrolled or typed since it began, no window of the app opened or closed,
    /// and the window hasn't moved or changed size.
    static func reuses(
        _ look: SettledLook, lastPresenterInput: ContinuousClock.Instant?, scope: DemoScopeBaseline,
        windowFrame: CGRect?
    ) -> Bool {
        if let input = lastPresenterInput, input >= look.since { return false }
        return scope == look.scope && windowFrame == look.snapshot.windowFrame
    }

    // MARK: Timings

    private func beginTurn() {
        turnTimings = DemoTurnTimings()
        turnBegan = .now
        turnAction = "look"
        waitedBeforeTurn = driver.waitedForPause
    }

    /// Logs the turn that just ended, if one began, and adds it to the run's.
    private func endTurn() {
        guard let began = turnBegan else { return }
        turnBegan = nil
        turnTimings.total = ContinuousClock.now - began
        turnTimings.pauseWait = driver.waitedForPause - waitedBeforeTurn
        timings.add(turnTimings)
        let line = turnTimings.line("build turn=\(draft.turn) action=\(turnAction)")
        AppLog.demoTimings.info("\(line, privacy: .public)")
    }

    /// Logs the last turn and the run's totals, however the run ended.
    private func endTimings() {
        endTurn()
        let summary = timings.summary("build ended")
        AppLog.demoTimings.info("\(summary, privacy: .public)")
    }

    // MARK: Start point

    private func startPoint(from snapshot: AXSnapshot) -> DemoStartPoint {
        let visible = snapshot.nodes.filter(\.isVisible)
        let toggles = visible.filter { $0.roleClass == .checkbox && $0.toggleValue != nil }
            .filter { LabelStability.isStable(roleClass: .checkbox, label: $0.label) }
            .prefix(12)
            .compactMap { node -> ToggleState? in
                guard let locator = DemoLocatorFactory.locator(for: node.id, in: snapshot), let value = node.toggleValue
                else { return nil }
                return ToggleState(locator: locator, isOn: value)
            }
        var anchor: DemoElementLocator?
        if !info.isBrowser {
            let candidate = DemoLocatorMatcher.ordered(visible).first { node in
                node.isSelected && [.tab, .radio, .link, .row, .button].contains(node.roleClass)
                    && LabelStability.isStable(roleClass: node.roleClass, label: node.label)
                    && (node.rect.midX < 0.3 || node.rect.midY < 0.15)
            }
            anchor = candidate.flatMap { DemoLocatorFactory.locator(for: $0.id, in: snapshot) }
        }
        return DemoStartPoint(
            signature: ScreenSignatures.make(snapshot), url: info.isBrowser ? snapshot.webURL : nil,
            returnAnchor: anchor, toggles: Array(toggles), description: "", sizeClass: info.sizeClass)
    }

    // MARK: Records

    private func save(_ record: ScoutRecord) {
        guard !interrupted else { return }
        draft.records.append(record)
        onUpdate(demo, "")
    }

    private func replaceLast(_ record: ScoutRecord) {
        guard !interrupted, !draft.records.isEmpty else { return }
        draft.records[draft.records.count - 1] = record
        onUpdate(demo, "")
    }

    private func markDispatched() throws {
        guard !interrupted else { throw CancellationError() }
        try check()
        guard var last = draft.records.last, last.outcome == .pending else { return }
        last.outcome = .unobserved
        last.fact =
            "#\(last.turn) \(last.steps.first.map { describe($0.action) } ?? "scroll") → result not observed yet"
        draft.records[draft.records.count - 1] = last
        onUpdate(demo, "")
    }

    /// The driver handed the commit back: the route that committed delivered nothing,
    /// so a pause before the next one delivers drops the record as never dispatched.
    private func markUndispatched() {
        guard var last = draft.records.last, last.outcome == .unobserved else { return }
        last.outcome = .pending
        last.fact = ""
        draft.records[draft.records.count - 1] = last
        onUpdate(demo, "")
    }

    /// A step dispatched before a pause or relaunch: keep it, and let the next
    /// observation (and verification) decide what it did.
    private func resolveUnobservedRecord() {
        guard var last = draft.records.last else { return }
        if last.outcome == .pending {
            dropLastRecord()
        } else if last.outcome == .unobserved {
            last.outcome = .contaminated
            last.fact = last.fact.replacingOccurrences(
                of: "result not observed yet", with: "result unknown; check the screen")
            draft.records[draft.records.count - 1] = last
        }
    }

    /// `keeping` holds steps left out of the demo whose framing scrolled all the same.
    private func reject(_ turn: Int, _ reason: String, keeping steps: [DemoStep] = []) {
        save(ScoutRecord(turn: turn, steps: steps, outcome: .rejected, fact: "#\(turn) rejected: \(reason)"))
        progress.rejected()
    }

    /// The policy turned the action down: Claude hears why, and the turn counts
    /// toward the denial limit instead of the stuck limit.
    private func deny(_ turn: Int, _ reason: String) {
        save(ScoutRecord(turn: turn, steps: [], outcome: .rejected, fact: "#\(turn) rejected: \(reason)"))
        progress.denied()
    }

    /// Keeps Claude's verdict on the last turn's action with its record. A change
    /// Claude says went the wrong way counts toward the stuck limit like one that
    /// never happened; what the demo keeps still follows what was observed.
    private func judge(_ judgement: ScoutJudgement?) {
        guard let judgement, judgement.verdict != .none, var last = draft.records.last, last.turn == draft.turn - 1,
            [.changed, .noEffect, .contaminated].contains(last.outcome)
        else { return }
        let acted = last.scroll != nil || last.steps.contains { $0.action.isMutating }
        if judgement.verdict == .wrongTurn, last.outcome == .changed, acted { progress.wentWrong() }
        last.judgement = ScoutJudgement(verdict: judgement.verdict, reason: ScoutNote.reason(judgement.reason))
        replaceLast(last)
    }

    /// Takes the last record out of the demo. Scrolling its framing did stays on a
    /// record compaction leaves out, which carries it to the next step.
    private func dropLastRecord() {
        guard var last = draft.records.popLast(), last.steps.contains(where: { ($0.framing ?? 0) != 0 }) else {
            return
        }
        last.outcome = .rejected
        last.fact = ""
        draft.records.append(last)
    }

    private func appendFact(turn: Int, _ fact: String) {
        save(ScoutRecord(turn: turn, steps: [], outcome: .rejected, fact: "#\(turn) \(fact)"))
    }

    private func facts() -> [String] {
        let all = draft.records.map(\.fact).filter { !$0.isEmpty }
        guard all.count > 30 else { return all }
        return ["(\(all.count - 30) earlier facts omitted)"] + all.suffix(30)
    }

    private func update(_ activity: String) {
        onUpdate(demo, activity)
    }

    // MARK: Descriptions

    private func describe(_ action: DemoAction) -> String {
        switch action {
        case .click(let locator): "clicked \(locator.roleClass.noun) “\(String(locator.displayName.prefix(40)))”"
        case .typeText(let field, let text, let submit):
            "typed “\(String(text.prefix(40)))” into “\(String(field.displayName.prefix(40)))”\(submit ? " + Return" : "")"
        case .press(let key): "pressed \(key.rawValue)"
        case .navigate(let url): "opened \(url.host ?? "")\(url.path)"
        case .present(let beat): "showed \(beat.effect.rawValue)"
        }
    }

    private func progressText(for action: DemoAction, title: String) -> String {
        switch action {
        case .click(let locator): "Clicking \(String(locator.displayName.prefix(40)))"
        case .typeText(_, let text, _): "Typing “\(String(text.prefix(30)))”"
        case .press(let key): "Pressing \(key.badge)"
        case .navigate(let url): "Opening \(url.host ?? "the page")"
        case .present: title
        }
    }

    private func clean(title: String, fallback: String) -> String {
        let text = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? fallback : String(text.prefix(32))
    }

    // MARK: Policy

    /// Checks an action against the safety policy. An approval covers only the
    /// exact question the presenter answered (for a control with a borrowed name,
    /// also the one asked of it unnamed); demos approved before reasons were
    /// recorded keep their approval. A trusted app answers the questions trust
    /// covers, whatever was recorded.
    static func policy(
        for action: DemoAction, node: AXNode?, snapshot: AXSnapshot? = nil, prompt: String, startHost: String?,
        approved: Bool, approvedReason: String? = nil, trusted: Bool = false
    ) -> DemoPolicyDecision {
        let decision = evaluate(
            action, node: node, snapshot: snapshot, prompt: prompt, startHost: startHost, trusted: trusted)
        guard approved, case .needsApproval(let approval) = decision else { return decision }
        if approvedReason == nil || approvedReason == approval.message { return .allow }
        // A demo saved before the control borrowed a name asked about it unnamed, and
        // that's the question the presenter approved. Denials were judged on the name.
        if var unnamed = node, unnamed.labelIsBorrowed {
            unnamed.label = ""
            if case .needsApproval(let asked) = evaluate(
                action, node: unnamed, snapshot: snapshot, prompt: prompt, startHost: startHost, trusted: trusted),
                asked.message == approvedReason
            {
                return .allow
            }
        }
        return decision
    }

    private static func evaluate(
        _ action: DemoAction, node: AXNode?, snapshot: AXSnapshot?, prompt: String, startHost: String?, trusted: Bool
    ) -> DemoPolicyDecision {
        let policyAction: DemoPolicyAction
        switch action {
        case .click:
            guard let node else { return .deny("That control is no longer on screen.") }
            policyAction = .click(policyElement(node, in: snapshot))
        case .typeText(_, let text, let submit):
            guard let node else { return .deny("That field is no longer on screen.") }
            policyAction = .type(field: policyElement(node, in: snapshot), text: text, submit: submit)
        case .press: policyAction = .pressKey
        case .navigate(let url): policyAction = .navigate(url)
        case .present: return .allow
        }
        return DemoActionPolicy.evaluate(
            policyAction, prompt: prompt, startHost: startHost, approved: false, appTrusted: trusted)
    }

    static func policyElement(_ node: AXNode, in snapshot: AXSnapshot? = nil) -> DemoPolicyElement {
        let kind = DemoDriver.policyKind(role: node.role, subrole: node.subrole) ?? .other
        // Only the control's own words count. A container's text can be its whole
        // contents (“Confirmed” in a details panel); confirmations inside dialogs are
        // covered by the dialog rule instead, whose own text only decides whether
        // trusting the app can answer it.
        let details = [node.help, node.identifier, node.placeholder].compactMap { $0 }
        return DemoPolicyElement(
            kind: kind, label: node.label, labelIsData: node.roleClass == .row || node.roleClass == .cell,
            isSecure: node.isSecure,
            isSearchField: node.subrole == "AXSearchField" || node.role == "AXSearchField", inDialog: node.inDialog,
            dialogText: snapshot?.dialogText(of: node) ?? [], details: details)
    }

    /// The next element past the fold, so scrolling it into view moves the page
    /// by most of a screen without touching the pointer.
    static func scrollTarget(in snapshot: AXSnapshot, container: AXNode?, down: Bool) -> Int? {
        let candidates = snapshot.nodes.filter { node in
            !node.isVisible && !node.isContainer && node.rect.isUsable
                && (container == nil || node.containerID == container?.id)
                && (down ? node.rect.y >= 1 && node.rect.midY <= 1.8 : node.rect.maxY <= 0 && node.rect.midY >= -0.8)
        }
        let best =
            down ? candidates.max { $0.rect.midY < $1.rect.midY } : candidates.min { $0.rect.midY < $1.rect.midY }
        return best?.id
    }

    /// A switch-like button clicked an odd number of times, such as Ledger's
    /// discreet-mode eye, which the demo would leave flipped.
    static func unrestoredToggle(in steps: [DemoStep]) -> String? {
        var counts: [String: (Int, String)] = [:]
        for step in steps {
            guard case .click(let locator) = step.action, locator.labelIsStable,
                locator.roleClass == .button || locator.roleClass == .checkbox,
                DemoElementLocator.namesToggle(locator.label)
            else { continue }
            let key = DemoLocatorFactory.identity(locator)
            counts[key] = ((counts[key]?.0 ?? 0) + 1, locator.label)
        }
        return counts.values.first { $0.0 % 2 == 1 }?.1
    }

    static func sameTarget(_ a: DemoAction, _ b: DemoAction) -> Bool {
        switch (a, b) {
        case (.click(let x), .click(let y)): DemoLocatorFactory.identity(x) == DemoLocatorFactory.identity(y)
        case (.typeText(let x, let t, _), .typeText(let y, let u, _)):
            DemoLocatorFactory.identity(x) == DemoLocatorFactory.identity(y) && t == u
        case (.press(let x), .press(let y)): x == y
        case (.navigate(let x), .navigate(let y)): x == y
        default: false
        }
    }
}
