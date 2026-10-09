import SwiftUI

/// The bar under the steps: this demo's tools on the leading side, the presenter's on the trailing side.
struct DemoActionBar: View {
    @ObservedObject var demo: DemoSession
    let manager: CaptureManager
    let bar: DemoPanelContent.BarActions
    let perform: (PanelActionID) -> Void

    var body: some View {
        // Edit Demo… and Test Again keep their labels; the presenter's tools fold first.
        ViewThatFits(in: .horizontal) {
            row(compactTools: false, compactWriting: false)
            row(compactTools: true, compactWriting: false)
            row(compactTools: true, compactWriting: true)
        }
        .frame(height: 24)
    }

    private func row(compactTools: Bool, compactWriting: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(bar.demoTools) { action in
                Button {
                    perform(action.id)
                } label: {
                    Label(action.title, systemImage: action.symbol ?? "circle")
                }
                .buttonStyle(.accessoryBarAction)
                .disabled(!action.isEnabled)
                .help(action.help)
            }
            if bar.isWritingScript {
                writingLines(compact: compactWriting)
                    .padding(.leading, bar.demoTools.isEmpty ? 0 : 8)
            }
            Spacer(minLength: 12)
            teleprompterToggle(compact: compactTools)
            PacingMenu(demo: demo, prompter: demo.prompter, manager: manager, compact: compactTools)
        }
        .font(.callout)
    }

    private func writingLines(compact: Bool) -> some View {
        let text = "Writing lines…"
        return HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            if !compact {
                Text(text).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    @ViewBuilder private func teleprompterToggle(compact: Bool) -> some View {
        let toggle = Toggle(
            isOn: Binding(get: { demo.teleprompterVisible }, set: { _ in demo.toggleTeleprompter() })
        ) {
            Label("Teleprompter", systemImage: "captions.bubble")
        }
        .toggleStyle(.button)
        .buttonStyle(.accessoryBar)
        .disabled(!bar.teleprompterEnabled)
        .help(bar.teleprompterHelp)
        if compact {
            toggle.labelStyle(.iconOnly)
        } else {
            toggle
        }
    }
}

/// How the demo moves from step to step: following the presenter's voice, on a
/// timer, or one step at a time.
struct PacingMenu: View {
    @ObservedObject var demo: DemoSession
    @ObservedObject var prompter: PresenterPrompter
    let manager: CaptureManager
    var compact = false

    var body: some View {
        let menu = Menu {
            Toggle("Follow My Voice", isOn: $demo.followsVoice)
            Toggle("Pause After Each Step", isOn: $demo.pausesAfterEachStep)
            if !prompter.followsVoice {
                Picker("Speed", selection: $demo.playbackSpeed) {
                    ForEach(DemoPlaybackSpeed.allCases) { Text($0.label).tag($0) }
                }
            }
            Divider()
            Button("Demo Settings…") { UtilityWindows.showSettings(manager: manager, tab: .demos) }
        } label: {
            Label(mode.title, systemImage: mode.symbol)
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBarAction)
        .menuIndicator(.visible)
        .fixedSize()
        .help("How the demo moves from step to step")
        .accessibilityLabel("Pacing")
        .accessibilityValue(mode.accessibilityValue)
        if compact {
            menu.labelStyle(.iconOnly)
        } else {
            menu
        }
    }

    private var mode: (title: String, symbol: String, accessibilityValue: String) {
        if demo.pausesAfterEachStep { return ("Step by Step", "pause.circle", "Step by step") }
        if prompter.followsVoice { return ("Voice", "waveform", "Follows your voice") }
        let speed = demo.playbackSpeed.label
        return ("Timed · \(speed)", "metronome", "Timed, \(speed)")
    }
}
