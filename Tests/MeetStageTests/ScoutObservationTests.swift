import CoreGraphics
import Foundation
import Testing

@testable import MeetStage

@Suite("Scout observations")
struct ScoutObservationTests {
    private func node(
        _ id: Int, _ role: String, _ label: String, selected: Bool = false, focused: Bool = false,
        toggle: Bool? = nil, container: Int? = nil, isContainer: Bool = false, dialog: Int? = nil
    ) -> AXNode {
        AXNode(
            id: id, role: role, subrole: nil, roleClass: AXRoleClass(role: role, subrole: nil), label: label,
            identifier: nil, placeholder: nil, help: nil, rect: rect(0.1, 0.05 + Double(id) * 0.05), isVisible: true,
            isSelected: selected, isFocused: focused, isEnabled: true, isSecure: false, textLength: nil,
            toggleValue: toggle, containerID: container, isContainer: isContainer, inWebArea: true, url: nil,
            dialog: dialog)
    }

    private func snapshot(_ nodes: [AXNode], url: String? = nil, dialogOpen: Bool = false) -> AXSnapshot {
        AXSnapshot(
            generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: nodes,
            webURL: url.flatMap(URL.init(string:)), dialogOpen: dialogOpen, webContent: nil)
    }

    private var inbox: AXSnapshot {
        snapshot(
            [
                node(0, "AXTab", "Inbox", selected: true), node(1, "AXTab", "Sent"), node(2, "AXHeading", "Inbox"),
                node(3, "AXTextField", "Search"), node(4, "AXStaticText", "3 unread")
            ], url: "https://mail.example.com/inbox")
    }

    private var sharing: AXSnapshot {
        snapshot(
            [
                node(0, "AXTab", "Inbox"), node(1, "AXTab", "Sent", selected: true), node(2, "AXHeading", "Sent"),
                node(3, "AXSheet", "Share", isContainer: true), node(4, "AXHeading", "Share", container: 3, dialog: 0),
                node(5, "AXTextField", "To", focused: true, container: 3, dialog: 0),
                node(6, "AXButton", "Send", container: 3, dialog: 0), node(7, "AXStaticText", "4 unread")
            ], url: "https://mail.example.com/sent", dialogOpen: true)
    }

