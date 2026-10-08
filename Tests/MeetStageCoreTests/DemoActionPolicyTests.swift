import Foundation
import MeetStageCore
import Testing

@Suite("Demo action policy")
struct DemoActionPolicyTests {
    private func evaluate(_ action: DemoPolicyAction, prompt: String = "", startHost: String? = nil, approved: Bool = false)
        -> DemoPolicyDecision
    {
        DemoActionPolicy.evaluate(action, prompt: prompt, startHost: startHost, approved: approved)
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
        #expect(evaluate(.type(field: search, text: "The Matrix", submit: true), prompt: "Search for The Matrix") == .allow)
        guard case .needsApproval = evaluate(.type(field: search, text: "Inception", submit: false), prompt: "Search")
        else {
            Issue.record("Expected an approval request")
            return
        }
        let password = DemoPolicyElement(kind: .field, label: "Password", isSecure: true)
        guard case .deny = evaluate(.type(field: password, text: "x", submit: false), prompt: "x", approved: true) else {
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
        guard case .needsApproval = evaluate(.navigate(other), prompt: "Show the dashboard", startHost: "subtis.io") else {
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
        guard case .deny = evaluate(.type(field: field, text: "hi\r", submit: false), prompt: "hi", approved: true) else {
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
}
