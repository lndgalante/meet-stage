import AppKit
import SwiftUI
import Testing

@testable import MeetStage

/// Renders the demo panel's states to PNGs for design review, at real panel widths
/// in Dark and Light. Runs only with SNAPSHOT_DIR set; SNAPSHOT_WIDTHS (comma
/// separated, window width − 100) picks the widths.
@Suite("View snapshots")
@MainActor
struct ZZViewSnapshots {
    private struct Keys: DemoKeyStore {
        var key: String? { "k" }
        var hasKey: Bool { true }
        func save(_ value: String) -> Bool { true }
    }

    /// No key yet, and Keychain refuses to save one.
    private struct NoKeys: DemoKeyStore {
        var key: String? { nil }
        var hasKey: Bool { false }
        func save(_ value: String) -> Bool { false }
    }

    private static let titles = [
        "Open a new task", "Write the prompt", "Review the prompt", "Pick the schedule", "The Create button",
        "Create the task", "See the next run", "Check the schedule", "Open the summary", "Share the summary",
        "Mute the reminder", "Edit the schedule", "Pause the task", "Delete the draft"
    ]

    private var widths: [CGFloat] {
        let environment = ProcessInfo.processInfo.environment
        let list = environment["SNAPSHOT_WIDTHS"] ?? environment["SNAPSHOT_WIDTH"] ?? "700,720,1080,1600"
        return list.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .map { CGFloat($0) }
    }

    /// Draws `view` at every width in Dark and Light, and logs each panel's height.
    private func render<V: View>(_ view: @autoclosure () -> V, name: String, widths: [CGFloat]? = nil) throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        for width in widths ?? self.widths {
            for dark in [true, false] {
                let folder = URL(fileURLWithPath: dir).appendingPathComponent("\(Int(width))")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let host = NSHostingView(
                    rootView: view().padding(12).frame(width: width).fixedSize(horizontal: false, vertical: true)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: width, height: 240), styleMask: [.borderless],
                    backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                for _ in 0..<2 {
                    host.frame = CGRect(origin: .zero, size: host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                }
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try #require(rep.representation(using: .png, properties: [:]))
                let file = "\(name)-\(dark ? "dark" : "light")"
                try data.write(to: folder.appendingPathComponent(file + ".png"))
                if dark {
                    let log = URL(fileURLWithPath: dir).appendingPathComponent("heights.txt")
                    let line = "\(Int(width)) \(name) panel=\(Int(host.bounds.height - 24))\n"
                    if let handle = try? FileHandle(forWritingTo: log) {
                        handle.seekToEndOfFile()
                        handle.write(Data(line.utf8))
                        try handle.close()
                    } else {
                        try Data(line.utf8).write(to: log)
                    }
                }
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func defaults(consent: Bool = true) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "snapshots-\(UUID().uuidString)"))
        defaults.set(consent, forKey: DemoSession.consentKey)
        defaults.set(consent, forKey: "demo.consentAnswered")
        return defaults
    }

    private func session(
        _ app: FakeApp, _ defaults: UserDefaults, model: ScriptedModel = ScriptedModel([]),
        keys: any DemoKeyStore = Keys()
    ) -> DemoSession {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let session = DemoSession(
            driver: app, defaults: defaults, model: model, keyStore: keys, observesUserInput: false,
            scoutLimits: limits, opensWindows: false)
        session.replayTuning = (0.001, .milliseconds(300))
        return session
    }

    /// `base` with the given steps, lines and test result.
    private func demo(_ base: RealTimeDemo, title: String, steps count: Int, tested: Bool) -> RealTimeDemo {
        var demo = base
        demo.id = UUID()
        demo.title = title
        demo.steps = (0..<count).map { index in
            var step = base.steps[index % base.steps.count]
            step.id = UUID()
            step.title = Self.titles[index % Self.titles.count]
            step.script =
                "Now we choose when it runs: every weekday at nine, so the summary is waiting before your first meeting."
            step.holdSeconds = 8
            return step
        }
        demo.start?.label = "the Scheduled page"
        demo.openingScript = "Let's schedule a summary that's ready before the day starts."
        demo.closingScript = "And that's it: the summary arrives every weekday at nine."
        demo.status =
            tested
            ? .checked(
                DemoVerification(
                    checkedAt: Date(),
                    fingerprint: DemoFingerprint.make(demo, appVersion: "1.0", sizeClass: .regular, window: "12x8")))
            : .recorded
        return demo
    }

