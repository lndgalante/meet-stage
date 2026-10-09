import SwiftUI

struct DemoCommands: Commands {
    @ObservedObject var demo: DemoSession
    @ObservedObject private var windowState = BetterMeetsWindowState.shared

    var body: some Commands {
        CommandMenu("Demo") {
            item(PanelActionID.menuPrimary(in: demo.phase))
                .keyboardShortcut(.return, modifiers: [.command, .control])
                .disabled(!demo.phase.isActuating && !canPlayOrContinue)
            item(isPlaying ? .nextLine : .nextStep)
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(!isPlaying && (!canReplay || demo.phase.replayMode == .verify))
            item(.previousStep)
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                .disabled(!canRewind)
            item(.startOver)
                .disabled(!canRewind)
            item(.goToStart)
                .disabled(!canReplay)
            item(.testAgain)
                .disabled(!canReplay)
            Divider()
            item(.newDemo)
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(demo.isBusy || demo.selectedSource == nil || demo.phase == .composing)
            Menu("Open Demo") {
                ForEach(demo.savedDemos) { saved in
                    Toggle(
                        saved.title,
                        isOn: Binding(get: { saved.id == demo.demo?.id }, set: { if $0 { demo.openDemo(saved.id) } }))
                }
            }
            .disabled(demo.isBusy || demo.savedDemos.isEmpty)
            // These open the panel's sheet, field or dialog, so they need the panel on screen.
            item(.editDemo)
                .disabled(!canEdit)
            item(.renameDemo)
                .disabled(!canEdit)
            item(.deleteDemo)
                .disabled(demo.isBusy || demo.demo == nil || windowState.stageOnly)
            Divider()
            Button(
                demo.teleprompterVisible ? "Hide Teleprompter" : "Show Teleprompter", action: demo.toggleTeleprompter
            )
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(demo.demo?.isCompiled != true && !demo.teleprompterVisible)
            Toggle("Follow My Voice", isOn: $demo.followsVoice)
            Toggle("Pause After Each Step", isOn: $demo.pausesAfterEachStep)
            if !demo.followsVoice {
                Picker("Playback Speed", selection: $demo.playbackSpeed) {
                    ForEach(DemoPlaybackSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
            }
            Button("Rewrite Lines", action: demo.rewriteScript)
                .disabled(demo.demo?.isCompiled != true || demo.isWritingScript || !demo.allowsAI)
        }
    }

    private func item(_ action: PanelActionID) -> some View {
        Button(action.menuTitle) { action.perform(on: demo) }
    }

    private var canEdit: Bool {
        !demo.isBusy && demo.demo?.isCompiled == true && !windowState.stageOnly
    }

    /// A built demo for the app on stage, with nothing running.
    private var canReplay: Bool {
        !demo.isBusy && demo.demo?.isCompiled == true && demo.isLiveSourceSelected
    }

    /// Playing for an audience right now, not paused.
    private var isPlaying: Bool {
        if case .running(.present, _, _) = demo.phase { true } else { false }
    }

    /// Previous Step and Start Over work while presenting, paused or not, and once the demo ends.
    private var canRewind: Bool {
        switch demo.phase {
        case .running(.present, _, _), .paused(.present, _, _, _), .offTrack(.present, _, _), .finished: true
        default: false
        }
    }

    private var canPlayOrContinue: Bool {
        guard demo.isLiveSourceSelected else { return false }
        switch demo.phase {
        case .ready, .finished, .paused, .offTrack: return demo.demo?.isCompiled == true
        case .needsStart(_, .ready), .needsStart(_, .play): return true
        case .scoutPaused(let stop): return stop.canKeepBuilding
        default: return false
        }
    }
}
