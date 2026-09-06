import AppKit

@MainActor
enum VoiceOnboarding {
    static func show() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Present with your voice"
        alert.informativeText =
            "Describe a control to highlight it, or say “click” or “open” to use it. "
            + "Conversational understanding is on automatically.\n\n"
            + "With an API key, voice commands send a screenshot of your shared window "
            + "and your spoken words to the model selected in Voice settings: "
            + "Anthropic or OpenAI. Without a key, commands stay on this Mac.\n\n"
            + "Use the Voice button to stop listening. Remove your API key in Voice "
            + "settings to stop using cloud understanding."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        alert.window.sharingType = .none
        NSApplication.shared.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