    /// A build in progress with `recorded` steps so far and two beats still planned.
    private func draft(_ base: RealTimeDemo, id: UUID, title: String, recorded: Int) -> RealTimeDemo {
        var demo = self.demo(base, title: title, steps: recorded, tested: false)
        demo.id = id
        let records = demo.steps.enumerated().map { index, step in
            var step = step
            step.action = base.steps[index % 2].action
            return ScoutRecord(turn: index, steps: [step], scroll: nil, outcome: .changed, fact: "")
        }
        demo.steps = []
        demo.outline = ["Open the summary", "See the next run"]
        demo.status = .draft(ScoutDraft(records: records, outline: demo.outline, turn: recorded))
        return demo
    }

    /// A 14-inch MacBook Pro: a 185-point notch and a 33-point menu bar.
    private static let builtIn = IslandScreen(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 94, width: 1728, height: 990), safeTop: 32, auxLeftWidth: 771,
        auxRightWidth: 772)

    /// An external display without a notch and a 25-point menu bar.
    private static let external = IslandScreen(
        frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1055), safeTop: 0, auxLeftWidth: nil,
        auxRightWidth: nil)

    private static func islandLayout(_ screen: IslandScreen = builtIn, size: Double = 26) -> IslandLayout {
        IslandLayout.make(
            screen: screen, fontSize: size, rowHeight: IslandType.rowHeight(IslandType.font(size: size, bold: false)))
    }

    /// A voice rising and falling, for the meter.
    private static let speech: [Float] = (0..<40).map { index in
        let syllable = abs(sin(Double(index) * 0.9))
        return Float(index % 9 == 0 ? 0.1 : 0.2 + 0.6 * syllable)
    }

    /// The teleprompter island in each state it looks different in, docked under a menu bar.
    private func renderIsland(_ main: DemoSession, _ open: RealTimeDemo) throws {
        let prompter = main.prompter
        let listener = prompter.listener
        let opening = open.openingScript ?? ""
        func island(_ name: String, _ mode: IslandMode = .expanded, layout: IslandLayout = Self.islandLayout()) throws {
            try render(
                IslandSnapshot(demo: main, chrome: IslandChrome(resting: mode, in: layout), layout: layout),
                name: name, widths: [layout.width + 164])
        }

        main.showForTesting(open, in: .ready)
        prompter.show(.opening, text: opening, heading: "Opening", upNext: open.steps.first?.title, position: nil)
        try island("18a-island-ready")

        main.showForTesting(open, in: .running(.present, next: 3, current: 3))
        listener.simulateListening(levels: Self.speech)
        listener.simulateHearing("now we choose when", isFinal: true)
        try island("18b-island-listening")

        main.followsVoice = false
        main.showForTesting(open, in: .running(.present, next: 3, current: 3))
        prompter.simulateHold(seconds: 8, elapsed: 3)
        try island("18c-island-timed")
        main.followsVoice = true

        main.showForTesting(open, in: .running(.present, next: 4, current: 4))
        prompter.show(
            .step(4), text: "", heading: open.steps[4].title, upNext: open.steps[5].title, position: (5, 9))
        listener.simulateListening(levels: Self.speech)
        try island("18d-island-no-line")

        main.showForTesting(open, in: .paused(.present, next: 4, current: 3, reason: .userInput))
        listener.simulateHearing("now we choose when it runs every", isFinal: true)
        try island("18e-island-paused")

        main.showForTesting(open, in: .offTrack(.present, index: 5, .wrongScreen(onStep: 7)))
        try island("18f-island-off-track")

        main.showForTesting(open, in: .returning(then: .play))
        prompter.show(.opening, text: opening, heading: "Opening", upNext: open.steps.first?.title, position: nil)
        try island("18g-island-going-back")

        main.showForTesting(open, in: .finished)
        prompter.show(.closing, text: open.closingScript, heading: "Wrap up", upNext: nil, position: nil)
        try island("18h-island-finished")

        main.showForTesting(open, in: .running(.present, next: 3, current: 3))
        listener.simulateState(.unavailable("No microphone is available."))
        prompter.simulateHold(seconds: 8, elapsed: 2)
        try island("18i-island-mic-unavailable")

        main.showForTesting(open, in: .running(.verify, next: 2, current: 2))
        try island("18j-island-compact", .compact)

        main.showForTesting(open, in: .offTrack(.verify, index: 2, .wrongScreen(onStep: 3)))
        try island("18j2-island-compact-stopped", .compact)

        main.showForTesting(open, in: .needsStart(.togglesDiffer(["Dark mode"]), then: .play))
        prompter.show(.opening, text: opening, heading: "Opening", upNext: open.steps.first?.title, position: nil)
        try island("18j3-island-needs-start")

        main.showForTesting(open, in: .running(.present, next: 3, current: 3))
        listener.simulateListening(levels: Self.speech)
        listener.simulateHearing("now we choose when it runs", isFinal: true)
        try island("18k-island-no-notch", layout: Self.islandLayout(Self.external))

        try island("18l-island-large-text", layout: Self.islandLayout(size: 40))
        try island("18m-island-small-text", layout: Self.islandLayout(size: 16))

        listener.stop()
        prompter.clear()
    }

    /// The demo notice from the notch, without one, and under the expanded and compact teleprompter.
    private func renderNotice(_ main: DemoSession, _ open: RealTimeDemo) throws {
        // Safari, whose icon every Mac has.
        var cannes = open
        cannes.title = "El Gran Premio de Cannes"
        cannes.steps = Array(open.steps.prefix(4))
        cannes.app = DemoAppKey(bundleID: "com.apple.Safari", appName: "Safari", engine: .webkit, isBrowser: true)
        func notice(
            _ name: String, _ phase: DemoPhase, screen: IslandScreen = Self.builtIn, island: IslandMode? = nil
        ) throws {
            let content = try #require(DemoNoticeContent.make(phase: phase, demo: cannes, isChecked: true))
            let islandLayout = Self.islandLayout(screen)
            let islandChrome = island.map { IslandChrome(resting: $0, in: islandLayout) }
            let docked = islandChrome.map { DockedIsland($0.shape, in: islandLayout) }
            let layout = DemoNoticeLayout.make(screen: screen, island: docked)
            let chrome = DemoNoticeChrome(resting: content, in: layout)
            try render(
                NoticeSnapshot(
                    chrome: chrome, layout: layout,
                    island: islandChrome.map { (main, $0, islandLayout) }),
                name: name, widths: [max(layout.width, docked?.frame.width ?? 0) + 164])
        }

        try notice("20a-notice-ready", .ready)
        try notice("20b-notice-test-stopped", .offTrack(.verify, index: 2, .wrongScreen(onStep: 3)))
        let approval = PendingApproval(
            action: open.steps[1].action, title: "Create the task", script: "",
            message: "Click “Create” in this dialog?", rect: nil)
        try notice("20c-notice-build-paused", .scoutPaused(.needsApproval(approval)))
        try notice("20d-notice-ready-no-notch", .ready, screen: Self.external)
        cannes.start?.description =
            "The Paisanos home page, scrolled to the top, with the Cannes case study card showing"
        try notice("20f-notice-test-waiting", .needsStart(.wrongScreen, then: .verify))

        main.showForTesting(open, in: .ready)
        main.prompter.show(
            .opening, text: open.openingScript ?? "", heading: "Opening", upNext: open.steps.first?.title,
            position: nil)
        try notice("20e-notice-under-island", .ready, island: .expanded)
        main.prompter.clear()

        let stopped = DemoPhase.offTrack(.verify, index: 2, .wrongScreen(onStep: 3))
        main.showForTesting(open, in: stopped)
        try notice("20g-notice-under-compact-island", stopped, island: .compact)
        try notice("20h-notice-under-compact-island-no-notch", stopped, screen: Self.external, island: .compact)
    }

    @Test func surfaces() async throws {
        guard ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil else { return }
        let app = subtisApp()
        let manager = CaptureManager(defaults: try defaults())

        // First run: no saved demos, ideas from Claude.
        let first = session(
            app, try defaults(),
            model: ScriptedModel([
                reply(
                    .typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
                reply(.click(elementID: 2, title: "Open the first result", script: "")),
                reply(
                    .present([
                        ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "Grab it here.")
                    ])),
                reply(
                    .finish(
                        title: "Find The Matrix", startDescription: "Subtis home, with the search field empty",
                        startLabel: "", closingScript: ""))
            ]))
        try await waitUntil { first.ideas.count == 3 }
        try render(DemoBarView(manager: manager, demo: first), name: "01-composing-first")
        first.prompt = "Search for The Matrix and open the result"
        first.build()
        try await waitUntil { first.phase == .ready && !first.isWritingScript }
        let built = try #require(first.demo)

        // A library of four, with the 9-step demo open.
        let mainDefaults = try defaults()
        let open = demo(built, title: "Create a scheduled task", steps: 9, tested: true)
        var library = DemoLibrary(defaults: mainDefaults)
        library.save(open)
        library.save(demo(built, title: "Morning digest", steps: 4, tested: false))
        library.save(demo(built, title: "Share a chat link", steps: 5, tested: true))
        library.save(demo(built, title: "Summarize a PDF and send it to the team", steps: 6, tested: false))
        library.select(open.id, for: app.demoSource)
        let main = session(app, mainDefaults)
        let bar = { DemoBarView(manager: manager, demo: main) }

        let draftID = UUID()
        main.showForTesting(
            draft(built, id: draftID, title: "Schedule a daily briefing", recorded: 4), in: .scouting,
            activity: "Opening the schedule picker")
        try render(bar(), name: "02-building")
        let approval = PendingApproval(
            action: built.steps[1].action, title: "Create the task", script: "",
            message: "Click “Create” in this dialog?", rect: nil)
        main.showForTesting(
            draft(built, id: draftID, title: "Schedule a daily briefing", recorded: 3),
            in: .scoutPaused(.needsApproval(approval)))
        try render(bar(), name: "03-approval")
        main.showForTesting(
            draft(built, id: draftID, title: "Export the report", recorded: 2),
            in: .scoutPaused(
                .blocked(reason: "Exporting needs a paid plan in this app.", alternative: "the export settings")))
        try render(bar(), name: "04-blocked")
        main.deleteDemo(draftID)

        main.showForTesting(open, in: .ready)
        try render(bar(), name: "05-ready-tested")
        var untested = open
        untested.status = .recorded
        main.showForTesting(untested, in: .ready)
        try render(bar(), name: "06-ready-not-tested")
        let long = demo(built, title: "Every step of the weekly report", steps: 14, tested: true)
        main.showForTesting(long, in: .ready)
        try render(bar(), name: "07-ready-overflow")
        main.showForTesting(long, in: .running(.present, next: 11, current: 11), teleprompterVisible: true)
        try render(bar(), name: "07b-presenting-overflow")
        main.deleteDemo(long.id)

        main.showForTesting(open, in: .running(.present, next: 3, current: 3), teleprompterVisible: true)
        try render(bar(), name: "08-presenting")
        main.showForTesting(open, in: .running(.present, next: 3, current: 3))
        try render(bar(), name: "09-presenting-line")
        main.showForTesting(
            open, in: .paused(.present, next: 4, current: 3, reason: .userInput), teleprompterVisible: true)
        try render(bar(), name: "10-paused")
        main.showForTesting(
            open, in: .offTrack(.present, index: 5, .wrongScreen(onStep: 7)), teleprompterVisible: true)
        try render(bar(), name: "11-off-track")
        main.showForTesting(open, in: .needsStart(.togglesDiffer(["Dark mode"]), then: .play))
        try render(bar(), name: "12-needs-start")
        main.showForTesting(open, in: .running(.verify, next: 2, current: 2))
        try render(bar(), name: "13-testing")
        main.showForTesting(open, in: .finished)
        try render(bar(), name: "14-finished")

        try renderIsland(main, open)
        try renderNotice(main, open)

        main.newDemo()
        try await waitUntil { main.ideas.count == 3 }
        try render(bar(), name: "15-composing-new")

        // The first launch asks about Claude access.
        let consent = session(app, try defaults(consent: false))
        try render(DemoBarView(manager: manager, demo: consent), name: "16-composing-consent")

        // Build without a key, and Keychain refuses it.
        let keyless = session(app, try defaults(), keys: NoKeys())
        keyless.prompt = "Schedule a daily summary"
        keyless.build()
        keyless.saveKey("sk-test")
        try render(DemoBarView(manager: manager, demo: keyless), name: "17-composing-key")

        if let plan = main.savedDemos.first {
            try render(DemoEditorView(demo: main, plan: plan).frame(height: 740), name: "19-editor", widths: [724])
        }
    }
}

