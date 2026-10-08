import SwiftUI

struct DemoCommands: Commands {
    @ObservedObject var demo: DemoSession

    var body: some Commands {
        CommandMenu("Demo") {
            Button(demo.phase.isActuating ? "Pause Demo" : "Play or Continue Demo") {
                if demo.phase.isActuating { demo.pause() } else { demo.play() }
            }
            .keyboardShortcut(.return, modifiers: [.command, .control])
            .disabled(!demo.phase.isActuating && !canPlayOrContinue)
            Button(isPresenting ? "Next Line" : "Next Step") {
                if isPresenting { demo.skipLine() } else { demo.play(singleStep: true) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            .disabled(
                !isPresenting
                    && (demo.isBusy || demo.demo?.isCompiled != true || !demo.isLiveSourceSelected
                        || demo.phase.replayMode == .verify))
            Button("Return to Start", action: demo.returnToStart)
                .disabled(demo.isBusy || demo.demo?.isCompiled != true)
            Button("Check Again", action: demo.checkAgain)
                .disabled(demo.isBusy || demo.demo?.isCompiled != true || !demo.isLiveSourceSelected)
            Divider()
            if !demo.prompter.followsVoice {
                Picker("Playback Speed", selection: $demo.playbackSpeed) {
                    ForEach(DemoPlaybackSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
            }
            Toggle("Pause After Each Step", isOn: $demo.pausesAfterEachStep)
            Divider()
            Button(demo.notesVisible ? "Hide Presenter Notes" : "Show Presenter Notes", action: demo.toggleNotes)
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(demo.demo?.isCompiled != true && !demo.notesVisible)
            Toggle(
                "Follow My Voice",
                isOn: Binding(
                    get: { demo.prompter.followsVoice },
                    set: {
                        demo.prompter.followsVoice = $0
                        demo.updateListening()
                    }))
            Button("Rewrite Script", action: demo.rewriteScript)
                .disabled(demo.demo?.isCompiled != true || demo.isWritingScript || !demo.allowsAI)
        }
    }

    private var isPresenting: Bool {
        if case .running(.present, _, _) = demo.phase { true } else { false }
    }

    private var canPlayOrContinue: Bool {
        guard demo.isLiveSourceSelected else { return false }
        switch demo.phase {
        case .ready, .finished, .paused, .offTrack: return demo.demo?.isCompiled == true
        case .needsStart(_, .ready): return true
        case .scoutPaused(let stop): return stop.canKeepBuilding
        default: return false
        }
    }
}
