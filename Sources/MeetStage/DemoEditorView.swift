import SwiftUI

/// Edits a demo's title and everything the presenter says, in one place.
/// Targets and actions come from what the scout actually did in the app, so
/// they can't be retyped here; removing an action also removes every step
/// after it. Each step holds for as long as its line takes to say.
struct DemoEditorView: View {
    @ObservedObject var demo: DemoSession
    @State private var draft: RealTimeDemo
    /// The demo as the editor last synced it, to apply only what changed.
    @State private var base: RealTimeDemo
    @State private var truncation: DemoStep?
    private let focusedStep: UUID?
    @Environment(\.dismiss) private var dismiss

    init(demo: DemoSession, plan: RealTimeDemo, focusedStep: UUID? = nil) {
        self.demo = demo
        _draft = State(initialValue: plan)
        _base = State(initialValue: plan)
        self.focusedStep = focusedStep
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            rewriteBar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        lineRow(
                            symbol: "text.quote", title: "Opening", detail: "Before the first step",
                            text: Binding(get: { draft.openingScript ?? "" }, set: { draft.openingScript = $0 }))
                        ForEach($draft.steps) { $step in
                            Divider().padding(.leading, 52)
                            stepRow($step).id(step.id)
                        }
                        Divider().padding(.leading, 52)
                        lineRow(
                            symbol: "flag.checkered", title: "Closing", detail: "After the last step",
                            text: $draft.closingScript)
                    }
                    .padding(.vertical, 8)
                    .opacity(demo.isWritingScript ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.2), value: demo.isWritingScript)
                }
                .onAppear {
                    if let focusedStep { proxy.scrollTo(focusedStep, anchor: .top) }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 560, idealHeight: 720)
        .onChange(of: demo.isWritingScript) { _, writing in
            if !writing { takeRewrittenLines() }
        }
        .confirmationDialog(
            "Remove this step and everything after it?",
            isPresented: Binding(get: { truncation != nil }, set: { if !$0 { truncation = nil } }),
            presenting: truncation
        ) { step in
            Button("Remove \(stepsAfter(step)) Steps", role: .destructive) {
                if let index = draft.steps.firstIndex(where: { $0.id == step.id }) {
                    draft.steps.removeSubrange(index...)
                }
            }
        } message: { _ in
            Text("Later steps depend on what this action opens in the app.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Demo title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .accessibilityLabel("Demo title")
            HStack(spacing: 6) {
                Text("\(draft.app.appName) · \(draft.steps.count) steps")
                    .foregroundStyle(.secondary)
                if demo.isChecked {
                    Label("Tested", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 16)
                if draft.start != nil {
                    Text("Starts on").foregroundStyle(.secondary)
                    TextField(
                        draft.startLabel,
                        text: Binding(get: { draft.start?.label ?? "" }, set: { draft.start?.label = $0 })
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .help("BetterMeets checks: \(draft.start?.description ?? "")")
                    .accessibilityLabel("Starts on")
                }
            }
            .font(.callout)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var rewriteBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("Tone", selection: $demo.scriptTone) {
                    ForEach(ScriptTone.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
                ScriptLanguagePicker(title: "Language", selection: $demo.scriptLanguage)
                    .help("The language Rewrite Lines writes every title and line in")
                TextField("Audience, e.g. investors who know crypto", text: $demo.scriptAudience)
                    .textFieldStyle(.roundedBorder)
                Button {
                    demo.rewriteScript()
                } label: {
                    if demo.isWritingScript {
                        ProgressView().controlSize(.small).frame(minWidth: 110)
                    } else {
                        Label("Rewrite Lines", systemImage: "sparkles")
                    }
                }
                .disabled(demo.isWritingScript || !demo.allowsAI || !demo.hasKey || hasRemovedSteps)
                .help(
                    hasRemovedSteps
                        ? "Save or cancel removed steps first"
                        : "Claude rewrites every line as one story. Lines you edited here are kept.")
            }
            if let error = demo.scriptError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Rows

    private func stepRow(_ step: Binding<DemoStep>) -> some View {
        let value = step.wrappedValue
        let number = (draft.steps.firstIndex(where: { $0.id == value.id }) ?? 0) + 1
        return HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Step title", text: step.title)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .accessibilityLabel("Title of step \(number)")
                    Button(role: .destructive) {
                        if value.action.isMutating {
                            truncation = value
                        } else {
                            draft.steps.removeAll { $0.id == value.id }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(draft.steps.count == 1)
                    .help(value.action.isMutating ? "Remove this step and the ones after it" : "Remove this step")
                    .accessibilityLabel("Remove step \(number)")
                }
                Label(summary(value.action), systemImage: value.action.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                lineField(step.script, placeholder: "What you say during this step")
                    .accessibilityLabel("Line for step \(number)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func lineRow(symbol: String, title: String, detail: String, text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                lineField(text, placeholder: "Optional")
                    .accessibilityLabel("\(title) line")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func lineField(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineSpacing(3)
            .lineLimit(1...8)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Copy Script", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft.presenterScript, forType: .string)
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") {
                if demo.updateDemo(draft, base: base) { dismiss() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled((try? draft.validated()) == nil || draft.steps.isEmpty || demo.isBusy)
        }
        .padding(16)
    }

    private var footnote: String {
        if demo.isBusy { return "Pause the demo to save changes." }
        return hasRemovedSteps
            ? "Removing an action means testing the demo again."
            : "Edited words keep the demo tested."
    }

    /// Steps removed here but not saved yet.
    private var hasRemovedSteps: Bool { draft.steps.map(\.id) != base.steps.map(\.id) }

    /// After Claude rewrites the script, takes its lines for everything not edited here.
    private func takeRewrittenLines() {
        guard let live = demo.demo, live.id == draft.id else { return }
        let rewritten = Dictionary(uniqueKeysWithValues: live.steps.map { ($0.id, $0) })
        let originals = Dictionary(uniqueKeysWithValues: base.steps.map { ($0.id, $0) })
        for index in draft.steps.indices {
            let step = draft.steps[index]
            guard let new = rewritten[step.id], let old = originals[step.id] else { continue }
            if step.title == old.title { draft.steps[index].title = new.title }
            if step.script == old.script { draft.steps[index].script = new.script }
        }
        if draft.openingScript == base.openingScript { draft.openingScript = live.openingScript }
        if draft.closingScript == base.closingScript { draft.closingScript = live.closingScript }
        if draft.start?.label == base.start?.label { draft.start?.label = live.start?.label }
        base = live
    }

    private func summary(_ action: DemoAction) -> String {
        switch action {
        case .click(let target): "Click \(target.displayName)"
        case .typeText(let field, let text, let submit):
            "Type “\(text)” into \(field.displayName)\(submit ? " and press Return" : "")"
        case .press(let key): "Press \(key.badge)"
        case .navigate(let url): "Open \(url.host ?? "")\(url.path)"
        case .present(let beat):
            "\(beat.effect.label): " + beat.targets.map(\.displayName).joined(separator: ", ")
        }
    }

    private func stepsAfter(_ step: DemoStep) -> Int {
        guard let index = draft.steps.firstIndex(where: { $0.id == step.id }) else { return 1 }
        return draft.steps.count - index
    }
}
