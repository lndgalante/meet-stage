import Foundation
import MeetStageCore
import Testing

@Suite("Demo action policy")
struct DemoActionPolicyTests {
    private func evaluate(
        _ action: DemoPolicyAction, prompt: String = "", startHost: String? = nil, approved: Bool = false,
        trusted: Bool = false
    ) -> DemoPolicyDecision {
        DemoActionPolicy.evaluate(action, prompt: prompt, startHost: startHost, approved: approved, appTrusted: trusted)
    }

    /// The kind of question an action asks, or nil when it's allowed or denied.
    private func kind(_ action: DemoPolicyAction, prompt: String = "", startHost: String? = nil) -> DemoApproval.Kind? {
        guard case .needsApproval(let approval) = evaluate(action, prompt: prompt, startHost: startHost) else {
            return nil
        }
        return approval.kind
    }

    private func isDenied(_ action: DemoPolicyAction) -> Bool {
        if case .deny = evaluate(action) { return true }
        return false
    }

    private func click(_ kind: DemoPolicyElement.Kind, _ label: String, details: [String] = []) -> DemoPolicyAction {
        .click(DemoPolicyElement(kind: kind, label: label, details: details))
    }

    private func dialogButton(_ label: String, text: [String]) -> DemoPolicyAction {
        .click(DemoPolicyElement(kind: .button, label: label, inDialog: true, dialogText: text))
    }

    @Test("Ordinary navigation is allowed")
    func allowsNavigation() {
        #expect(evaluate(.click(DemoPolicyElement(kind: .link, label: "Transactions"))) == .allow)
        #expect(evaluate(.click(DemoPolicyElement(kind: .checkbox, label: "Discreet mode"))) == .allow)
        #expect(evaluate(.pressKey) == .allow)
    }

    @Test("Destructive buttons are denied; destructive navigation asks first")
    func destructiveControls() {
        guard case .deny = evaluate(.click(DemoPolicyElement(kind: .button, label: "Delete account"))) else {
            Issue.record("Expected a denial")
            return
        }
        guard case .deny = evaluate(.click(DemoPolicyElement(kind: .button, label: "Confirm payment"))) else {
            Issue.record("Expected a denial")
            return
        }
        guard case .needsApproval = evaluate(.click(DemoPolicyElement(kind: .link, label: "Send"))) else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(evaluate(.click(DemoPolicyElement(kind: .link, label: "Send")), approved: true) == .allow)
        // Approval never overrides a denial.
        guard case .deny = evaluate(.click(DemoPolicyElement(kind: .button, label: "Delete")), approved: true) else {
            Issue.record("Expected a denial")
            return
        }
    }

    @Test("Data rows are judged by their details, not their text")
    func rows() {
        let row = DemoPolicyElement(kind: .row, label: "Sent 0.1 BTC to Swap Inc", labelIsData: true)
        #expect(evaluate(.click(row)) == .allow)
    }