/// A display's top edge: a menu bar strip with the camera notch drawn over
/// `content` when the display has one, so the merge with the notch shows;
/// without a notch, `content` hangs below the menu bar.
private struct MenuBarSnapshot<Content: View>: View {
    let notch: CGRect?
    let height: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let menuBar = notch == nil ? 25.0 : 33.0
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("Safari").fontWeight(.bold)
                    Text("File")
                    Text("Edit")
                    Text("View")
                    Text("History")
                    Text("Bookmarks")
                    Text("Window")
                    Spacer(minLength: 0)
                    Text("Thu 9:41")
                }
                .font(.system(size: 13))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: menuBar)
                .background(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
                Color(white: colorScheme == .dark ? 0.24 : 0.82)
            }
            content
                .padding(.top, notch == nil ? menuBar : 0)
            if let notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                    .fill(.black)
                    .overlay(alignment: .center) {
                        Circle().fill(Color(white: 0.12)).frame(width: 8, height: 8)
                    }
                    .frame(width: notch.width, height: notch.height)
            }
        }
        .frame(height: menuBar + height + 28)
        .clipped()
    }
}

/// The island as it docks on a display.
private struct IslandSnapshot: View {
    let demo: DemoSession
    let chrome: IslandChrome
    let layout: IslandLayout

