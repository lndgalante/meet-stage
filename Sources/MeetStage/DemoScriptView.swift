import SwiftUI

struct DemoScriptView: View {
    @ObservedObject var demo: DemoSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Presenter script").font(.title2.weight(.semibold))
                Text(demo.demo?.title ?? "").foregroundStyle(.secondary)
                if let start = demo.demo?.start, !start.description.isEmpty {
                    Text("Starts on: \(start.description)").font(.callout)
                }
            }
            .padding(20)
            rewriteControls
                .padding(.horizontal, 20)
                .padding(.bottom, demo.scriptError == nil ? 14 : 6)
            if let error = demo.scriptError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let opening = demo.demo?.openingScript, !opening.isEmpty {
                            line(title: "Opening", text: opening, isCurrent: false)
                        }
                        ForEach(Array((demo.demo?.steps ?? []).enumerated()), id: \.element.id) { index, step in
                            line(
                                title: "\(index + 1). \(step.title)",
                                text: step.script.isEmpty ? nil : step.script,
                                isCurrent: demo.phase.currentStep == index
                            )
                            .id(index)
                        }
                        if let closing = demo.demo?.closingScript, !closing.isEmpty {
                            line(title: "Closing", text: closing, isCurrent: false)
                        }
                    }
                    .padding(20)
                    .textSelection(.enabled)
                    .opacity(demo.isWritingScript ? 0.45 : 1)
                    .animation(.easeOut(duration: 0.2), value: demo.isWritingScript)
                }
                .onAppear {
                    if let current = demo.phase.currentStep { proxy.scrollTo(current, anchor: .top) }
                }
            }
            Divider()
            HStack {
                Button("Copy Script", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(demo.demo?.presenterScript ?? "", forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 640)
    }

    private var rewriteControls: some View {
        HStack(spacing: 10) {
            Picker("Tone", selection: $demo.scriptTone) {
                ForEach(ScriptTone.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()
            TextField("Audience or notes, e.g. investors who know crypto", text: $demo.scriptAudience)
                .textFieldStyle(.roundedBorder)
            Button {
                demo.rewriteScript()
            } label: {
                if demo.isWritingScript {
                    ProgressView().controlSize(.small).frame(minWidth: 96)
                } else {
                    Label("Rewrite Script", systemImage: "sparkles")
                }
            }
            .disabled(demo.isWritingScript || demo.demo?.isCompiled != true || !demo.allowsAI || !demo.hasKey)
            .help("Claude rewrites every line as one story. Steps and the check don’t change.")
        }
    }

    private func line(title: String, text: String?, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                if isCurrent {
                    Text("Current step").font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            Text(text ?? "No line — this step just moves the demo along.")
                .font(.system(size: 16))
                .foregroundStyle(text == nil ? .secondary : .primary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