    @Test("Typing needs a text field, never a secret one, and text from the request")
    func typing() {
        let search = DemoPolicyElement(kind: .field, label: "Buscar película")
        #expect(
            evaluate(.type(field: search, text: "The Matrix", submit: true), prompt: "Search for The Matrix") == .allow)
        guard case .needsApproval = evaluate(.type(field: search, text: "Inception", submit: false), prompt: "Search")
        else {
            Issue.record("Expected an approval request")
            return
        }
        let password = DemoPolicyElement(kind: .field, label: "Password", isSecure: true)
        guard case .deny = evaluate(.type(field: password, text: "x", submit: false), prompt: "x", approved: true)
        else {
            Issue.record("Expected a denial")
            return
        }
        let seed = DemoPolicyElement(kind: .field, label: "Recovery phrase")
        guard case .deny = evaluate(.type(field: seed, text: "abc", submit: false), prompt: "abc") else {
            Issue.record("Expected a denial")
            return
        }
        let comment = DemoPolicyElement(kind: .field, label: "Comment")
        guard case .needsApproval = evaluate(.type(field: comment, text: "hi", submit: true), prompt: "hi") else {
            Issue.record("Return outside a search field needs approval")
            return
        }
    }

    @Test("Pages open only on the start site or a site the request names")
    func navigation() throws {
        let start = try #require(URL(string: "https://subtis.io/movie/603"))
        #expect(evaluate(.navigate(start), startHost: "subtis.io") == .allow)
        let named = try #require(URL(string: "https://www.youtube.com/"))
        #expect(evaluate(.navigate(named), prompt: "Open youtube.com and search") == .allow)
        let other = try #require(URL(string: "https://evil.example/?q=balance"))
        guard case .needsApproval = evaluate(.navigate(other), prompt: "Show the dashboard", startHost: "subtis.io")
        else {
            Issue.record("Expected an approval request")
            return
        }
        let file = try #require(URL(string: "file:///etc/passwd"))
        guard case .deny = evaluate(.navigate(file), approved: true) else {
            Issue.record("Expected a denial")
            return
        }
    }

    @Test("Line breaks and tabs never reach a field as live keys")
    func controlCharacters() {
        let field = DemoPolicyElement(kind: .field, label: "Message")
        guard case .deny = evaluate(.type(field: field, text: "hi\r", submit: false), prompt: "hi", approved: true)
        else {
            Issue.record("Expected a denial")
            return
        }
    }

    @Test("Dialog buttons other than dismissals ask first")
    func dialogs() {
        let yes = DemoPolicyElement(kind: .button, label: "Yes", inDialog: true)
        guard case .needsApproval = evaluate(.click(yes)) else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(evaluate(.click(DemoPolicyElement(kind: .button, label: "Cancel", inDialog: true))) == .allow)
    }

    @Test("Localized destructive buttons are denied")
    func localized() {
        guard case .deny = evaluate(.click(DemoPolicyElement(kind: .button, label: "Eliminar cuenta"))) else {
            Issue.record("Expected a denial")
            return
        }
        #expect(evaluate(.click(DemoPolicyElement(kind: .button, label: "Buscar película"))) == .allow)
    }

    @Test("Only hosts written in the request count, not their substrings")
    func exactHosts() throws {
        let partial = try #require(URL(string: "https://hub.com/data"))
        guard case .needsApproval = evaluate(.navigate(partial), prompt: "Show my repos on github.com") else {
            Issue.record("Expected an approval request")
            return
        }
        let named = try #require(URL(string: "https://docs.github.com/en"))
        #expect(evaluate(.navigate(named), prompt: "Show my repos on github.com") == .allow)
    }

    @Test("Each question says what kind it is, and keeps the words a step records")
    func approvalKinds() throws {
        let field = DemoPolicyElement(kind: .field, label: "Comment")
        let search = DemoPolicyElement(kind: .field, label: "Search")
        #expect(
            evaluate(click(.link, "Sign out"))
                == .needsApproval(DemoApproval(.riskyLink, "Open “Sign out”? It mentions “sign out”.")))
        #expect(kind(click(.menuItem, "Delete")) == .riskyMenuItem)
        #expect(kind(dialogButton("OK", text: ["Save your changes?"])) == .dialogButton)
        #expect(kind(dialogButton("OK", text: ["Delete this transaction?"])) == .riskyDialogButton)
        #expect(
            evaluate(click(.button, ""))
                == .needsApproval(DemoApproval(.unlabelledControl, "Click an unlabelled control?")))
        #expect(
            evaluate(.type(field: field, text: "hi", submit: true), prompt: "hi")
                == .needsApproval(DemoApproval(.returnOutsideSearch, "Type “hi” and press Return in “Comment”?")))
        #expect(
            evaluate(.type(field: search, text: "Inception", submit: true), prompt: "Search for a movie")
                == .needsApproval(DemoApproval(.unrequestedText, "Type “Inception” into “Search”?")))
        // Return outside a search field asks first, even when the text isn't from the request either.
        #expect(kind(.type(field: field, text: "Inception", submit: true)) == .returnOutsideSearch)
        let offSite = try #require(URL(string: "https://evil.example/"))
        #expect(evaluate(.navigate(offSite)) == .needsApproval(DemoApproval(.unknownHost, "Open evil.example?")))
        let query = try #require(URL(string: "https://subtis.io/search?q=balance"))
        #expect(
            evaluate(.navigate(query), startHost: "subtis.io")
                == .needsApproval(DemoApproval(.unrequestedQuery, "Open subtis.io?")))
    }

    @Test("Trusting the app answers ordinary questions, never risky ones or denials")
    func trustCoverage() throws {
        let covered: [DemoApproval.Kind] = [.dialogButton, .unlabelledControl, .unrequestedText, .unrequestedQuery]
        let uncovered: [DemoApproval.Kind] = [
            .riskyLink, .riskyMenuItem, .riskyDialogButton, .returnOutsideSearch, .unknownHost
        ]
        #expect(covered.allSatisfy { $0.isCoveredByTrust })
        #expect(!uncovered.contains { $0.isCoveredByTrust })

        let search = DemoPolicyElement(kind: .field, label: "Search")
        let comment = DemoPolicyElement(kind: .field, label: "Comment")
        let query = try #require(URL(string: "https://subtis.io/search?q=inception"))
        let named = try #require(URL(string: "https://www.youtube.com/results?search_query=cats"))
        let offSite = try #require(URL(string: "https://evil.example/?q=balance"))
        // Covered: each passes in a trusted app and still asks in any other.
        let ordinary: [(DemoPolicyAction, String?)] = [
            (dialogButton("Continue", text: ["Add a transaction"]), nil),
            (click(.button, ""), nil),
            (.type(field: search, text: "Inception", submit: true), nil),
            (.navigate(query), "subtis.io"),
            (.navigate(named), nil)
        ]
        for (action, start) in ordinary {
            #expect(
                evaluate(action, prompt: "Open youtube.com", startHost: start, trusted: true) == .allow, "\(action)")
            #expect(kind(action, prompt: "Open youtube.com", startHost: start) != nil, "\(action)")
        }
        // Not covered: still asks in a trusted app.
        let risky: [DemoPolicyAction] = [
            click(.link, "Delete account"),
            click(.link, "Sign out"),
            click(.menuItem, "Delete"),
            dialogButton("OK", text: ["Delete this transaction?"]),
            dialogButton("Continue", text: ["Enter your password to continue"]),
            .type(field: comment, text: "hi", submit: true),
            .navigate(offSite)
        ]
        for action in risky {
            guard case .needsApproval = evaluate(action, startHost: "subtis.io", trusted: true) else {
                Issue.record("Expected an approval request for \(action)")
                continue
            }
        }
        // Denials stay denials.
        let password = DemoPolicyElement(kind: .field, label: "Password", isSecure: true)
        #expect(isDenied(click(.button, "Delete account")))
        guard case .deny = evaluate(.type(field: password, text: "x", submit: false), prompt: "x", trusted: true) else {
            Issue.record("Expected a denial")
            return
        }
        guard case .deny = evaluate(click(.button, "Send"), approved: true, trusted: true) else {
            Issue.record("Expected a denial")
            return
        }
    }

    @Test("Destructive words count only at the start of a word, including identifiers")
    func anchoredStems() {
        #expect(evaluate(click(.button, "Presets")) == .allow)
        #expect(evaluate(click(.button, "Mistakes")) == .allow)
        #expect(evaluate(click(.button, "Hotswap guide")) == .allow)
        #expect(isDenied(click(.button, "Reset")))
        #expect(isDenied(click(.button, "Factory reset")))
        // A prefix doesn't hide the action.
        #expect(isDenied(click(.button, "Unstake")))
        #expect(isDenied(click(.button, "Resubmit")))
        #expect(isDenied(click(.button, "Resend code")))
        // Identifiers are split into words first.
        #expect(isDenied(click(.button, "", details: ["btnDeleteAccount"])))
        #expect(isDenied(click(.button, "", details: ["action_delete"])))
        #expect(isDenied(click(.button, "", details: ["delete-button"])))
    }

    @Test("Localized destructive words count at a word start, and German ones inside words")
    func localizedStems() {
        #expect(isDenied(click(.button, "Cerrar sesión")))
        #expect(isDenied(click(.button, "Transferir dinero")))
        #expect(isDenied(click(.button, "Supprimer le compte")))
        #expect(isDenied(click(.button, "Acquista ora")))
        #expect(isDenied(click(.button, "Paga")))
        // German joins verbs to prefixes, so its stems match anywhere.
        #expect(isDenied(click(.button, "Absenden")))
        #expect(isDenied(click(.button, "Aktie verkaufen")))
        #expect(isDenied(click(.button, "Konto löschen")))
        // Another word that merely contains a stem doesn't count.
        #expect(evaluate(click(.button, "Reenviar más tarde")) == .allow)
        #expect(evaluate(click(.button, "Pagamentos")) == .allow)
    }

    @Test("Tabs that sound destructive open without asking")
    func destructiveTabs() {
        #expect(evaluate(click(.tab, "Deleted")) == .allow)
        #expect(evaluate(click(.tab, "Send")) == .allow)
        #expect(evaluate(click(.tab, "Transfers")) == .allow)
        // Inside a dialog, a tab is still one of its controls.
        #expect(kind(.click(DemoPolicyElement(kind: .tab, label: "Delete", inDialog: true))) == .riskyDialogButton)
    }

    @Test("Links that name a list or a state open; links that name an action still ask")
    func destructiveLinks() {
        for label in [
            "Confirmed", "Approved", "Submitted", "Published", "Deleted", "Transfers", "Swaps", "Purchases",
            "Withdrawals", "Confirmations", "Unconfirmed", "Staked", "Swapped", "Transferred"
        ] {
            #expect(evaluate(click(.link, label)) == .allow, "\(label)")
        }
        for label in ["Delete account", "Sign out", "Log out", "Send", "Swap", "Transfer funds", "Deleted · Delete all"]
        {
            #expect(kind(click(.link, label)) == .riskyLink, "\(label)")
        }
        // A verb anywhere in the link's words asks, and names that verb.
        #expect(
            evaluate(click(.link, "Confirmed · Delete"))
                == .needsApproval(DemoApproval(.riskyLink, "Open “Confirmed · Delete”? It mentions “delete”.")))
        // Menu items keep asking, whatever the form.
        #expect(kind(click(.menuItem, "Deleted Items")) == .riskyMenuItem)
        // Buttons are still denied.
        #expect(isDenied(click(.button, "Confirmed")))
    }

    @Test("A dialog's own text decides only whether trust can answer for it")
    func dialogText() {
        #expect(kind(dialogButton("OK", text: ["Rename", "New name"])) == .dialogButton)
        #expect(
            kind(dialogButton("OK", text: ["Delete this transaction?", "This can’t be undone."])) == .riskyDialogButton)
        #expect(kind(dialogButton("Continue", text: ["Enter your password"])) == .riskyDialogButton)
        #expect(kind(dialogButton("Next", text: ["Write down your recovery phrase"])) == .riskyDialogButton)
        // A confirmation that doesn't say what it confirms isn't harmless either.
        #expect(kind(dialogButton("OK", text: ["Are you sure?"])) == .riskyDialogButton)
        #expect(kind(dialogButton("Sí", text: ["¿Estás seguro?"])) == .riskyDialogButton)
        #expect(kind(dialogButton("OK", text: ["This can’t be undone."])) == .riskyDialogButton)
        // A dialog whose text couldn't be read isn't taken as harmless.
        #expect(kind(dialogButton("OK", text: [])) == .riskyDialogButton)
        #expect(kind(dialogButton("OK", text: ["", ""])) == .riskyDialogButton)
        // A destructive link in such a dialog isn't answered by trust either.
        let link = DemoPolicyElement(
            kind: .link, label: "Delete account", inDialog: true, dialogText: ["Delete your account?"])
        #expect(kind(.click(link)) == .riskyDialogButton)
        // Harmless text never allows anything without trust, and dismissals stay allowed.
        guard case .needsApproval = evaluate(dialogButton("OK", text: ["Rename"])) else {
            Issue.record("Expected an approval request")
            return
        }
        #expect(evaluate(dialogButton("Cancel", text: ["Delete this transaction?"])) == .allow)
        #expect(isDenied(dialogButton("Delete", text: ["Rename"])))
    }
}
