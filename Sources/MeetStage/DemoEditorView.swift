import SwiftUI

/// Edits a recorded demo's words and timing. Targets and actions come from
/// what the scout actually did in the app, so they can't be retyped here;
/// removing an action also removes every step after it.
struct DemoEditorView: View {
    @ObservedObject var demo: DemoSession
    @State var draft: RealTimeDemo
    /// The demo as the editor opened it, to apply only what changed.
    let base: RealTimeDemo

    init(demo: DemoSession, draft: RealTimeDemo) {
        self.demo = demo
        _draft = State(initialValue: draft)
        base = draft
    }
    @State private var truncation: DemoStep?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Demo steps").font(.title2.weight(.semibold))
                Spacer()
                Text("\(draft.steps.count) steps").foregroundStyle(.secondary)
            }
            .padding(20)
            Form {
                TextField("Title", text: $draft.title)
                if draft.start != nil {
                    TextField(
                        "Starts on",
                        text: Binding(
                            get: { draft.start?.description ?? "" }, set: { draft.start?.description = $0 }),
                        axis: .vertical)
                }
                TextField("Closing line", text: $draft.closingScript, axis: .vertical)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach($draft.steps) { $step in
                        stepEditor($step)
                        Divider()
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(20)
            }
            Divider()
            HStack {
                Text(
                    demo.isBusy
                        ? "Pause the demo to save changes."
                        : "Changing words and timing keeps the check. Removing an action needs a new check."
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if demo.updateDemo(draft, base: base) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled((try? draft.validated()) == nil || draft.steps.isEmpty || demo.isBusy)
            }
            .padding(16)
        }
        .frame(width: 620, height: 640)
        .confirmationDialog(
            "Remove this step and everything after it?", isPresented: Binding(
                get: { truncation != nil }, set: { if !$0 { truncation = nil } }),
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

    private func stepEditor(_ step: Binding<DemoStep>) -> some View {
        let value = step.wrappedValue
        let number = (draft.steps.firstIndex(where: { $0.id == value.id }) ?? 0) + 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(number)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: value.action.symbol).foregroundStyle(.secondary)
                TextField("Step title", text: step.title).font(.headline)
                Button(role: .destructive) {
                    if value.action.isMutating {
                        truncation = value
                    } else {
                        draft.steps.removeAll { $0.id == value.id }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(draft.steps.count == 1)
                .accessibilityLabel("Remove \(value.title)")
            }
            HStack {
                Text(summary(value.action)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Stepper(value: step.holdSeconds, in: 0.3...30, step: 0.5) {
                    Text("Hold \(value.holdSeconds.formatted(.number.precision(.fractionLength(0...1))))s")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            TextField("What you say (optional)", text: step.script, axis: .vertical)
                .accessibilityLabel("Presenter script for \(value.title)")
        }
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
