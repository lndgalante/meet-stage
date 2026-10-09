import SwiftUI

/// A row of the demo library: a saved demo, or the one being written.
enum LibraryRow: Hashable {
    case demo(UUID)
    case new
}

extension RealTimeDemo {
    var libraryRow: LibraryRow { .demo(id) }
}

/// The demo panel's library: the app's demos. Selecting a row opens it; it's
/// the one place to create, switch, rename and delete demos.
struct DemoLibraryList: View {
    @ObservedObject var demo: DemoSession
    /// How the open demo's row is marked right now.
    let openStatus: LibraryRowStatus?
    @Binding var renaming: UUID?
    var focus: FocusState<DemoPanelFocus?>.Binding
    let newDemo: () -> Void
    let cancelNewDemo: () -> Void
    let edit: () -> Void
    let rename: (UUID) -> Void
    let delete: (RealTimeDemo) -> Void
    @State private var selection: LibraryRow?
    @State private var title = ""
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appName: String { demo.selectedSource?.name ?? "this app" }
    private var isComposing: Bool { demo.phase == .composing }
    private var openID: UUID? { demo.demo?.id }

    /// The row the session has open.
    private var modelSelection: LibraryRow? {
        openID.map(LibraryRow.demo) ?? (isComposing ? .new : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(appName) Demos")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(contrast == .increased ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Lines up with the row glyphs, which sit inside the plain List's own row inset.
                .padding(.leading, 9)
                .frame(height: 20, alignment: .leading)
                .help("Demos for \(appName), saved on this Mac")
                .accessibilityAddTraits(.isHeader)
            list
            libraryBar
        }
        .onAppear { selection = modelSelection }
        .onChange(of: modelSelection) { _, row in selection = row }
        .onChange(of: selection) { _, row in select(row) }
        .onChange(of: renaming) { _, id in
            guard let id, let saved = savedDemo(id) else { return }
            title = saved.title
        }
        .onChange(of: focus.wrappedValue) { old, new in
            // Leaving the field saves the name, as in Finder.
            if old == .rename, new != .rename, renaming != nil { commitRename() }
        }
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            rows
                // The open demo stays in view, even when it's past the rows that fit.
                .onAppear { reveal(modelSelection, with: proxy) }
                .onChange(of: modelSelection) { _, row in reveal(row, with: proxy) }
        }
    }

    private func reveal(_ row: LibraryRow?, with proxy: ScrollViewProxy) {
        guard let row else { return }
        Task { @MainActor in proxy.scrollTo(row) }
    }

    private var rowCount: Int { demo.savedDemos.count + (isComposing ? 1 : 0) }

    private var rows: some View {
        List(selection: $selection) {
            // Rows are identified by their selection value, which ScrollViewReader scrolls to.
            ForEach(demo.savedDemos, id: \.libraryRow) { saved in
                savedRow(saved)
                    .tag(saved.libraryRow)
                    .selectionDisabled(demo.isBusy && saved.id != openID)
            }
            if isComposing {
                newRow.tag(LibraryRow.new).id(LibraryRow.new)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .environment(\.defaultMinListRowHeight, 24)
        // A peeking fourth row fades out, so it reads as "more below", not as clipped.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.78),
                    .init(color: .black.opacity(rowCount > 3 ? 0.15 : 1), location: 1)
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .focused(focus, equals: .library)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: demo.savedDemos.map(\.id))
        .contextMenu(forSelectionType: LibraryRow.self) { rows in
            if let row = rows.first { menu(for: row) }
        } primaryAction: { rows in
            if rows.first == openID.map(LibraryRow.demo), canEdit { edit() }
        }
        .onDeleteCommand(perform: deleteSelection)
        .onKeyPress(.return) {
            // Return renames the selected demo, as in Finder.
            guard renaming == nil, case .demo(let id) = selection, canRename(id) else { return .ignored }
            rename(id)
            return .handled
        }
        .accessibilityLabel("\(appName) Demos")
    }

    private func savedRow(_ saved: RealTimeDemo) -> some View {
        let isOpen = saved.id == openID
        let isLocked = demo.isBusy && !isOpen
        let status = isOpen ? openStatus ?? .saved(saved) : .saved(saved)
        return Label {
            if renaming == saved.id {
                TextField("Demo title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused(focus, equals: .rename)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
                    .onAppear { focus.wrappedValue = .rename }
            } else {
                Text(saved.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            LibraryGlyph(status: status)
        }
        .foregroundStyle(isLocked ? .tertiary : .primary)
        .help(isLocked ? "Pause first to switch demos" : saved.title)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .accessibilityElement(children: renaming == saved.id ? .contain : .ignore)
        .accessibilityLabel(saved.title)
        .accessibilityValue(status.accessibilityValue)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    private var newRow: some View {
        HStack(spacing: 6) {
            Label {
                Text("New demo").font(.callout).lineLimit(1)
            } icon: {
                LibraryGlyph(status: .new)
            }
            Spacer(minLength: 4)
            Button(PanelActionID.cancelNewDemo.title, action: cancelNewDemo)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help(PanelActionID.cancelNewDemo.help(.init(app: appName, start: "")))
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: Menus

    @ViewBuilder private func menu(for row: LibraryRow) -> some View {
        switch row {
        case .new:
            Button(PanelActionID.cancelNewDemo.menuTitle, action: cancelNewDemo)
        case .demo(let id):
            if let saved = savedDemo(id) {
                if id != openID {
                    Button("Open") { demo.openDemo(id) }.disabled(demo.isBusy)
                    Button(PanelActionID.renameDemo.title) { rename(id) }.disabled(!canRename(id))
                    Divider()
                    deleteButton(saved)
                } else if saved.draft != nil {
                    draftMenu(saved)
                } else {
                    Button(PanelActionID.editDemo.title, action: edit).disabled(!canEdit)
                    Button(PanelActionID.renameDemo.title) { rename(id) }.disabled(!canRename(id))
                    Button(PanelActionID.testAgain.title, action: demo.checkAgain)
                        .disabled(demo.isBusy || !demo.isLiveSourceSelected)
                    Button(PanelActionID.goToStart.title, action: demo.returnToStart)
                        .disabled(demo.phase == .ready || demo.isBusy || !demo.isLiveSourceSelected)
                    Divider()
                    deleteButton(saved)
                }
            }
        }
    }

    /// A build's own decisions; all off while it's running.
    @ViewBuilder private func draftMenu(_ saved: RealTimeDemo) -> some View {
        let isStopped = if case .scoutPaused = demo.phase { true } else { false }
        Group {
            if demo.scoutedSteps > 0 {
                Button(PanelActionID.useSteps(demo.scoutedSteps).title, action: demo.useRecordedSteps)
                    .disabled(!isStopped || !demo.isLiveSourceSelected)
            }
            Button(PanelActionID.editRequest.title, action: demo.editRequest).disabled(!isStopped)
            Divider()
            deleteButton(saved)
        }
        .help(demo.isBusy ? "Pause the build first" : "")
    }

    private func deleteButton(_ saved: RealTimeDemo) -> some View {
        Button(PanelActionID.deleteDemo.title, role: .destructive) { delete(saved) }
            .disabled(demo.isBusy)
    }

    // MARK: Library bar

    private var libraryBar: some View {
        HStack(spacing: 0) {
            Button(action: newDemo) {
                Label(PanelActionID.newDemo.title, systemImage: "plus")
            }
            .disabled(demo.isBusy || demo.selectedSource == nil || isComposing)
            .help(PanelActionID.newDemo.help(.init(app: appName, start: "")))
            Spacer(minLength: 4)
            Button(action: minus) {
                Image(systemName: "minus").frame(width: 16, height: 16)
            }
            .disabled(demo.isBusy || (selection == nil && openID == nil))
            .help(minusHelp)
            .accessibilityLabel(isComposing ? "Cancel New Demo" : "Delete Demo")
        }
        .buttonStyle(.accessoryBarAction)
        .font(.callout)
        .frame(height: 24)
    }

    private var minusHelp: String {
        if isComposing { return "Cancel the new demo" }
        return demo.demo.map { "Delete “\($0.title)”…" } ?? "Delete Demo…"
    }

    private func minus() {
        if isComposing {
            cancelNewDemo()
        } else if let open = demo.demo {
            delete(open)
        }
    }

    // MARK: Actions

    private var canEdit: Bool { demo.demo?.isCompiled == true && !demo.isBusy }

    private func canRename(_ id: UUID) -> Bool {
        !demo.isBusy && savedDemo(id)?.isCompiled == true
    }

    private func savedDemo(_ id: UUID) -> RealTimeDemo? { demo.savedDemos.first { $0.id == id } }

    private func select(_ row: LibraryRow?) {
        guard row != modelSelection else { return }
        if case .demo(let id) = row {
            demo.openDemo(id)
            // The session refuses while busy; the list goes back to what's open.
            if openID != id { selection = modelSelection }
        } else {
            selection = modelSelection
        }
    }

    private func deleteSelection() {
        guard !demo.isBusy else { return }
        switch selection {
        case .demo(let id): if let saved = savedDemo(id) { delete(saved) }
        case .new: cancelNewDemo()
        case nil: break
        }
    }

    private func commitRename() {
        guard renaming != nil else { return }
        demo.renameDemo(to: title)
        renaming = nil
        focus.wrappedValue = .library
    }

    private func cancelRename() {
        renaming = nil
        focus.wrappedValue = .library
    }
}

/// A demo's status mark in the library.
private struct LibraryGlyph: View {
    let status: LibraryRowStatus

    var body: some View {
        Group {
            switch status {
            case .playing:
                Image(systemName: "play.fill").foregroundStyle(Color.accentColor)
            case .working:
                ProgressView().controlSize(.mini)
            case .paused, .buildPaused:
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            case .tested:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            case .notTested:
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            case .new:
                Image(systemName: "square.and.pencil").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(width: 16)
    }
}
