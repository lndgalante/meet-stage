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
        /// Test hooks: a fixed hold and gate timeout instead of the paced ones.
        var holdOverride: Double?
        var gateTimeout: Duration?
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
    private var livePre: [UUID: ScreenSignature] = [:]
    private var liveStart: ScreenSignature?
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
    func returnToStart() async throws -> StartMismatch? {
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
            while snapshot.dialogOpen, !start.signature.dialogOpen, escapes < 2 {
                escapes += 1
                if let close = closeButton(in: snapshot) {
                    try await press(close, in: snapshot, name: "Close")
                } else {
                    try await driver.perform(.press(.escape), on: source, pace: .scout) {}
                }
                try await Task.sleep(for: .milliseconds(400))
                try check()
                snapshot = try await driver.snapshot(source, waitForContent: true)
            }
            if let anchor = start.returnAnchor, let id = DemoLocatorMatcher.match(anchor, in: snapshot).nodeID,
                let node = snapshot.node(id),
                DemoScout.policy(
                    for: .click(anchor), node: node, snapshot: snapshot, prompt: "", startHost: nil, approved: false)
                    == .allow
            {
                try await press(id, in: snapshot, name: anchor.displayName)
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

    private func press(_ id: Int, in snapshot: AXSnapshot, name: String) async throws {
        try await driver.perform(
            .click(ElementHandle(generation: snapshot.generation, id: id), name: name), on: source, pace: .scout
        ) {}
    }

    // MARK: Steps

    func run(from index: Int) async throws -> ReplayEnd {
        var index = index
        if options.mode == .verify, index == 0 {
            // The start screen as the check found it, to confirm the start signature.
            liveStart = ScreenSignatures.make(try await driver.snapshot(source, waitForContent: true))
        }
        if options.mode == .present, index == 0, let opening = hooks.opening {
            try await opening()
            try check()
        }
        while index < demo.steps.count {
            try check()
            let step = demo.steps[index]
            hooks.onStep(index, step.title)
            let previous = index > 0 ? demo.steps[index - 1].action : nil
            let gate = try await self.gate(index, after: previous)
            try check()

            switch gate {
            case .failure(let mismatch):
                if case .present = step.action, options.mode == .present {
                    // Never stop a live demo for a highlight: skip it and keep the previous view.
                    skippedBeats.append(step.title)
                    hooks.onCommit(index + 1)
                    index += 1
                    continue
                }
                return .offTrack(index: index, mismatch)
            case .resolved(let snapshot, let ids):
                if options.mode == .verify { livePre[step.id] = ScreenSignatures.make(snapshot) }
                if let end = try await perform(index, snapshot: snapshot, ids: ids) { return end }
                if options.mode == .verify { passedSteps.insert(step.id) }
            }

            if options.singleStep || options.pausesAfterEachStep, index + 1 < demo.steps.count {
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

    /// Waits for the step's screen to settle and for every target to be present
    /// and unique, revealing off-screen targets and healing renamed ones.
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

        while true {
            let snapshot = try await driver.snapshot(source, waitForContent: false)
            try check()
            lastSnapshot = snapshot
            let settled = !needsSettle || snapshot.digest == lastDigest
            lastDigest = snapshot.digest
            let live = ScreenSignatures.make(snapshot)
            // Headings can be below the fold, so they only identify the screen in diagnostics.
            let onScreen = ScreenSignatures.matches(step.pre, live: live, includeHeadings: false)
            if onScreen, settled, snapshot.webContent.map(\.isReady) ?? true {
                let ids = locators.map { DemoLocatorMatcher.match($0, in: snapshot).nodeID }
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
            if ContinuousClock.now - started >= timeout { break }
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
            heals[step.id] = healed.locators
            return .resolved(healed.snapshot, healed.ids)
        }
        return .failure(.targetNotFound(locators.first(where: {
            DemoLocatorMatcher.match($0, in: snapshot).nodeID == nil
        })?.displayName ?? step.title))
    }

    /// Scrolls a resolved but off-screen target into view: first by asking the
    /// element itself (works in the background), then with the scroll wheel.
    private func reveal(nodeID: Int, in snapshot: AXSnapshot, hint: RevealHint?) async throws {
        guard let node = snapshot.node(nodeID), let locator = DemoLocatorFactory.locator(for: nodeID, in: snapshot)
        else { return }
        do {
            try await driver.perform(
                .scrollToVisible(ElementHandle(generation: snapshot.generation, id: nodeID)), on: source, pace: .scout
            ) {}
        } catch DemoError.targetNotFound {
            return
        }
        try await Task.sleep(for: .milliseconds(250))
        try check()
        var latest = try await driver.snapshot(source, waitForContent: false)
        if let id = DemoLocatorMatcher.match(locator, in: latest).nodeID, latest.node(id)?.isVisible == true { return }

        let down = hint?.directionDown ?? (node.rect.midY > 0.5)
        let container = hint.flatMap { containerRect(for: $0, in: latest) } ?? latest.containerNode(of: node)?.rect
        for _ in 0..<8 {
            do {
                try await driver.perform(.wheel(around: container, down: down, increments: 1), on: source, pace: .scout) {}
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
    /// scrolled into view, falling back to the scroll wheel.
    private func scroll(hint: RevealHint, in snapshot: AXSnapshot) async throws {
        let container = hint.container.flatMap { key in
            snapshot.nodes.first { $0.isContainer && AXSnapshot.key(for: $0) == key }
        }
        let input: DemoInput =
            DemoScout.scrollTarget(in: snapshot, container: container, down: hint.directionDown)
            .map { .scrollToVisible(ElementHandle(generation: snapshot.generation, id: $0)) }
            ?? .wheel(around: container?.rect, down: hint.directionDown, increments: 4)
        do {
            try await driver.perform(input, on: source, pace: .scout) {}
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
        let nodes = ids.compactMap { snapshot.node($0) }
        let pace: DemoPace = options.mode == .present ? .present : .verify
        let hooks = hooks
        let commit: @MainActor () throws -> Void = {
            try hooks.check()
            hooks.onCommit(index + 1)
        }

        let action: DemoAction =
            switch step.action {
            case .click: .click(locators[0])
            case .typeText(_, let text, let submit): .typeText(field: locators[0], text: text, submit: submit)
            case .present(let beat): .present(DemoBeat(effect: beat.effect, targets: locators))
            default: step.action
            }
        switch DemoScout.policy(
            for: action, node: nodes.first, snapshot: snapshot, prompt: demo.prompt, startHost: demo.start?.url?.host,
            approved: step.approved, approvedReason: step.approvedReason)
        {
        case .allow: break
        case .deny(let reason), .needsApproval(let reason):
            return .offTrack(index: index, .blocked(.policyDenied(reason)))
        }

        do {
            switch action {
            case .present(let beat):
                let rect = nodes.dropFirst().reduce(nodes[0].rect) { $0.union($1.rect) }
                driver.show(DemoCue(effect: beat.effect, rect: rect))
                try await hold(index)
                try commit()
                return nil

            case .click(let locator):
                driver.show(nil)
                if let expected = locator.toggleValueAfter, nodes.first?.toggleValue == expected {
                    // Already in the state this click produced; clicking again would undo it.
                    try commit()
                } else {
                    try await driver.perform(
                        .click(
                            ElementHandle(generation: snapshot.generation, id: ids[0]), name: locator.displayName,
                            pointer: step.usesPointer == true),
                        on: source, pace: pace, commit: commit)
                }

            case .typeText(let field, let text, let submit):
                driver.show(nil)
                try await driver.perform(
                    .type(
                        ElementHandle(generation: snapshot.generation, id: ids[0]), name: field.displayName, text: text,
                        submit: submit), on: source, pace: pace, commit: commit)

            case .press(let key):
                try await driver.perform(.press(key), on: source, pace: pace, commit: commit)

            case .navigate(let url):
                driver.show(nil)
                try await driver.perform(.navigate(url), on: source, pace: pace, commit: commit)
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

    private func hold(_ index: Int) async throws {
        let step = demo.steps[index]
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
        let seconds = speaking > 0 ? max(step.holdSeconds / max(options.speed, 0.5), speaking + 0.4)
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
        let screenshot = try await driver.screenshot(source)
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
        hooks.onStep(index, "Looking for \(locators.first?.displayName ?? step.title)")
        let result = try await model.relocate(
            RelocateRequest(stepTitle: step.title, description: description, screenshot: screenshot, elements: encoded.text),
            key: key)
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
            healed.append(locator)
            freshIDs.append(id)
        }
        AppLog.demoMode.info("Healed step \(index + 1) target")
        return (healed, fresh, freshIDs)
    }

    // MARK: Verification

    /// Keeps only screen evidence that held in both scouting and checking,
    /// and folds healed targets into the steps.
    private func confirmVerification() {
        for index in demo.steps.indices {
            let id = demo.steps[index].id
            if let live = livePre[id] {
                demo.steps[index].pre = ScreenSignatures.confirm(demo.steps[index].pre, with: live)
            }
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
