import Foundation
import MeetStageCore

enum ScoutLimit: String, Equatable, Sendable {
    case turns, steps, time, budget, stuck

    var message: String {
        switch self {
        case .turns: "Stopped after the maximum number of turns."
        case .steps: "Reached the 40-step limit."
        case .time: "Stopped after four minutes."
        case .budget: "Stopped at the $2 build limit."
        case .stuck: "Stopped because the last few actions didn’t change anything."
        }
    }
}

/// An action the policy wants the presenter to approve before the scout runs it.
struct PendingApproval: Equatable, Sendable {
    var action: DemoAction
    var title: String
    var script: String
    var message: String
    var rect: NormRect?
}

enum ScoutStop: Equatable, Sendable {
    case user, userInput, focusLost, relaunched
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
        case .leftScope(let reason): reason + " Close it and come back to the app to resume."
        case .needsApproval(let pending): pending.message
        case .blocked(let reason, _): reason
        case .limit(let limit): limit.message
        case .error(let error): error.localizedDescription
        }
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
        /// How long each chosen highlight is shown while building.
        var beatPreview = Duration.milliseconds(650)
    }

    private(set) var demo: RealTimeDemo
    private let source: DemoSource
    private let driver: any DemoDriving
    private let model: any DemoModeling
    private let key: String
    private let limits: Limits
    private let language: ScriptLanguage
    private let check: () throws -> Void
    private let onUpdate: (RealTimeDemo, String) -> Void
    private var info: DemoAppInfo
    private var baseline: DemoScopeBaseline
    /// Windows the app opened that the scout closed again, so the build could go on.
    private var closedWindows = 0
    private var unchangedTurns = 0
    private var interrupted = false

    init(
        demo: RealTimeDemo, source: DemoSource, driver: any DemoDriving, model: any DemoModeling, key: String,
        limits: Limits = Limits(), language: ScriptLanguage = .automatic, check: @escaping () throws -> Void,
        onUpdate: @escaping (RealTimeDemo, String) -> Void
    ) throws {
        self.demo = demo
        self.source = source
        self.driver = driver
        self.model = model
        self.key = key
        self.limits = limits
        self.language = language
        self.check = check
        self.onUpdate = onUpdate
        info = try driver.appInfo(for: source)
        baseline = driver.scopeBaseline(source)
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
            draft.records.removeLast()
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
        if let skipped {
            appendFact(turn: draft.turn, "Presenter declined: \(skipped.message) Choose another way or call blocked.")
        }
        var approval = approval
        while true {
            try check()
            if draft.turn >= limits.maxTurns { return .stopped(.limit(.turns)) }
            if ContinuousClock.now - started >= limits.maxDuration { return .stopped(.limit(.time)) }
            if draft.spentMicroUSD >= limits.maxSpendMicroUSD { return .stopped(.limit(.budget)) }
            if ScoutCompaction.compact(draft.records).count >= RealTimeDemo.maximumSteps {
                return .stopped(.limit(.steps))
            }
            if unchangedTurns >= 3 { return .stopped(.limit(.stuck)) }

            update(draft.turn == 0 ? "Looking at \(source.name)" : "Looking at the screen")
            let snapshot = try await driver.snapshot(source, waitForContent: true)
            try check()
            resolveUnobservedRecord()
            if demo.start == nil { demo.start = startPoint(from: snapshot) }

            if let pending = approval {
                approval = nil
                if let result = try await perform(
                    pending.action, title: pending.title, script: pending.script, snapshot: snapshot, approved: true,
                    approvedReason: pending.message)
                {
                    return result
                }
                continue
            }

            let screenshot = try await driver.screenshot(source)
            try check()
            let encoded = DemoSceneEncoder.encode(snapshot)
            update(draft.turn == 0 ? "Planning the demo" : "Deciding what’s next")
            let reply = try await ask(snapshot: snapshot, screenshot: screenshot, elements: encoded.text)
            try check()
            draft.turn += 1
            draft.spentMicroUSD += reply.costMicroUSD
            if draft.outline.isEmpty, !reply.outline.isEmpty {
                draft.outline = Array(reply.outline.prefix(7))
                demo.outline = draft.outline
            }
            if let result = try await handle(reply.decision, snapshot: snapshot, listed: encoded.listed) {
                return result
            }
        }
    }

    // MARK: Model

    private func ask(snapshot: AXSnapshot, screenshot: DemoWindowScreenshot.Capture, elements: String)
        async throws -> ScoutReply
    {
        var request = ScoutTurnRequest(
            prompt: demo.prompt, appName: source.name, engine: info.engine,
            start: demo.start?.url.map { "\($0.host ?? "")\($0.path)" } ?? "native app", outline: draft.outline,
            facts: facts(), turn: draft.turn + 1, maxTurns: limits.maxTurns, screenshot: screenshot,
            elements: elements, correction: nil, language: language)
        for attempt in 0..<2 {
            do {
                return try await model.scoutTurn(request, key: key)
            } catch let failure as DemoModelFailure {
                // Failed calls still cost money and count toward the build limit.
                draft.spentMicroUSD += failure.costMicroUSD
                guard case DemoModelError.noToolCall(let text) = failure.underlying else { throw failure.underlying }
                try check()
                if attempt == 0 {
                    request.correction = "Your previous reply had no tool call. Call exactly one of the tools."
                    continue
                }
                let reason = text.isEmpty ? "Claude couldn’t decide on a next step." : String(text.prefix(200))
                return ScoutReply(decision: .blocked(reason: reason, alternative: ""), outline: [], costMicroUSD: 0)
            }
        }
        throw DemoError.invalidResponse
    }

    // MARK: Decisions

    private func handle(_ decision: ScoutDecision, snapshot: AXSnapshot, listed: Set<Int>) async throws
        -> ScoutResult?
    {
        let turn = draft.turn
        func locator(_ id: Int) -> (DemoElementLocator, AXNode)? {
            guard listed.contains(id), let node = snapshot.node(id),
                let locator = DemoLocatorFactory.locator(for: id, in: snapshot)
            else { return nil }
            return (locator, node)
        }
        /// Text or an icon inside a link or button stands for that control.
        func clickTarget(_ id: Int) -> (DemoElementLocator, AXNode)? {
            guard listed.contains(id), let node = snapshot.node(id) else { return nil }
            if !node.roleClass.isInteractive, node.roleClass != .row, node.roleClass != .cell,
                let ancestor = node.interactiveAncestorID,
                let locator = DemoLocatorFactory.locator(for: ancestor, in: snapshot),
                let parent = snapshot.node(ancestor)
            {
                return (locator, parent)
            }
            return locator(id)
        }
        func unusable(_ id: Int) -> ScoutResult? {
            reject(
                turn,
                "element \(id) isn’t in the current list or can’t be found again reliably; choose a uniquely labelled element or its row."
            )
            return nil
        }

        switch decision {
        case .finish(let title, let startDescription, let startLabel, let closingScript):
            let steps = ScoutCompaction.compact(draft.records)
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
            demo.title = String((title.isEmpty ? demo.title : title).prefix(80))
            demo.closingScript = String(closingScript.prefix(300))
            demo.start?.description = String(startDescription.prefix(200))
            demo.start?.label = startLabel.isEmpty ? nil : String(startLabel.prefix(32))
            update("Recorded \(steps.count) steps")
            return .finished

        case .blocked(let reason, let alternative):
            return .stopped(.blocked(reason: String(reason.prefix(300)), alternative: String(alternative.prefix(120))))

        case .click(let id, let title, let script):
            guard let (target, _) = clickTarget(id) else { return unusable(id) }
            return try await perform(.click(target), title: title, script: script, snapshot: snapshot, approved: false)

        case .typeText(let id, let text, let submit, let title, let script):
            guard let (target, node) = locator(id) else { return unusable(id) }
            guard node.roleClass == .field, (1...80).contains(text.count),
                !DemoActionPolicy.containsControlCharacters(text)
            else {
                reject(turn, "type_text needs a text field and 1–80 characters with no line breaks or tabs.")
                return nil
            }
            return try await perform(
                .typeText(field: target, text: text, submit: submit), title: title, script: script,
                snapshot: snapshot, approved: false)

        case .press(let key, let title, let script):
            return try await perform(.press(key), title: title, script: script, snapshot: snapshot, approved: false)

        case .openURL(let address, let title, let script):
            guard info.isBrowser, address.count <= 300, let url = URL(string: address), url.host != nil else {
                reject(turn, "open_url only works in a browser, with a full http(s) address.")
                return nil
            }
            return try await perform(.navigate(url), title: title, script: script, snapshot: snapshot, approved: false)

        case .scroll(let containerID, let down):
            let container = containerID.flatMap { snapshot.node($0) }
            if containerID != nil, container == nil { return unusable(containerID ?? -1) }
            let hint = RevealHint(container: container.map(AXSnapshot.key(for:)), directionDown: down)
            var record = ScoutRecord(turn: turn, steps: [], scroll: hint, outcome: .pending, fact: "")
            save(record)
            update("Scrolling \(down ? "down" : "up")")
            let input: DemoInput =
                Self.scrollTarget(in: snapshot, container: container, down: down)
                .map { .scrollToVisible(ElementHandle(generation: snapshot.generation, id: $0)) }
                ?? .wheel(around: container?.rect, down: down, increments: 4)
            try await driver.perform(input, on: source, pace: .scout) { [weak self] in try self?.markDispatched() }
            let settled = try await settle(after: snapshot, maximum: .milliseconds(1_500))
            record.outcome = settled.digest != snapshot.digest ? .changed : .noEffect
            record.fact =
                "#\(turn) scrolled \(down ? "down" : "up") → "
                + (record.outcome == .changed ? "more content is visible" : "nothing moved")
            replaceLast(record)
            noteProgress(record.outcome == .changed)
            return nil

        case .present(let beats):
            let pre = ScreenSignatures.make(snapshot)
            var steps: [DemoStep] = []
            var shown: [String] = []
            for beat in beats.prefix(4) {
                let targets = beat.elementIDs.prefix(6).compactMap { locator($0) }
                guard !targets.isEmpty else { continue }
                let action = DemoAction.present(DemoBeat(effect: beat.effect, targets: targets.map(\.0)))
                let script = String(beat.script.prefix(240))
                steps.append(
                    DemoStep(
                        title: clean(title: beat.title, fallback: beat.effect.label), script: script,
                        holdSeconds: DemoStep.hold(for: script, action: action), action: action, pre: pre))
                shown.append(
                    "\(beat.effect.rawValue) "
                        + targets.map { "“\(String($0.0.displayName.prefix(40)))”" }
                        .joined(separator: " + "))
                let rect = targets.map(\.1.rect).dropFirst().reduce(targets[0].1.rect) { $0.union($1) }
                update("Highlighting \(clean(title: beat.title, fallback: "a detail"))")
                driver.show(DemoCue(effect: beat.effect, rect: rect))
                try await Task.sleep(for: limits.beatPreview)
                try check()
            }
            driver.show(nil)
            guard !steps.isEmpty else {
                reject(turn, "none of those element IDs could be highlighted reliably.")
                return nil
            }
            save(
                ScoutRecord(
                    turn: turn, steps: steps, outcome: .changed,
                    fact: "#\(turn) showed " + shown.joined(separator: "; ")))
            unchangedTurns = 0
            return nil
        }
    }

    /// Checks policy, records the step, performs it, and observes the result.
    private func perform(
        _ action: DemoAction, title: String, script: String, snapshot: AXSnapshot, approved: Bool,
        approvedReason: String? = nil
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

        let decision = Self.policy(
            for: action, node: node, snapshot: snapshot, prompt: demo.prompt, startHost: startHost, approved: approved,
            approvedReason: approvedReason)
        switch decision {
        case .deny(let reason):
            reject(turn, reason + " Present it instead if it matters.")
            return nil
        case .needsApproval(let message):
            return .stopped(
                .needsApproval(
                    PendingApproval(action: action, title: title, script: script, message: message, rect: node?.rect)))
        case .allow:
            break
        }

        let pre = ScreenSignatures.make(snapshot)
        let step = DemoStep(
            title: clean(title: title, fallback: action.kindLabel), script: String(script.prefix(240)),
            holdSeconds: DemoStep.hold(for: script, action: action), action: action, pre: pre, approved: approved,
            approvedReason: approvedReason)
        save(ScoutRecord(turn: turn, steps: [step], outcome: .pending, fact: ""))
        update(progressText(for: action, title: step.title))

        let input: DemoInput
        let name = action.locators.first?.displayName ?? step.title
        switch action {
        case .click: input = .click(ElementHandle(generation: snapshot.generation, id: node?.id ?? -1), name: name)
        case .typeText(_, let text, let submit):
            input = .type(
                ElementHandle(generation: snapshot.generation, id: node?.id ?? -1), name: name, text: text,
                submit: submit)
        case .press(let key): input = .press(key)
        case .navigate(let url): input = .navigate(url)
        case .present: return nil
        }

        do {
            try await driver.perform(input, on: source, pace: .scout) { [weak self] in try self?.markDispatched() }
        } catch let error as DemoError {
            switch error {
            case .occluded, .typingFailed, .targetNotFound, .policyDenied, .addressBarUnavailable, .inputNotDelivered:
                // Nothing reached the app (or the app refused), so the record never happened.
                let last = draft.records.last?.outcome
                if last == .pending || (last == .unobserved && error.wasNotDelivered) {
                    draft.records.removeLast()
                    reject(turn, "\(describe(action)) failed: \(error.localizedDescription)")
                    return nil
                }
                throw error
            default:
                throw error
            }
        }
        try check()

        let maximum: Duration =
            switch action {
            case .navigate: .seconds(10)
            case .typeText(_, _, let submit): submit ? .seconds(8) : .seconds(2)
            case .press: .seconds(2)
            default: .seconds(4)
            }
        var settled = try await settle(after: snapshot, maximum: maximum)
        try check()
        var changed = Self.changed(from: snapshot, to: settled)
        var record = draft.records.last ?? ScoutRecord(turn: turn, steps: [step], outcome: .pending, fact: "")
        var neededPointer = false
        // A click that opened another window changed nothing here, and clicking again would open another.
        let openedWindow = driver.scopeViolation(source, since: baseline) != nil
        if !changed, !openedWindow, case .click(let locator) = action,
            let id = DemoLocatorMatcher.match(locator, in: settled).nodeID
        {
            // Accessibility's press did nothing (some controls close at once while their
            // window isn't focused); try a real click before telling Claude it failed.
            update("Trying a real click on \(String(locator.displayName.prefix(40)))")
            try await driver.perform(
                .click(ElementHandle(generation: settled.generation, id: id), name: name, pointer: true), on: source,
                pace: .scout
            ) {}
            try check()
            let retried = try await settle(after: settled, maximum: maximum)
            try check()
            if Self.changed(from: settled, to: retried) {
                changed = true
                neededPointer = true
                settled = retried
                record.steps[0].usesPointer = true
            }
        }
        record.outcome = changed ? .changed : .noEffect
        if case .click(var locator) = action, locator.roleClass == .checkbox,
            let id = DemoLocatorMatcher.match(locator, in: settled).nodeID, let value = settled.node(id)?.toggleValue
        {
            locator.toggleValueAfter = value
            record.steps[0].action = .click(locator)
        }
        let urlNote =
            changed && settled.webURL != snapshot.webURL
            ? " (" + (ScreenSignatures.urlKey(settled.webURL) ?? "new page") + ")" : ""
        record.fact =
            "#\(turn) \(describe(action))\(neededPointer ? " (needed a real click)" : "") → "
            + (changed ? "screen changed\(urlNote)" : "no visible change; don’t repeat it")
        replaceLast(record)
        noteProgress(changed)

        if let violation = driver.scopeViolation(source, since: baseline) {
            // A window the action just opened can't be on the stage. Close it, leave the
            // action out of the demo and let Claude find another way.
            guard closedWindows < limits.maxClosedWindows, await driver.closeWindows(source, openedSince: baseline)
            else {
                return .stopped(.leftScope(violation))
            }
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

    static func changed(from before: AXSnapshot, to after: AXSnapshot) -> Bool {
        after.digest != before.digest || after.webURL != before.webURL
            || after.focusedID.map { after.node($0)?.label } != before.focusedID.map { before.node($0)?.label }
    }

    // MARK: Settling

    /// Waits until two consecutive snapshots agree and web content has loaded.
    private func settle(after previous: AXSnapshot, maximum: Duration) async throws -> AXSnapshot {
        let start = ContinuousClock.now
        try await Task.sleep(for: limits.settleMinimum)
        var last = try await driver.snapshot(source, waitForContent: false)
        while ContinuousClock.now - start < maximum {
            try await Task.sleep(for: limits.settlePoll)
            try check()
            let next = try await driver.snapshot(source, waitForContent: false)
            let ready = next.webContent.map(\.isReady) ?? true
            if next.digest == last.digest, ready { return next }
            last = next
        }
        return last
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

    /// A step dispatched before a pause or relaunch: keep it, and let the next
    /// observation (and verification) decide what it did.
    private func resolveUnobservedRecord() {
        guard var last = draft.records.last else { return }
        if last.outcome == .pending {
            draft.records.removeLast()
        } else if last.outcome == .unobserved {
            last.outcome = .contaminated
            last.fact = last.fact.replacingOccurrences(
                of: "result not observed yet", with: "result unknown; check the screen")
            draft.records[draft.records.count - 1] = last
        }
    }

    private func reject(_ turn: Int, _ reason: String) {
        save(ScoutRecord(turn: turn, steps: [], outcome: .rejected, fact: "#\(turn) rejected: \(reason)"))
        noteProgress(false)
    }

    private func appendFact(turn: Int, _ fact: String) {
        save(ScoutRecord(turn: turn, steps: [], outcome: .rejected, fact: "#\(turn) \(fact)"))
    }

    private func noteProgress(_ changed: Bool) {
        unchangedTurns = changed ? 0 : unchangedTurns + 1
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
    /// exact question the presenter answered; demos approved before reasons were
    /// recorded keep their approval.
    static func policy(
        for action: DemoAction, node: AXNode?, snapshot: AXSnapshot? = nil, prompt: String, startHost: String?,
        approved: Bool, approvedReason: String? = nil
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
        let decision = DemoActionPolicy.evaluate(policyAction, prompt: prompt, startHost: startHost, approved: false)
        if approved, case .needsApproval(let question) = decision, approvedReason == nil || approvedReason == question {
            return .allow
        }
        return decision
    }

    static func policyElement(_ node: AXNode, in snapshot: AXSnapshot? = nil) -> DemoPolicyElement {
        let kind = DemoDriver.policyKind(role: node.role, subrole: node.subrole) ?? .other
        // Only the control's own words count. A container's text can be its whole
        // contents (“Confirmed” in a details panel); confirmations inside dialogs are
        // covered by the dialog rule instead.
        let details = [node.help, node.identifier, node.placeholder].compactMap { $0 }
        return DemoPolicyElement(
            kind: kind, label: node.label, labelIsData: node.roleClass == .row || node.roleClass == .cell,
            isSecure: node.isSecure,
            isSearchField: node.subrole == "AXSearchField" || node.role == "AXSearchField", inDialog: node.inDialog,
            details: details)
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
        let pattern =
            #"discreet|privacy|hide balances|show balances|mask|dark mode|light mode|theme|mute|toggle|modo discreto"#
        var counts: [String: (Int, String)] = [:]
        for step in steps {
            guard case .click(let locator) = step.action, locator.labelIsStable,
                locator.roleClass == .button || locator.roleClass == .checkbox,
                locator.label.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
