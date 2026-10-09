import SwiftUI

/// Where keyboard focus sits in the demo panel.
enum DemoPanelFocus: Hashable {
    case library, request, rename
}

/// The demo panel under the stage: the app's demos on the left, and the open
/// demo's status, steps and tools on the right. It keeps one height while a
/// demo plays, pauses or finishes, so the stage above never moves.
struct DemoBarView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject var demo: DemoSession
    @State private var editing: EditorRequest?
    @State private var deleting: RealTimeDemo?
    @State private var renaming: UUID?
    @State private var contentWidth: CGFloat = 0
    @State private var composerHeight = Self.innerHeight
    @State private var announcementBase = DemoPhase.composing
    @State private var announcedDemoID: UUID?
    @FocusState private var focus: DemoPanelFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct EditorRequest: Identifiable {
        let plan: RealTimeDemo
        var step: UUID?
        var id: UUID { plan.id }
    }

    /// 168 pt with the panel's 16 pt padding.
    private static let innerHeight: CGFloat = 136
    /// Composing grows with a longer request, up to 200 pt.
    private static let maximumComposingHeight: CGFloat = 168

    private var appName: String { demo.selectedSource?.name ?? "this app" }
    private var isComposing: Bool { demo.phase == .composing }
    private var showsLibrary: Bool { !demo.savedDemos.isEmpty }

    private var inputs: DemoPanelInputs {
        DemoPanelInputs(session: demo, stagePaused: manager.state == .paused)
    }

    private var libraryWidth: CGFloat {
        min(240, max(160, (contentWidth * 0.2).rounded()))
    }

    var body: some View {
        let content = DemoPanelContent.make(inputs)
        HStack(alignment: .top, spacing: 0) {
            if showsLibrary {
                DemoLibraryList(
                    demo: demo, openStatus: content.libraryStatus, renaming: $renaming, focus: $focus,
                    newDemo: startNewDemo, cancelNewDemo: cancelNewDemo, edit: { edit() }, rename: startRename,
                    delete: { deleting = $0 }
                )
                .frame(width: libraryWidth)
                .transition(reduceMotion ? .identity : .opacity)
                Divider().padding(.horizontal, 12)
            }
            detail(content)
        }
        .frame(
            height: isComposing
                ? min(max(composerHeight, Self.innerHeight), Self.maximumComposingHeight) : Self.innerHeight,
            alignment: .top
        )
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            contentWidth = $0
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspacePanel()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsLibrary)
        .sheet(item: $editing) { request in
            DemoEditorView(demo: demo, plan: request.plan, focusedStep: request.step)
        }
        .confirmationDialog(
            "Delete “\(deleting?.title ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { plan in
            Button("Delete Demo", role: .destructive) {
                demo.deleteDemo(plan.id)
                focus = .library
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its steps and lines are removed from this Mac. Other demos stay.")
        }
        .onChange(of: demo.selectedSource) { _, _ in
            editing = nil
            deleting = nil
            renaming = nil
        }
        .onChange(of: demo.demo?.id) { _, id in
            // The Demo menu can open another demo while a sheet is up.
            editing = nil
            deleting = nil
            if renaming != id { renaming = nil }
            // Switching demos is quiet, but the next phase change on the new one isn't.
            // A build starting on its new demo is announced from the phase change.
            if demo.phase != .scouting {
                announcedDemoID = id
                announcementBase = demo.phase
            }
        }
        .onChange(of: demo.panelRequest) { _, request in
            guard let request else { return }
            demo.panelRequest = nil
            switch request {
            case .new: startNewDemo()
            case .edit: edit()
            case .rename: startRename(demo.demo?.id)
            case .delete: if let plan = demo.demo, !demo.isBusy { deleting = plan }
            }
        }
        .onAppear {
            announcementBase = demo.phase
            announcedDemoID = demo.demo?.id
        }
        .onChange(of: demo.phase) { _, phase in announce(phase) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Real-time demos for \(appName)")
    }

    // MARK: Detail

    private func detail(_ content: DemoPanelContent) -> some View {
        VStack(alignment: .leading, spacing: isComposing ? 12 : 8) {
            DemoStatusBand(content: content, diagnosticDetails: demo.diagnosticDetails, perform: perform)
            if isComposing {
                DemoComposer(demo: demo, row: content.composerRow, focus: $focus, cancel: cancelNewDemo)
            } else {
                bodyRegion(content)
                    .frame(height: 58, alignment: .topLeading)
                DemoActionBar(demo: demo, manager: manager, bar: content.bar, perform: perform)
            }
        }
        .fixedSize(horizontal: false, vertical: isComposing)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            if isComposing { composerHeight = height }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.detailLabel)
    }

    @ViewBuilder private func bodyRegion(_ content: DemoPanelContent) -> some View {
        Group {
            switch content.body {
            case .grid:
                DemoStepGrid(cells: content.cells, isEditable: content.cellsAreEditable) { edit(focusing: $0) }
            case .line:
                PresentingLineView(prompter: demo.prompter, emptyText: "No line for this step")
            case .closing:
                PresentingLineView(prompter: demo.prompter, emptyText: "That’s the whole demo.")
            case .empty:
                Text("Nothing recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            case .composer:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: content.body)
    }

    // MARK: Actions

    private func perform(_ action: PanelActionID) {
        if action == .editDemo { edit() } else { action.perform(on: demo) }
    }

    private func startNewDemo() {
        demo.newDemo()
        focus = .request
    }

    private func cancelNewDemo() {
        demo.cancelNewDemo()
        focus = .library
    }

    private func edit(focusing step: UUID? = nil) {
        guard let plan = demo.demo, plan.isCompiled, !demo.isBusy else { return }
        editing = EditorRequest(plan: plan, step: step)
    }

    /// Renames in place on the demo's row, opening it first if it isn't open.
    private func startRename(_ id: UUID?) {
        guard let id, !demo.isBusy, demo.savedDemos.first(where: { $0.id == id })?.isCompiled == true else { return }
        if id != demo.demo?.id { demo.openDemo(id) }
        guard demo.demo?.id == id else { return }
        renaming = id
    }

    // MARK: VoiceOver

    /// Says what changed when the phase changes kind. Switching demos stays
    /// quiet, except for a build starting on its new demo.
    private func announce(_ phase: DemoPhase) {
        let id = demo.demo?.id
        defer { announcedDemoID = id }
        guard id == announcedDemoID || phase == .scouting else {
            announcementBase = phase
            return
        }
        if let text = DemoPanelContent.announcement(from: announcementBase, to: inputs) {
            AccessibilityNotification.Announcement(text).post()
        }
        announcementBase = DemoPanelContent.announcementBase(previous: announcementBase, next: phase)
    }
}

/// The current line, when the teleprompter is hidden while presenting.
private struct PresentingLineView: View {
    @ObservedObject var prompter: PresenterPrompter
    @ObservedObject var listener: SpeechListener
    let emptyText: String

    init(prompter: PresenterPrompter, emptyText: String) {
        self.prompter = prompter
        listener = prompter.listener
        self.emptyText = emptyText
    }

    var body: some View {
        Group {
            if prompter.follower.isEmpty {
                Text(emptyText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ScriptLineText(
                    follower: prompter.follower, size: 15,
                    marksNextWord: prompter.followsVoice && listener.isListening
                )
                .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current line")
        .accessibilityValue(
            prompter.follower.isEmpty ? emptyText : prompter.follower.displayWords.joined(separator: " "))
    }
}
