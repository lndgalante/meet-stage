import SwiftUI

struct DemoBarView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject var demo: DemoSession
    @State private var showsSetup = false
    @State private var showsEditor = false
    @State private var showsScript = false
    @State private var confirmsNewDemo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .composing = demo.phase {
                composer
            } else {
                header
                chips
            }
            contextLine
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.18), value: demo.phase)
        .popover(isPresented: $showsSetup, arrowEdge: .bottom) { DemoSetupView(demo: demo) }
        .sheet(isPresented: $showsEditor) {
            if let plan = demo.demo { DemoEditorView(demo: demo, draft: plan) }
        }
        .sheet(isPresented: $showsScript) { DemoScriptView(demo: demo) }
        .confirmationDialog("Start a new demo?", isPresented: $confirmsNewDemo) {
            Button("New Demo", role: .destructive, action: demo.newDemo)
        } message: {
            Text("This removes the current demo for this app. Your request stays in the field.")
        }
        .onChange(of: demo.selectedSource) { _, _ in
            showsEditor = false
            showsScript = false
            showsSetup = false
            confirmsNewDemo = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Real-time demo controls")
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Real-time demos", systemImage: "play.rectangle")
                    .font(.callout.weight(.semibold))
                Text("Your app. A live walkthrough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("What should we show? e.g. a quick tour of Transactions", text: $demo.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
                .onSubmit(build)
                .accessibilityLabel("Demo request")
                .help("Name a page or feature, or describe the flow step by step.")
            Button("Build Demo", systemImage: "sparkles", action: build)
                .buttonStyle(.borderedProminent)
                .disabled(!demo.canBuild)
                .help(
                    demo.isLiveSourceSelected
                        ? "Claude explores the app, records a walkthrough, then plays it back to check it"
                        : "Choose a source window first")
            setupButton
        }
        .controlSize(.large)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if demo.phase.isActuating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
            }
            Text(demo.demo?.title ?? "Demo")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .help(demo.demo?.prompt ?? "")
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            statusPill
            if demo.isWritingScript {
                Label("Writing the script…", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            actions
            if demo.demo?.isCompiled == true { notesButton }
            optionsMenu
        }
    }

    private var caption: String? {
        switch demo.phase {
        case .scouting, .scoutPaused: demo.scoutedSteps > 0 ? "\(demo.scoutedSteps) steps so far" : nil
        case .running(.verify, let next, _): "Checking \(min(next + 1, stepCount)) of \(stepCount)"
        case .ready, .finished, .needsStart:
            demo.demo.map { plan in
                demo.prompter.followsVoice
                    ? "\(plan.steps.count) steps · paced by your voice"
                    : "\(plan.steps.count) steps · about \(max(5, Int(Double(plan.estimatedSeconds) / demo.playbackSpeed.rawValue))) s"
            }
        default: nil
        }
    }

    private var stepCount: Int { demo.demo?.steps.count ?? 0 }

    @ViewBuilder private var statusPill: some View {
        switch demo.phase {
        case .ready, .finished:
            pill(demo.isChecked ? "Checked" : "Not checked", color: demo.isChecked ? .green : .secondary)
        case .needsStart: pill("Not at the start", color: .orange)
        case .scoutPaused: pill("Build paused", color: .orange)
        case .paused: pill("Paused", color: .orange)
        case .offTrack: pill("Needs attention", color: .orange)
        default: EmptyView()
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private var actions: some View {
        switch demo.phase {
        case .scouting:
            Button("Stop", systemImage: "stop.fill", action: demo.pause)
        case .scoutPaused(let stop):
            scoutPausedActions(stop)
        case .returning:
            Button("Stop", systemImage: "stop.fill", action: demo.pause)
        case .needsStart(let mismatch, let then):
            switch mismatch {
            case .noAutomaticReturn, .webContentUnavailable:
                Button("Check", systemImage: "checkmark.circle", action: demo.checkStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!demo.isLiveSourceSelected)
            case .togglesDiffer:
                Button("Return to Start", systemImage: "arrow.uturn.backward", action: demo.returnToStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!demo.isLiveSourceSelected)
                Button("Check", systemImage: "checkmark.circle", action: demo.checkStart)
                    .disabled(!demo.isLiveSourceSelected)
            case .wrongScreen:
                Button("Return to Start", systemImage: "arrow.uturn.backward", action: demo.returnToStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!demo.isLiveSourceSelected)
            }
            if then == .ready || then == .play {
                Button("Play Anyway") { demo.play() }.disabled(!demo.isLiveSourceSelected)
            }
        case .ready:
            playButton("Play Demo")
            nextStepButton
        case .running(.verify, _, _):
            Button("Stop Check", systemImage: "pause.fill", action: demo.pause)
        case .running:
            Button(action: demo.pause) {
                Label("Pause Demo", systemImage: "pause.fill").frame(minWidth: 94)
            }
            .buttonStyle(.borderedProminent)
            nextStepButton.disabled(true)
        case .paused(let mode, _, _, _):
            playButton(mode == .verify ? "Continue Check" : "Continue")
            if mode == .present { nextStepButton }
            Button("Return to Start", systemImage: "arrow.uturn.backward", action: demo.returnToStart)
                .labelStyle(.iconOnly)
                .help("Return to the start")
                .disabled(!demo.isLiveSourceSelected)
        case .offTrack(let mode, _, _):
            playButton("Try Again")
            if mode == .present {
                Button("Skip Step", action: demo.skipStep).disabled(!demo.isLiveSourceSelected)
            }
            Button("Return to Start", systemImage: "arrow.uturn.backward", action: demo.returnToStart)
                .labelStyle(.iconOnly)
                .help("Return to the start")
                .disabled(!demo.isLiveSourceSelected)
        case .finished:
            Button("Return to Start", systemImage: "arrow.uturn.backward", action: demo.returnToStart)
                .buttonStyle(.borderedProminent)
                .disabled(!demo.isLiveSourceSelected)
            Button("Play Again") { demo.play() }.disabled(!demo.canPlay)
        case .composing:
            EmptyView()
        }
    }

    @ViewBuilder private func scoutPausedActions(_ stop: ScoutStop) -> some View {
        let live = demo.isLiveSourceSelected
        switch stop {
        case .needsApproval:
            Button("Allow", action: demo.allowPending).buttonStyle(.borderedProminent).disabled(!live)
            Button("Skip", action: demo.skipPending).disabled(!live)
        case .blocked(_, let alternative):
            if !alternative.isEmpty {
                Button("Show \(Self.shortened(alternative)) Instead") {
                    demo.buildAlternative("Show \(alternative)")
                }
                .buttonStyle(.borderedProminent)
                .help("Build a demo of \(alternative) instead")
                .disabled(!live)
            }
            Button("Edit Request", action: demo.editRequest)
            if demo.scoutedSteps > 0 {
                Button("Use \(demo.scoutedSteps) Steps", action: demo.useRecordedSteps).disabled(!live)
            }
        case .limit:
            if demo.scoutedSteps > 0 {
                Button("Use \(demo.scoutedSteps) Steps", action: demo.useRecordedSteps)
                    .buttonStyle(.borderedProminent)
                    .disabled(!live)
            }
            Button("Discard", role: .destructive, action: demo.discardDraft)
        default:
            Button("Keep Building", systemImage: "play.fill", action: demo.keepBuilding)
                .buttonStyle(.borderedProminent)
                .disabled(!live)
            if demo.scoutedSteps > 0 {
                Button("Use \(demo.scoutedSteps) Steps", action: demo.useRecordedSteps).disabled(!live)
            }
            Button("Discard", role: .destructive, action: demo.discardDraft)
        }
    }

    /// Up to four words, cut on a word boundary.
    static func shortened(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let head = words.prefix(4).joined(separator: " ")
        return words.count > 4 ? head + "…" : head
    }

    private func playButton(_ title: String) -> some View {
        Button {
            if !demo.hasKey && !demo.isChecked && demo.phase == .ready {
                showsSetup = true
            } else {
                demo.play()
            }
        } label: {
            Label(title, systemImage: "play.fill").frame(minWidth: 94)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!demo.isLiveSourceSelected || demo.demo?.isCompiled != true)
        .help("Pause Demo keeps the live app and the current highlight on screen")
    }

    private var nextStepButton: some View {
        Button {
            demo.play(singleStep: true)
        } label: {
            Image(systemName: "forward.end.fill")
        }
        .disabled(!demo.isLiveSourceSelected || demo.demo?.isCompiled != true || demo.phase.replayMode == .verify)
        .accessibilityLabel("Run the next step, then pause")
        .help("Run the next step, then pause")
    }

    private var optionsMenu: some View {
        Menu {
            if demo.demo?.isCompiled == true {
                Button("Edit Steps…") {
                    demo.pause()
                    showsEditor = true
                }
                .disabled(demo.isBusy)
                Button("Presenter Script…") { showsScript = true }
                Button("Check Again", action: demo.checkAgain).disabled(demo.isBusy || !demo.isLiveSourceSelected)
                Button("Return to Start", action: demo.returnToStart)
                    .disabled(demo.isBusy || !demo.isLiveSourceSelected || demo.phase == .ready)
                Divider()
                if !demo.prompter.followsVoice {
                    // With Follow my voice, the presenter sets the pace.
                    Picker("Speed", selection: $demo.playbackSpeed) {
                        ForEach(DemoPlaybackSpeed.allCases) { Text($0.label).tag($0) }
                    }
                }
                Toggle("Pause After Each Step", isOn: $demo.pausesAfterEachStep)
                Divider()
            }
            Button("Demo Setup…") { showsSetup = true }
            Button("New Demo…") { confirmsNewDemo = true }.disabled(demo.isBusy)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .accessibilityLabel("Demo options")
    }

    private var notesButton: some View {
        Button(action: demo.toggleNotes) {
            Image(systemName: demo.notesVisible ? "text.bubble.fill" : "text.bubble")
        }
        .help(demo.notesVisible ? "Hide presenter notes (⌃⌘N)" : "Show presenter notes (⌃⌘N)")
        .accessibilityLabel(demo.notesVisible ? "Hide presenter notes" : "Show presenter notes")
    }

    private var setupButton: some View {
        Button {
            showsSetup = true
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .accessibilityLabel("Demo Setup")
        .help("AI access, API key and playback settings")
    }

    // MARK: Chips

    private var chipSteps: [DemoStep] {
        guard let plan = demo.demo else { return [] }
        if let draft = plan.draft { return ScoutCompaction.compact(draft.records) }
        return plan.steps
    }

    private var chips: some View {
        let steps = chipSteps
        let ghosts = demo.phase == .scouting || isScoutPaused ? remainingOutline(after: steps.count) : []
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        chip(index: index, step: step).id(index)
                    }
                    ForEach(Array(ghosts.enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            .accessibilityLabel("Planned: \(title)")
                    }
                    if demo.phase == .scouting {
                        ProgressView().controlSize(.small).padding(.horizontal, 8).id("building")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: 34)
            .onChange(of: demo.phase.currentStep) { _, step in
                if let step { withAnimation { proxy.scrollTo(step, anchor: .center) } }
            }
            .onChange(of: steps.count) { _, count in
                if demo.phase == .scouting, count > 0 { withAnimation { proxy.scrollTo(count - 1, anchor: .trailing) } }
            }
        }
    }

    private var isScoutPaused: Bool {
        if case .scoutPaused = demo.phase { true } else { false }
    }

    private func remainingOutline(after count: Int) -> [String] {
        demo.outlineProgress.filter { !$0.done }.map(\.title)
    }

    private func chip(index: Int, step: DemoStep) -> some View {
        let isCurrent = demo.phase.currentStep == index
        let isDone = index < demo.phase.nextStep && demo.phase.replayMode != nil
        return HStack(spacing: 7) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: step.action.symbol)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            Text(step.title)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            isCurrent ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(alignment: .bottom) {
            if isDone {
                RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(height: 2)
            }
        }
        .help(step.script.isEmpty ? step.action.kindLabel : "\(step.action.kindLabel)\n\(step.script)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1): \(step.title), \(step.action.kindLabel)")
        .accessibilityValue(isCurrent ? "Current" : isDone ? "Done" : "Upcoming")
    }

    // MARK: Context line

    private var isPresentingLine: Bool {
        switch demo.phase {
        case .running(.present, _, _), .paused(.present, _, _, .user), .finished:
            demo.notice == nil && demo.prompter.line != nil
        default: false
        }
    }

    @ViewBuilder private var contextLine: some View {
        if demo.needsActuationConsent, case .composing = demo.phase {
            consentRow
        } else if isPresentingLine {
            PresentingLineView(prompter: demo.prompter)
        } else if let text = contextText {
            HStack(alignment: .top, spacing: 12) {
                Text(text.text)
                    .font(text.isWarning ? .callout : .caption)
                    .foregroundStyle(text.isWarning ? .orange : .secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if case .offTrack(.present, _, .wrongScreen(let step)) = demo.phase {
                    Button("Continue from Step \(step + 1)", action: demo.continueFromScreen)
                        .disabled(!demo.isLiveSourceSelected)
                }
                if demo.recheckSuggested, demo.phase == .ready {
                    Button("Check Again", action: demo.checkAgain).disabled(!demo.isLiveSourceSelected)
                }
                if let details = demo.diagnosticDetails {
                    Button("Copy Details", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(details, forType: .string)
                    }
                    .help("Copy the API error, model and request ID")
                }
            }
        }
    }

    private var consentRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised").foregroundStyle(.secondary)
            Text(
                "BetterMeets will operate \(demo.selectedSource?.name ?? "this app") in the background for a minute or two. Watch it on the stage here; clicking or typing inside \(demo.selectedSource?.name ?? "the app") pauses the build. If you’re sharing BetterMeets, viewers will see it."
            )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Not Now", action: demo.cancelActuationConsent)
            Button("Build", action: demo.confirmActuation).buttonStyle(.borderedProminent)
        }
    }

    private var contextText: (text: String, isWarning: Bool)? {
        if let notice = demo.notice {
            switch demo.phase {
            case .needsStart, .offTrack, .paused, .scoutPaused, .running: break
            default: return (notice, true)
            }
        }
        switch demo.phase {
        case .composing:
            return nil
        case .scouting:
            return (demo.activity.isEmpty ? "Working…" : demo.activity + "…", false)
        case .scoutPaused(let stop):
            return (scoutStopText(stop), true)
        case .returning(let then):
            return (then == .play ? "Going back to the start, then playing…" : "Going back to the start…", false)
        case .needsStart(let mismatch, let then):
            if !demo.activity.isEmpty { return (demo.activity + "…", false) }
            let start = demo.demo?.start?.description ?? ""
            if then == .play, mismatch == .wrongScreen || mismatch == .noAutomaticReturn {
                return (
                    "Go to: \(start.isEmpty ? "the screen where the build started" : start). The demo starts once you’re there.",
                    true
                )
            }
            switch mismatch {
            case .togglesDiffer(let names):
                return ("Turn \(names.joined(separator: ", ")) back to how the demo starts, then press Check.", true)
            case .webContentUnavailable:
                return (DemoError.webContentUnavailable(demo.demo?.app.engine ?? .chromium).localizedDescription, true)
            case .noAutomaticReturn:
                let prefix = demo.notice.map { $0 + " " } ?? ""
                return (prefix + "Return to: \(start.isEmpty ? "the screen where the build started" : start), then press Check.", true)
            case .wrongScreen:
                return ("Not on the starting view: \(start.isEmpty ? "the screen where the build started" : start).", true)
            }
        case .ready:
            if demo.recheckSuggested { return ("A step moved during the last run.", false) }
            return (demo.demo?.start.map { "Starts on: \($0.description.isEmpty ? "the screen where it was built" : $0.description)" }
                ?? "", false)
        case .running(.verify, _, _):
            return (demo.activity.isEmpty ? "Playing it back to check it…" : demo.activity + "…", false)
        case .running(_, _, let current), .paused(.present, _, let current, .user):
            guard let current, let step = demo.demo?.steps[safe: current] else { return nil }
            return step.script.isEmpty ? nil : (step.script, false)
        case .paused(_, _, _, let reason):
            return reason.message.map { ($0, true) } ?? ("Check paused.", false)
        case .offTrack(_, _, let mismatch):
            return (mismatch.message, true)
        case .finished:
            return (demo.demo?.closingScript.isEmpty == false ? demo.demo!.closingScript : "Demo complete.", false)
        }
    }

    private func scoutStopText(_ stop: ScoutStop) -> String {
        switch stop {
        case .user: "Build paused."
        case .userInput: "Paused because you clicked or typed in the app."
        case .focusLost: "Paused because the app lost focus."
        case .relaunched: "This build was interrupted. Keep building from the current screen, or use the steps so far."
        case .leftScope(let reason): reason + " Close it and return to the app to keep building."
        case .needsApproval(let pending): pending.message
        case .blocked(let reason, _): reason
        case .limit(let limit): limit.message
        case .error(let error): error.localizedDescription
        }
    }

    private func build() {
        guard demo.canBuild else { return }
        if !demo.hasKey || !demo.allowsAI { showsSetup = true } else { demo.build() }
    }
}

/// The current script line in the strip, large enough to read at a glance.
private struct PresentingLineView: View {
    @ObservedObject var prompter: PresenterPrompter
    @ObservedObject var listener: SpeechListener

    init(prompter: PresenterPrompter) {
        self.prompter = prompter
        listener = prompter.listener
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if prompter.follower.isEmpty {
                    Text(prompter.isFollowingVoice ? "Say “next” to continue" : "No line for this step")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ScriptLineText(
                        follower: prompter.follower, size: 17,
                        marksNextWord: prompter.followsVoice && listener.isListening
                    )
                    .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if prompter.isWaitingForVoice {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                    .help("Waiting for you to finish this line")
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