    var body: some View {
        MenuBarSnapshot(notch: layout.notch, height: layout.height) {
            TeleprompterIslandView(demo: demo, chrome: chrome)
                .frame(width: layout.width, height: layout.height)
        }
    }
}

/// The demo notice as it docks: from the notch, below the menu bar, or as a
/// card under the teleprompter.
private struct NoticeSnapshot: View {
    let chrome: DemoNoticeChrome
    let layout: DemoNoticeLayout
    let island: (demo: DemoSession, chrome: IslandChrome, layout: IslandLayout)?

    var body: some View {
        // The notice's window, headroom and all, hangs from the teleprompter's bottom edge.
        let frame = layout.frame(for: chrome.shape.size)
        let islandSize = island?.chrome.shape.size ?? .zero
        MenuBarSnapshot(notch: island?.layout.notch ?? layout.notch, height: islandSize.height + frame.height) {
            ZStack(alignment: .top) {
                if let island {
                    TeleprompterIslandView(demo: island.demo, chrome: island.chrome)
                        .frame(width: islandSize.width, height: islandSize.height)
                }
                DemoNoticeView(chrome: chrome, open: {}, dismiss: {})
                    .frame(width: frame.width, height: frame.height)
                    .padding(.top, islandSize.height)
            }
        }
    }
}