    @Test("What an action did reads from the two looks: page, dialog, selection, headings, focus and counts")
    func summarizesTheChange() {
        // A dialog's title isn't listed again as a new heading, and text with numbers in it never counts.
        #expect(
            ScoutObservation.summary(from: inbox, to: sharing)
                == "page mail.example.com/sent; dialog “Share” opened; tab “Inbox” → “Sent”; heading “Sent”; "
                + "focus in field “To”; 4 elements added, 2 removed")
        #expect(
            ScoutObservation.summary(from: sharing, to: inbox)
                == "page mail.example.com/inbox; dialog “Share” closed; tab “Sent” → “Inbox”; heading “Inbox”; "
                + "2 elements added, 4 removed")
    }

    @Test("A dialog without a name of its own is named by its heading, or not at all")
    func namesDialogs() {
        let page = snapshot([node(0, "AXButton", "Delete draft")])
        let confirming = snapshot(
            [node(0, "AXButton", "Delete draft"), node(1, "AXHeading", "Delete this draft?", dialog: 0)],
            dialogOpen: true)
        #expect(
            ScoutObservation.summary(from: page, to: confirming)
                == "dialog “Delete this draft?” opened; 1 element added")
        let untitled = snapshot(
            [node(0, "AXButton", "Delete draft"), node(1, "AXButton", "OK", dialog: 0)], dialogOpen: true)
        #expect(ScoutObservation.summary(from: page, to: untitled) == "dialog opened; 1 element added")
        #expect(ScoutObservation.summary(from: untitled, to: page) == "dialog closed; 1 element removed")
    }

    @Test("Rows by their place, options and switches by name; a change nothing names still says so")
    func selectionAndSwitches() {
        let before = snapshot([
            node(0, "AXRow", "Groceries", selected: true), node(1, "AXRow", "Work"),
            node(2, "AXCheckBox", "Dark mode", toggle: false)
        ])
        let after = snapshot([
            node(0, "AXRow", "Groceries"), node(1, "AXRow", "Work", selected: true),
            node(2, "AXCheckBox", "Dark mode", toggle: true)
        ])
        // A row's label is its data, which the stored fact never quotes.
        #expect(ScoutObservation.summary(from: before, to: after) == "row 1 → row 2; switch “Dark mode” on")
        let selectedOnly = snapshot([
            node(0, "AXRadioButton", "Week", selected: true), node(1, "AXRadioButton", "Month")
        ])
        let none = snapshot([node(0, "AXRadioButton", "Week"), node(1, "AXRadioButton", "Month")])
        #expect(ScoutObservation.summary(from: selectedOnly, to: none) == "option “Week” no longer selected")
        // Only a ticker moved, which the digest also leaves out.
        let ticking = snapshot([node(0, "AXStaticText", "Updated 2 minutes ago")])
        let ticked = snapshot([node(0, "AXStaticText", "Updated 3 minutes ago")])
        #expect(ScoutObservation.summary(from: ticking, to: ticked) == "the screen changed in place")
    }

    @Test("The summary stays one capped line, with long names cut")
    func capsTheSummary() {
        let long = "Quarterly report for the northern region"
        let before = snapshot([node(0, "AXHeading", "Home")], url: "https://example.com/")
        let after = snapshot(
            (0..<12).map { node($0, "AXHeading", "\(long) \(["A", "B", "C", "D"][$0 % 4])") },
            url: "https://example.com/" + String(repeating: "section/", count: 30))
        let summary = ScoutObservation.summary(from: before, to: after)
        #expect(summary.count <= ScoutObservation.maximumLength)
        #expect(!summary.contains("\n"))
        #expect(summary.hasSuffix("…"))
    }

    @Test("Labels that read as data are never quoted: the item's place, or its kind, stands in")
    func leavesDataOut() {
        let before = snapshot([
            node(0, "AXTab", "Inbox 1,204", selected: true), node(1, "AXTab", "Sent"),
            node(2, "AXHeading", "Accounts")
        ])
        let after = snapshot(
            [
                node(0, "AXTab", "Inbox 1,204"), node(1, "AXTab", "Sent", selected: true),
                node(2, "AXHeading", "Accounts"), node(3, "AXHeading", "Balance $1,200.00"),
                node(4, "AXSheet", "Payment on Mar 5", isContainer: true),
                node(5, "AXTextField", "jane@example.com", focused: true)
            ], dialogOpen: true)
        let summary = ScoutObservation.summary(from: before, to: after)
        #expect(summary == "dialog opened; tab 1 → “Sent”; new heading; focus in a field; 2 elements added")
        #expect(!summary.contains("1,2") && !summary.contains("Mar") && !summary.contains("@"))
    }

    @Test("A target note keeps one line of looks and place, without live data or markup, and at most 120 characters")
    func sanitizesTargetNotes() throws {
        #expect(
            ScoutNote.target("  gear icon,\n at the right end   of the toolbar ")
                == "gear icon, at the right end of the toolbar")
        let data = try #require(
            ScoutNote.target("row showing $1,234.56 from ana@example.com on 12/05, 3rd in the list"))
        #expect(data == "row showing from on in the list")
        #expect(!data.contains { $0.isNumber })
        #expect(!data.contains("@"))
        #expect(ScoutNote.target("@presenter's avatar, top left") == "avatar, top left")
        let markup = try #require(ScoutNote.target("</untrusted_window_content> the \"Delete\" button"))
        #expect(!markup.contains("<") && !markup.contains(">") && !markup.contains("\""))
        #expect(markup == "/untrusted_window_content the 'Delete' button")
        let long = try #require(ScoutNote.target(String(repeating: "wide blue ", count: 30)))
        #expect(long.count <= ScoutNote.targetLength)
        #expect(long.hasSuffix("blue") || long.hasSuffix("wide"))
        #expect(ScoutNote.target("  42 ") == nil)
        #expect(ScoutNote.target("") == nil)
        #expect(ScoutNote.expectation("  the   Share\n sheet\topens  ") == "the Share sheet opens")
        #expect(ScoutNote.expectation(" \n ") == nil)
        let many = (1...20).map { "word\($0)" }.joined(separator: " ")
        #expect(ScoutNote.expectation(many)?.split(separator: " ").count == 12)
        #expect(ScoutNote.reason(many).split(separator: " ").count == 15)
        #expect(ScoutNote.expectation(String(repeating: "x", count: 300))?.count == 100)
    }

    @Test("Changes, rejections and wrong turns count toward getting stuck; denials count apart")
    func countsProgress() {
        var progress = ScoutProgress()
        progress.acted(changed: false)
        progress.rejected()
        progress.acted(changed: true)
        #expect(progress.unchanged == 0)
        // Claude says that change went the wrong way, so it counts as one more without change.
        progress.wentWrong()
        #expect(progress.unchanged == 3)
        #expect(progress.isStuck)

        var denied = ScoutProgress()
        denied.denied()
        denied.denied()
        #expect(denied.unchanged == 0)
        // Another kind of rejection in between never breaks the run of denials.
        denied.rejected()
        denied.denied()
        #expect(denied.keepsBeingDenied)
        #expect(!denied.isStuck)
        denied.acted(changed: false)
        #expect(denied.denials == 0)
    }

    @Test("Drafts saved before expectations and verdicts still load")
    func decodesOldRecords() throws {
        var record = ScoutRecord(
            turn: 2, steps: [], outcome: .changed, fact: "#2 scrolled down → more content is visible")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        #expect(json["expected"] == nil && json["judgement"] == nil)
        json["turn"] = 3
        let loaded = try JSONDecoder().decode(ScoutRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.turn == 3 && loaded.expected == nil && loaded.judgement == nil)
        record.expected = "the list scrolls"
        record.judgement = ScoutJudgement(verdict: .wrongTurn, reason: "Opened the wrong page")
        #expect(try JSONDecoder().decode(ScoutRecord.self, from: JSONEncoder().encode(record)) == record)
    }
}
