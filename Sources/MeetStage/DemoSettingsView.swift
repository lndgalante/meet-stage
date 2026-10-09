import SwiftUI

/// The Demos pane in Settings: Claude access, presenting and pacing.
struct DemoSettingsView: View {
    @ObservedObject var demo: DemoSession
    @State private var key = ""
    @State private var hasAccessibility = AccessibilityService.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Claude explores your app, records a walkthrough of what’s really there, then plays it back to test it."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 4)

            SettingsFormRow(title: "API key") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SecureField(demo.hasKey ? "Saved in Keychain" : "Paste your Anthropic API key", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey).disabled(trimmedKey.isEmpty)
                    }
                    if demo.hasKey {
                        HStack(spacing: 8) {
                            Label("Saved in Keychain", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Button("Remove") { demo.saveKey("") }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                    }
                }
            }

            SettingsFormRow(title: "Claude access") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("See and operate the selected window while building", isOn: $demo.allowsAI)
                        .toggleStyle(.checkbox)
                    caption(
                        "Building sends your request, screenshots and control labels to Anthropic. Playing or testing sends a screenshot only when a control moved and has to be found again. It never pays, sends, deletes or enters passwords, and asks before anything unusual. Builds stop at $2."
                    )
                }
            }

            SettingsFormRow(title: "Script language") {
                VStack(alignment: .leading, spacing: 4) {
                    ScriptLanguagePicker(title: "Script language", selection: $demo.scriptLanguage)
                    caption(
                        "Claude writes the demo title, step titles and every line in this language. The teleprompter follows your voice in it. To change an existing demo, use Rewrite Lines in Edit Demo."
                    )
                }
            }

            Divider().padding(.vertical, 4)

            SettingsFormRow(title: "Teleprompter") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show under the camera when a demo plays", isOn: $demo.opensTeleprompter)
                        .toggleStyle(.checkbox)
                    caption("Share the BetterMeets window, not your whole screen, to keep it private.")
                }
            }

            SettingsFormRow(title: "Pacing") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Follow my voice", isOn: $demo.followsVoice)
                            .toggleStyle(.checkbox)
                        caption("Each step moves on when you finish its line. Speech stays on this Mac.")
                    }
                    Toggle("Pause after each step", isOn: $demo.pausesAfterEachStep)
                        .toggleStyle(.checkbox)
                    Picker("Speed", selection: $demo.playbackSpeed) {
                        ForEach(DemoPlaybackSpeed.allCases) { Text($0.label).tag($0) }
                    }
                    .fixedSize()
                    .disabled(demo.followsVoice)
                    .help(
                        demo.followsVoice
                            ? "Your voice sets the pace while Follow my voice is on."
                            : "Shortens pauses. Every line still gets the time it takes to say.")
                }
            }

            Divider().padding(.vertical, 4)

            SettingsFormRow(title: "Accessibility") {
                HStack {
                    if hasAccessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button("Allow Access…") { AccessibilityService.requestTrust() }
                    }
                    caption("Lets BetterMeets read, click and type in the app.")
                }
            }

            if let message = demo.notice {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = AccessibilityService.isTrusted
        }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveKey() {
        guard !trimmedKey.isEmpty else { return }
        demo.saveKey(trimmedKey)
        key = ""
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The request's own language first, then every language by its own name.
struct ScriptLanguagePicker: View {
    let title: String
    @Binding var selection: ScriptLanguage

    var body: some View {
        Picker(title, selection: $selection) {
            Text(ScriptLanguage.automatic.label).tag(ScriptLanguage.automatic)
            Divider()
            ForEach(ScriptLanguage.allCases.filter { $0 != .automatic }) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}
