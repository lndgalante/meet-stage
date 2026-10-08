import SwiftUI

struct DemoSetupView: View {
    @ObservedObject var demo: DemoSession
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasAccessibility = AccessibilityService.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Demo Setup").font(.headline)
            Text("Claude explores your app, records a walkthrough from what’s really there, then plays it back to check it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Anthropic API key").font(.callout.weight(.medium))
                    Spacer()
                    if demo.hasKey {
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    SecureField(demo.hasKey ? "Replace saved key" : "Paste your API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            demo.saveKey(key)
                            key = ""
                        }
                    Button("Save") {
                        demo.saveKey(key)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if demo.hasKey {
                    Button("Remove saved key") { demo.saveKey("") }
                        .font(.caption)
                }
            }
            Toggle("Allow Claude to see and control the selected window while building", isOn: $demo.allowsAI)
            Text(
                "Building sends your request, screenshots and control labels to Anthropic. BetterMeets then operates the app in the background through Accessibility while you watch the stage. It never pays, sends, deletes or enters passwords, and asks before anything unusual. Playing a checked demo runs on your Mac. Builds stop at $2. Your key stays in Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker("Playback speed", selection: $demo.playbackSpeed) {
                ForEach(DemoPlaybackSpeed.allCases) { Text($0.label).tag($0) }
            }
            .disabled(demo.prompter.followsVoice)
            .help(
                demo.prompter.followsVoice
                    ? "With Follow my voice, you set the pace: finish a line or say “next”."
                    : "Shortens pauses and silent steps. Every line still gets the time it takes to say it.")
            Toggle("Pause after each step", isOn: $demo.pausesAfterEachStep)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open presenter notes when playing", isOn: $demo.opensNotesWhenPlaying)
                Text("Share the BetterMeets window, not your whole screen, to keep your notes private.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Follow my voice", isOn: Binding(
                    get: { demo.prompter.followsVoice },
                    set: { demo.prompter.followsVoice = $0; demo.updateListening() }))
                Text("On by default: you set the pace. Each step moves on when you finish its line or say “next”; steps without a line wait for “next”. Your next word is highlighted as you read. Speech is recognized on this Mac and never saved or sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility access").font(.callout.weight(.medium))
                    Text("Needed to read the app and to click and type in it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if hasAccessibility {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Allow Access") { AccessibilityService.requestTrust() }
                }
            }
            if let message = demo.notice {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = AccessibilityService.isTrusted
        }
    }
}
