import SwiftUI

/// The request field and the one row under it: ideas to try, or the key or
/// Claude-access question Build is waiting on.
struct DemoComposer: View {
    @ObservedObject var demo: DemoSession
    let row: DemoPanelContent.ComposerRow
    var focus: FocusState<DemoPanelFocus?>.Binding
    let cancel: () -> Void
    @State private var key = ""
    @State private var showsAccessDetails = false

    private var appName: String { demo.selectedSource?.name ?? "this app" }
    private var showsSetupRow: Bool { row != .ideas }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field
            switch row {
            case .key: keyRow
            case .consent: consentRow
            case .ideas: ideasRow
            }
        }
    }

    // MARK: Field

    /// The request, with Claude's mark and Build Demo inside it.
    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .accessibilityHidden(true)
            TextField("What should the demo show in \(appName)?", text: $demo.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                // One line while empty, so the placeholder can't wrap and shift the stage on the first keystroke.
                .lineLimit(1...(showsSetupRow || demo.prompt.isEmpty ? 1 : 3))
                .focused(focus, equals: .request)
                .onSubmit(demo.build)
                .onExitCommand {
                    if !demo.savedDemos.isEmpty { cancel() }
                }
                .accessibilityLabel("Demo request")
                .help("Name a page or feature, or describe the flow step by step.")
            buildButton
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            if focus.wrappedValue == .request {
                DemoGlow(cornerRadius: 14, lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12))
            }
        }
        .animation(.easeOut(duration: 0.2), value: focus.wrappedValue == .request)
    }

    /// Prominent unless a setup row shows, which then holds the one prominent control.
    @ViewBuilder private var buildButton: some View {
        let action = PanelActionID.build
        let button = Button(action: demo.build) {
            Label(action.title, systemImage: action.symbol ?? "wand.and.sparkles")
        }
        .controlSize(.large)
        .disabled(!demo.canBuild)
        .help(
            demo.isLiveSourceSelected
                ? action.help(.init(app: appName, start: "")) : "Put an app on stage first")
        if showsSetupRow {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Ideas

    /// Two ideas that fit any app, then three Claude found in this one's own features.
    private var fixedIdeas: [DemoIdea] {
        [
            DemoIdea(
                label: "Quick tour", prompt: "Give a quick tour of \(appName)'s main screen and what matters most on it"
            ),
            DemoIdea(label: "Main flow", prompt: "Walk through the main flow of \(appName), step by step")
        ]
    }

    private var offersMoreIdeas: Bool {
        demo.allowsAI && demo.hasKey && !demo.isFindingIdeas && demo.isLiveSourceSelected
    }

    /// Requests to start from; picking one fills the field without building.
    /// Claude's ideas drop from the end to fit; More Ideas always stays.
    private var ideasRow: some View {
        let claude = demo.isFindingIdeas ? 3 : demo.ideas.count
        let counts = Array(stride(from: claude, through: 0, by: -1))
        return ViewThatFits(in: .horizontal) {
            ideasRow(claudeIdeas: claude, labelsMoreIdeas: true)
            ForEach(counts, id: \.self) { count in
                ideasRow(claudeIdeas: count, labelsMoreIdeas: false)
            }
        }
        .frame(height: 26)
    }

    private func ideasRow(claudeIdeas count: Int, labelsMoreIdeas: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Try").font(.callout).foregroundStyle(.secondary)
            ForEach(fixedIdeas, id: \.self) { idea in
                suggestion(idea, fromClaude: false)
            }
            if demo.isFindingIdeas {
                ForEach(0..<count, id: \.self) { _ in
                    Text("Finding ideas…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                        .accessibilityHidden(true)
                }
            } else {
                ForEach(demo.ideas.prefix(count), id: \.self) { idea in
                    suggestion(idea, fromClaude: true)
                }
            }
            if offersMoreIdeas {
                moreIdeas(labelled: labelsMoreIdeas)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func moreIdeas(labelled: Bool) -> some View {
        let button = Button {
            demo.findIdeas(again: true)
        } label: {
            Label("More Ideas", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .help("Ask Claude for other ideas from \(appName)'s features")
        if labelled {
            button
        } else {
            button.labelStyle(.iconOnly)
        }
    }

    private func suggestion(_ idea: DemoIdea, fromClaude: Bool) -> some View {
        Button {
            demo.prompt = idea.prompt
            focus.wrappedValue = .request
        } label: {
            if fromClaude {
                Label(idea.label, systemImage: "sparkles")
            } else {
                Text(idea.label)
            }
        }
        .buttonStyle(SuggestionStyle())
        .help(idea.prompt)
        .accessibilityHint(idea.prompt)
    }

    // MARK: Key

    private var keyRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                keyMessage(wraps: false)
                Spacer(minLength: 0)
                keyControls
            }
            VStack(alignment: .leading, spacing: 4) {
                keyMessage(wraps: true)
                HStack {
                    Spacer(minLength: 0)
                    keyControls
                }
            }
        }
    }

    private func keyMessage(wraps: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "key").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add your Anthropic API key to build demos. It stays in Keychain.")
                    .fixedSize(horizontal: !wraps, vertical: wraps)
                if let notice = demo.notice {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(notice).fixedSize(horizontal: !wraps, vertical: wraps)
                    }
                }
            }
        }
        .font(.callout)
    }

    private var keyControls: some View {
        HStack(spacing: 8) {
            SecureField("API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 200)
                .onSubmit(saveKey)
            Button("Not Now", action: demo.cancelBuildSetup)
            Button("Save and Build", action: saveKey)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedKey.isEmpty)
        }
        .fixedSize()
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveKey() {
        guard !trimmedKey.isEmpty, demo.saveKey(trimmedKey) else { return }
        key = ""
    }

    // MARK: Consent

    private static let consentText =
        "Claude operates the window you choose, in the background while you watch. Building sends your request, screenshots and control labels to Anthropic."

    private static let accessDetails =
        "Real-time demos let Claude see the window you choose and operate it in the background while you watch. Building sends your request, screenshots and control labels to Anthropic. Later, playing or testing sends a screenshot only to find a control that moved. Clicking or typing in the app pauses it. Claude never pays, sends, deletes or enters passwords, and builds stop at $2. You can change this anytime in Settings › Demos."

    /// Asked once for every app; Build asks again only after "Not Now".
    private var consentRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                consentMessage
                    .lineLimit(3)
                    .frame(minWidth: 340, idealWidth: 340, maxWidth: .infinity, alignment: .leading)
                consentControls
            }
            VStack(alignment: .leading, spacing: 4) {
                consentMessage.fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    consentControls
                }
            }
        }
    }

    private var consentMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hand.raised").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(Self.consentText)
        }
        .font(.callout)
    }

    private var consentControls: some View {
        HStack(spacing: 8) {
            Button("Learn More") { showsAccessDetails = true }
                .buttonStyle(.link)
                .font(.callout)
                .help("What Claude access sends, and when")
                .popover(isPresented: $showsAccessDetails, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude Access").font(.headline)
                        Text(Self.accessDetails)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 320, alignment: .leading)
                }
            Button("Not Now", action: demo.cancelBuildSetup)
            Button(demo.buildSetup == .consent ? "Allow and Build" : "Allow", action: demo.allowClaude)
                .buttonStyle(.borderedProminent)
                .help("Turns on Claude access for every app. Change this in Settings › Demos.")
        }
        .fixedSize()
    }
}

/// A rounded suggestion that fills the request field.
private struct SuggestionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(isHovering ? 0.12 : 0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}
