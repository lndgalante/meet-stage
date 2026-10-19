import CoreGraphics
import Foundation
import Testing

@testable import MeetStage

@Suite("Demo matching")
struct DemoMatchingTests {
    private func node(
        _ id: Int, _ role: String, _ label: String, _ r: NormRect, container: Int? = nil, isContainer: Bool = false,
        identifier: String? = nil, selected: Bool = false, visible: Bool = true
    ) -> AXNode {
        AXNode(
            id: id, role: role, subrole: nil, roleClass: AXRoleClass(role: role, subrole: nil), label: label,
            identifier: identifier, placeholder: nil, help: nil, rect: r, isVisible: visible, isSelected: selected,
            isFocused: false, isEnabled: true, isSecure: false, textLength: nil, toggleValue: nil, containerID: container,
            isContainer: isContainer, inWebArea: true, url: nil)
    }

    private func snapshot(_ nodes: [AXNode], url: String? = nil) -> AXSnapshot {
        AXSnapshot(
            generation: 1, windowFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), nodes: nodes,
            webURL: url.flatMap(URL.init(string:)), dialogOpen: false, webContent: nil)
    }

    @Test("Data labels are unstable; control names are stable")
    func labelStability() {
        #expect(LabelStability.isStable(roleClass: .link, label: "Transactions"))
        #expect(LabelStability.isStable(roleClass: .field, label: "Buscar película"))
        #expect(!LabelStability.isStable(roleClass: .button, label: "$1,204.55"))
        #expect(!LabelStability.isStable(roleClass: .link, label: "The Matrix (1999)"))
        #expect(!LabelStability.isStable(roleClass: .button, label: "2 min ago"))
        #expect(!LabelStability.isStable(roleClass: .row, label: "Settings"))
        #expect(LabelStability.isStableIdentifier("sidebar-transactions"))
        #expect(!LabelStability.isStableIdentifier(":r3:"))
        #expect(!LabelStability.isStableIdentifier("radix-12"))
    }

    @Test("Stable labels match by text, scoped to their container")
    func matchesStableLabels() {
        let nodes = [
            node(0, "AXGroup", "Sidebar", rect(0, 0, 0.2, 1), isContainer: true),
            node(1, "AXLink", "Transactions", rect(0.02, 0.3), container: 0),
            node(2, "AXGroup", "Main", rect(0.2, 0, 0.8, 1), isContainer: true),
            node(3, "AXLink", "Transactions", rect(0.5, 0.1), container: 2),
        ]
        let scene = snapshot(nodes)
        let locator = DemoLocatorFactory.locator(for: 1, in: scene)
        #expect(locator?.container?.label == "sidebar")
        #expect(locator.map { DemoLocatorMatcher.match($0, in: scene) } == .unique(1))
    }

    @Test("Identical controls without a container are ambiguous unless one is clearly nearest")
    func ambiguityFailsClosed() {
        let a = node(0, "AXButton", "Edit", rect(0.1, 0.1))
        let b = node(1, "AXButton", "Edit", rect(0.1, 0.14))
        let locator = DemoElementLocator(role: "AXButton", label: "Edit", labelIsStable: true, rect: rect(0.1, 0.12))
        #expect(DemoLocatorMatcher.match(locator, in: snapshot([a, b])) == .ambiguous)
        let near = DemoElementLocator(role: "AXButton", label: "Edit", labelIsStable: true, rect: rect(0.1, 0.1))
        #expect(DemoLocatorMatcher.match(near, in: snapshot([a, b])) == .unique(0))
    }

    @Test("Data rows are found by visual order, never by their text")
    func matchesRowsByPosition() {
        let table: (String, String) -> [AXNode] = { first, second in
            [
                self.node(0, "AXTable", "Operations", rect(0.2, 0.2, 0.7, 0.7), isContainer: true),
                // Tree order differs from visual order.
                self.node(1, "AXRow", second, rect(0.2, 0.36, 0.7, 0.05), container: 0),
                self.node(2, "AXRow", first, rect(0.2, 0.3, 0.7, 0.05), container: 0),
            ]
        }
        let recorded = snapshot(table("Received 0.5 BTC", "Sent 0.1 BTC"))
        let locator = DemoLocatorFactory.locator(for: 2, in: recorded)
        #expect(locator?.label == "")
        #expect(locator?.visualIndex == 0)
        let later = snapshot(table("Received 2 ETH", "Swap 10 USDC"))
        #expect(locator.map { DemoLocatorMatcher.match($0, in: later) } == .unique(2))
    }

    @Test("Count badges don't change a control's identity; generated IDs are ignored")
    func badgesAndGeneratedIDs() {
        #expect(LabelStability.matchKey("Inbox 3") == LabelStability.matchKey("Inbox (12)"))
        #expect(LabelStability.isStable(roleClass: .tab, label: "Pull requests 2"))
        #expect(!LabelStability.isStable(roleClass: .button, label: "Mar 5"))
        #expect(!LabelStability.isStable(roleClass: .button, label: "5%"))
        #expect(!LabelStability.isStableIdentifier("«r5»"))
        #expect(!LabelStability.isStableIdentifier("mat-input-4"))
        #expect(ScreenSignatures.urlKey(URL(string: "file:///app/index.html#?")) == nil)
        let tab = node(0, "AXRadioButton", "Inbox 4", rect(0.1, 0.1))
        let locator = DemoElementLocator(role: "AXRadioButton", label: "Inbox 3", labelIsStable: true, rect: rect(0.1, 0.1))
        #expect(DemoLocatorMatcher.match(locator, in: snapshot([tab])) == .unique(0))
    }

    @Test("A data row found by position must be near where it was recorded")
    func rowsMustBeNearby() {
        let recorded = DemoElementLocator(
            role: "AXRow", label: "", labelIsStable: false,
            container: ContainerKey(role: "AXTable", subrole: nil, label: "operations"), visualIndex: 0,
            rect: rect(0.2, 0.8, 0.7, 0.05))
        let table = [
            node(0, "AXTable", "Operations", rect(0.2, 0.1, 0.7, 0.8), isContainer: true),
            node(1, "AXRow", "Received", rect(0.2, 0.12, 0.7, 0.05), container: 0),
        ]
        #expect(DemoLocatorMatcher.match(recorded, in: snapshot(table)) == .none)
    }

    @Test("An unlabelled icon button is found where it was, never by its order on the page")
    func unlabelledButtonsByLocation() throws {
        let web = node(0, "AXWebArea", "", rect(0, 0, 1, 1), isContainer: true)
        let close = node(3, "AXButton", "", rect(0.972, 0.024, 0.011, 0.014), container: 0)
        let recordedScene = snapshot([web, node(1, "AXButton", "", rect(0.95, 0.05, 0.03, 0.04), container: 0), close])
        let locator = try #require(DemoLocatorFactory.locator(for: 3, in: recordedScene))
        #expect(locator.visualIndex == nil)

        // Another button now comes first in visual order; the close button is still found.
        let later = snapshot([
            web, node(1, "AXButton", "", rect(0.5, 0.01, 0.03, 0.03), container: 0),
            node(2, "AXButton", "", rect(0.95, 0.05, 0.03, 0.04), container: 0), close,
        ])
        #expect(DemoLocatorMatcher.match(locator, in: later) == .unique(3))

        // With the panel closed, a nearby top-bar button must not stand in for it.
        let closed = snapshot([web, node(2, "AXButton", "", rect(0.95, 0.05, 0.03, 0.04), container: 0)])
        #expect(DemoLocatorMatcher.match(locator, in: closed) == .none)
    }

    @Test("An icon button saved unlabelled is still found once it borrows a name, and new builds name it")
    func oldLocatorsFindBorrowedNames() throws {
        let web = node(0, "AXWebArea", "", rect(0, 0, 1, 1), isContainer: true)
        let close = node(1, "AXButton", "", rect(0.972, 0.024, 0.011, 0.014), container: 0)
        let saved = try #require(DemoLocatorFactory.locator(for: 1, in: snapshot([web, close])))
        #expect(saved.label.isEmpty)
        #expect(!saved.labelIsStable)

        // The same button now borrows its help text, and another one borrows a name too.
        var named = close
        named.label = "Close panel"
        named.labelIsBorrowed = true
        var other = node(2, "AXButton", "Share", rect(0.5, 0.024, 0.011, 0.014), container: 0)
        other.labelIsBorrowed = true
        let live = snapshot([web, named, other])
        #expect(DemoLocatorMatcher.match(saved, in: live) == .unique(1))

        // A new build records the borrowed name, and finds it by that.
        let recorded = try #require(DemoLocatorFactory.locator(for: 1, in: live))
        #expect(recorded.labelIsStable)
        #expect(recorded.label == "Close panel")
        #expect(DemoLocatorMatcher.match(recorded, in: live) == .unique(1))
    }

    @Test("A control's own label outranks a name another control borrows")
    func ownLabelsOutrankBorrowedOnes() throws {
        // Saved where the button sat then; it has since moved up a little.
        let saved = DemoElementLocator(role: "AXButton", label: "Share", labelIsStable: true, rect: rect(0.5, 0.08))
        let share = node(0, "AXButton", "Share", rect(0.5, 0.05))
        // An icon button as close the other way now borrows the same name from its help text.
        var icon = node(1, "AXButton", "Share", rect(0.5, 0.11))
        icon.labelIsBorrowed = true
        let live = snapshot([share, icon])
        #expect(DemoLocatorMatcher.match(saved, in: live) == .unique(0))
        // The icon can't be found by a name the other owns, so it's recorded where it sits, as before.
        let iconLocator = try #require(DemoLocatorFactory.locator(for: 1, in: live))
        #expect(!iconLocator.labelIsStable)
        #expect(DemoLocatorMatcher.match(iconLocator, in: live) == .unique(1))
    }

    @Test("Screen signatures leave out borrowed names, so they read as they did before them")
    func signaturesSkipBorrowedNames() {
        var icon = node(0, "AXRadioButton", "Grid view", rect(0.02, 0.05), selected: true)
        icon.labelIsBorrowed = true
        let tab = node(1, "AXRadioButton", "Library", rect(0.1, 0.05), selected: true)
        #expect(ScreenSignatures.make(snapshot([icon, tab])).selected == ["library"])
    }

    @Test("Position matches stay in their container: a closed panel's button never becomes a top-bar button")
    func positionStaysInContainer() throws {
        let web = node(0, "AXWebArea", "", rect(0, 0, 1, 1), isContainer: true)
        let bar = node(1, "AXGroup", "Top bar", rect(0.5, 0, 0.5, 0.08), isContainer: true)
        let close = node(3, "AXButton", "", rect(0.972, 0.024, 0.011, 0.014), container: 0)
        let locator = try #require(DemoLocatorFactory.locator(for: 3, in: snapshot([web, bar, close])))
        // The panel is closed; a top-bar button sits a few points from where the X was.
        let topBarButton = node(2, "AXButton", "", rect(0.97, 0.026, 0.012, 0.014), container: 1)
        #expect(DemoLocatorMatcher.match(locator, in: snapshot([web, bar, topBarButton])) == .none)
    }

    @Test("A target crowded by look-alikes is refused when recorded, so replay never guesses")
    func crowdedTargetsAreRefused() {
        let web = node(0, "AXWebArea", "", rect(0, 0, 1, 1), isContainer: true)
        let glyph = node(1, "AXStaticText", "$", rect(0.95, 0.3, 0.007, 0.014), container: 0)
        let value = node(2, "AXStaticText", "0.018", rect(0.96, 0.3, 0.02, 0.014), container: 0)
        #expect(DemoLocatorFactory.locator(for: 1, in: snapshot([web, glyph, value])) == nil)
    }

    @Test("Rows are read top to bottom, then left to right, whatever the tree order")
    func readingOrder() {
        let cells = [
            node(0, "AXCell", "b", rect(0.5, 0.101, 0.2, 0.03)),
            node(1, "AXCell", "c", rect(0.1, 0.2, 0.2, 0.03)),
            node(2, "AXCell", "a", rect(0.1, 0.1, 0.2, 0.03)),
        ]
        #expect(DemoLocatorMatcher.ordered(cells, in: snapshot(cells)).map(\.label) == ["a", "b", "c"])
    }

    @Test("Text captions match by words, and values by position when the words change")
    func textsMatchByWordsThenPosition() {
        let caption = DemoElementLocator(role: "AXStaticText", label: "Amount", labelIsStable: true, rect: rect(0.62, 0.3))
        // A different caption in that spot is a different field.
        #expect(DemoLocatorMatcher.match(caption, in: snapshot([node(0, "AXStaticText", "Total", rect(0.62, 0.3))])) == .none)
        // A value whose figures changed is still the value in that spot.
        let value = DemoElementLocator(role: "AXStaticText", label: "0.01 ETH", labelIsStable: true, rect: rect(0.9, 0.3))
        #expect(DemoLocatorMatcher.match(value, in: snapshot([node(0, "AXStaticText", "0.02 ETH", rect(0.9, 0.3))])) == .unique(0))
        #expect(LabelStability.isStable(roleClass: .text, label: "Amount"))
        #expect(!LabelStability.isStable(roleClass: .text, label: "-0.0000095 ETH"))
    }

    @Test("Stable identifiers win over labels")
    func identifiersWin() {
        let nodes = [
            node(0, "AXButton", "Save", rect(0.1, 0.1), identifier: "save-draft"),
            node(1, "AXButton", "Save", rect(0.5, 0.1), identifier: "save-final"),
        ]
        let locator = DemoLocatorFactory.locator(for: 1, in: snapshot(nodes))
        #expect(locator?.identifier == "save-final")
        #expect(locator.map { DemoLocatorMatcher.match($0, in: snapshot(nodes)) } == .unique(1))
    }

    @Test("Signatures use the URL until confirmed, then selected items and headings")
    func signatures() {
        let transactions = snapshot(
            [
                node(0, "AXLink", "Transactions", rect(0.02, 0.3), selected: true),
                node(1, "AXHeading", "Transactions", rect(0.3, 0.05)),
            ], url: "file:///app/index.html#/transactions?tab=all")
        let accounts = snapshot(
            [
                node(0, "AXLink", "Accounts", rect(0.02, 0.2), selected: true),
                node(1, "AXHeading", "Accounts", rect(0.3, 0.05)),
            ], url: "file:///app/index.html#/accounts")
        let recorded = ScreenSignatures.make(transactions)
        #expect(recorded.urlKey == "#/transactions")
        #expect(!ScreenSignatures.matches(recorded, live: ScreenSignatures.make(accounts)))
        var noURL = recorded
        noURL.urlKey = nil
        #expect(ScreenSignatures.matches(noURL, live: ScreenSignatures.make(accounts)))
        let confirmed = ScreenSignatures.confirm(noURL, with: ScreenSignatures.make(transactions))
        #expect(confirmed.confirmed)
        #expect(!ScreenSignatures.matches(confirmed, live: ScreenSignatures.make(accounts)))
        #expect(ScreenSignatures.matches(confirmed, live: ScreenSignatures.make(transactions)))
    }

    @Test("Fingerprints ignore words and timing but not actions or app version")
    func fingerprints() {
        let locator = DemoElementLocator(role: "AXLink", label: "Transactions", labelIsStable: true, rect: rect(0, 0))
        var demo = RealTimeDemo(
            prompt: "x", app: DemoAppKey(bundleID: "a", appName: "A", engine: .electron, isBrowser: false), title: "T",
            steps: [
                DemoStep(
                    title: "Open", script: "", holdSeconds: 1, action: .click(locator),
                    pre: ScreenSignature(selected: [], headings: [], dialogOpen: false))
            ], status: .recorded)
        let original = DemoFingerprint.make(demo, appVersion: "1", sizeClass: .regular)
        demo.steps[0].script = "Let's open it."
        demo.steps[0].holdSeconds = 4
        #expect(DemoFingerprint.make(demo, appVersion: "1", sizeClass: .regular) == original)
        #expect(DemoFingerprint.make(demo, appVersion: "2", sizeClass: .regular) != original)
        demo.steps[0].action = .press(.escape)
        #expect(DemoFingerprint.make(demo, appVersion: "1", sizeClass: .regular) != original)
    }

    @Test("Claude's note on a target never changes what identifies, matches or fingerprints it, and old demos load")
    func targetNotes() throws {
        let plain = DemoElementLocator(
            role: "AXButton", label: "", labelIsStable: false, rect: rect(0.9, 0.05, 0.03, 0.04))
        var noted = plain
        noted.note = "gear icon at the right end of the toolbar"
        #expect(noted == plain)
        #expect(noted.hashValue == plain.hashValue)
        #expect(DemoLocatorFactory.identity(noted) == DemoLocatorFactory.identity(plain))
        let scene = snapshot([
            node(0, "AXButton", "", rect(0.9, 0.05, 0.03, 0.04)), node(1, "AXButton", "", rect(0.1, 0.05, 0.03, 0.04))
        ])
        #expect(DemoLocatorMatcher.match(noted, in: scene) == .unique(0))
        #expect(DemoLocatorMatcher.match(noted, in: scene) == DemoLocatorMatcher.match(plain, in: scene))

        // Saved as before without a note, so demos saved before notes load with none.
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(json["note"] == nil)
        let loaded = try JSONDecoder().decode(
            DemoElementLocator.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.note == nil)
        let kept = try JSONDecoder().decode(DemoElementLocator.self, from: JSONEncoder().encode(noted))
        #expect(kept.note == noted.note)

        func demo(_ locator: DemoElementLocator) -> RealTimeDemo {
            let pre = ScreenSignature(selected: [], headings: [], dialogOpen: false)
            return RealTimeDemo(
                prompt: "x", app: DemoAppKey(bundleID: "a", appName: "A", engine: .native, isBrowser: false),
                title: "T",
                steps: [
                    DemoStep(title: "Open", script: "", holdSeconds: 1, action: .click(locator), pre: pre),
                    DemoStep(
                        title: "Type", script: "", holdSeconds: 1,
                        action: .typeText(field: locator, text: "Inbox", submit: false), pre: pre)
                ], status: .recorded)
        }
        #expect(
            DemoFingerprint.make(demo(noted), appVersion: "1", sizeClass: .regular)
                == DemoFingerprint.make(demo(plain), appVersion: "1", sizeClass: .regular))
    }
}

@Suite("Accessibility snapshots")
struct AXSnapshotBuilderTests {
    /// Which elements a walk asked for the element that titles them.
    final class TitleReads {
        var handles: [Int] = []
    }

    struct Tree: AXNodeSource {
        var nodes: [Int: (AXRawNode, [Int])]
        /// The text of each element's title element (`kAXTitleUIElementAttribute`).
        var titles: [Int: String] = [:]
        var titleReads = TitleReads()

        func read(_ handle: Int) -> (node: AXRawNode, children: [Int])? {
            nodes[handle].map { ($0.0, $0.1) }
        }

        func titleElementText(of handle: Int) -> String? {
            titleReads.handles.append(handle)
            return titles[handle]
        }
    }

    private func raw(
        _ role: String, title: String? = nil, value: String? = nil, frame: CGRect, subrole: String? = nil,
        placeholder: String? = nil, description: String? = nil, help: String? = nil, number: Double? = nil,
        maximum: Double? = nil, busy: Bool = false
    ) -> AXRawNode {
        var node = AXRawNode()
        node.role = role
        node.subrole = subrole
        node.title = title
        node.stringValue = value
        node.frame = frame
        node.placeholder = placeholder
        node.description = description
        node.help = help
        node.numberValue = number
        node.maxValue = maximum
        node.busy = busy
        return node
    }

    @Test("Walks the page, names rows from their text and never exposes field values")
    func buildsWebContent() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        let tree = Tree(nodes: [
            0: (raw("AXWindow", frame: window), [1, 2]),
            1: (raw("AXButton", title: "Back", frame: CGRect(x: 110, y: 110, width: 30, height: 20)), []),
            2: (raw("AXWebArea", frame: CGRect(x: 100, y: 150, width: 1000, height: 750)), [3, 4, 7]),
            3: (raw("AXTextField", value: "my secret search", frame: CGRect(x: 200, y: 200, width: 300, height: 30), placeholder: "Search"), []),
            4: (raw("AXTable", title: "Operations", frame: CGRect(x: 200, y: 300, width: 800, height: 400)), [5]),
            5: (raw("AXRow", frame: CGRect(x: 200, y: 300, width: 800, height: 40)), [6]),
            6: (raw("AXStaticText", value: "Received", frame: CGRect(x: 210, y: 305, width: 100, height: 20)), []),
            7: (raw("AXTextField", value: "hunter2", frame: CGRect(x: 200, y: 250, width: 300, height: 30), subrole: "AXSecureTextField"), []),
        ])
        var builder = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        let (snapshot, handles) = builder.build(generation: 1)

        #expect(handles.count == snapshot.nodes.count)
        let field = try #require(snapshot.nodes.first { $0.roleClass == .field && !$0.isSecure })
        #expect(field.label == "Search")
        #expect(field.textLength == "my secret search".count)
        let row = try #require(snapshot.nodes.first { $0.roleClass == .row })
        #expect(row.label == "Received")
        #expect(snapshot.container(of: row)?.label == "operations")
        let encoded = DemoSceneEncoder.encode(snapshot).text
        #expect(!encoded.contains("my secret search"))
        #expect(!encoded.contains("hunter2"))
        #expect(encoded.contains("\"Back\""))
        #expect(snapshot.webContent?.isReady == true)
    }

    @Test("Nodes in a page or a scroll area know the viewport that cuts them; window chrome has none")
    func recordsViewports() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        let tree = Tree(nodes: [
            0: (raw("AXWindow", frame: window), [1, 2, 4]),
            1: (raw("AXButton", title: "Back", frame: CGRect(x: 110, y: 110, width: 30, height: 20)), []),
            2: (raw("AXScrollArea", frame: CGRect(x: 100, y: 150, width: 300, height: 400)), [3]),
            3: (raw("AXRow", title: "Inbox", frame: CGRect(x: 100, y: 500, width: 300, height: 100)), []),
            4: (raw("AXWebArea", frame: CGRect(x: 400, y: 150, width: 700, height: 900)), [5]),
            5: (raw("AXHeading", title: "Pricing", frame: CGRect(x: 450, y: 200, width: 300, height: 40)), [])
        ])
        var builder = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        let snapshot = builder.build(generation: 1).snapshot
        let back = try #require(snapshot.nodes.first { $0.label == "Back" })
        #expect(back.viewport == nil)
        // The list's rows are cut by the scroll area.
        let row = try #require(snapshot.nodes.first { $0.roleClass == .row })
        #expect(row.viewport == NormRect(x: 0, y: 0.0625, w: 0.3, h: 0.5))
        // The page is cut by its web area where it stays inside the window.
        let heading = try #require(snapshot.nodes.first { $0.roleClass == .heading })
        #expect(heading.viewport == NormRect(x: 0.3, y: 0.0625, w: 0.7, h: 0.9375))
    }

    @Test("A dialog keeps its own text for the policy, long lines included, and none it couldn't read in full")
    func keepsDialogText() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        let warning = "This permanently removes the transaction from every device signed in to this account."
        let sheet = CGRect(x: 300, y: 200, width: 400, height: 200)
        let tree = Tree(nodes: [
            0: (raw("AXWindow", frame: window), [1, 2]),
            1: (raw("AXStaticText", value: "Confirmed", frame: CGRect(x: 110, y: 110, width: 100, height: 20)), []),
            2: (raw("AXSheet", title: "Delete transaction?", frame: sheet), [3]),
            3: (raw("AXGroup", frame: sheet), [4, 5]),
            4: (raw("AXStaticText", value: warning, frame: CGRect(x: 310, y: 240, width: 380, height: 40)), []),
            5: (raw("AXButton", title: "OK", frame: CGRect(x: 600, y: 350, width: 80, height: 30)), [])
        ])
        var builder = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        let snapshot = builder.build(generation: 1).snapshot
        let ok = try #require(snapshot.nodes.first { $0.label == "OK" })
        #expect(ok.inDialog)
        #expect(snapshot.dialogText(of: ok) == ["Delete transaction?", warning])
        // The warning is too long to list, so it's only kept as the dialog's text.
        #expect(!snapshot.nodes.contains { $0.label == warning })
        let page = try #require(snapshot.nodes.first { $0.label == "Confirmed" })
        #expect(!page.inDialog)
        #expect(snapshot.dialogText(of: page).isEmpty)

        // Cut off before its warning, the dialog has no text, so it never reads as harmless.
        var cut = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        cut.limits.chromeNodeBudget = 3
        cut.limits.nodeBudget = 3
        #expect(cut.build(generation: 1).snapshot.dialogTexts.isEmpty)
    }

    @Test("A control with no name borrows its help text, then an image's, then its title element's, and keeps it")
    func borrowsNamesForIconControls() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        func frame(_ x: Double, _ y: Double) -> CGRect { CGRect(x: x, y: y, width: 40, height: 24) }
        let tree = Tree(
            nodes: [
                0: (raw("AXWindow", frame: window), [1, 3, 5, 6, 7, 8]),
                1: (raw("AXButton", frame: frame(110, 110), help: "Share this list"), [2]),
                2: (raw("AXImage", frame: frame(110, 110), description: "Upload"), []),
                3: (raw("AXButton", frame: frame(160, 110)), [4]),
                4: (raw("AXImage", title: "gear", frame: frame(160, 110), description: "Settings"), []),
                5: (raw("AXCheckBox", frame: frame(110, 200)), []),
                6: (raw("AXButton", title: "Save", frame: frame(210, 110)), []),
                7: (raw("AXRow", frame: CGRect(x: 110, y: 300, width: 800, height: 30)), [9, 10]),
                8: (raw("AXButton", frame: frame(260, 110)), []),
                9: (raw("AXStaticText", value: "Inbox", frame: frame(120, 300)), []),
                10: (raw("AXButton", frame: frame(800, 300), help: "More"), [])
            ],
            titles: [5: "Show hidden files", 6: "Other caption", 10: "Never read"])
        var builder = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        let snapshot = builder.build(generation: 1).snapshot
        func node(at x: Double, _ y: Double) throws -> AXNode {
            let rect = NormRect(x: (x - 100) / 1000, y: (y - 100) / 800, w: 0.04, h: 0.03)
            return try #require(snapshot.nodes.first { $0.roleClass.isInteractive && $0.rect == rect })
        }

        // Help text first, before an image inside.
        #expect(try node(at: 110, 110).label == "Share this list")
        #expect(try node(at: 110, 110).labelIsBorrowed)
        // An image's description, before its title.
        #expect(try node(at: 160, 110).label == "Settings")
        // The element that titles it, like a checkbox's caption.
        #expect(try node(at: 110, 200).label == "Show hidden files")
        // A control's own title stays, and its title element is never read.
        #expect(try node(at: 210, 110).label == "Save")
        #expect(try !node(at: 210, 110).labelIsBorrowed)
        // With nothing to borrow it stays unlabelled.
        #expect(try node(at: 260, 110).label.isEmpty)
        // Only unnamed controls with neither help text nor an image are asked for a title element.
        #expect(tree.titleReads.handles.sorted() == [5, 8])
        // The row keeps the label its own text gives it, as before borrowed names.
        #expect(snapshot.nodes.first { $0.roleClass == .row }?.label == "Inbox")
        #expect(try node(at: 800, 300).label == "More")
        #expect(DemoSceneEncoder.encode(snapshot).text.contains("\"Settings\""))
    }

    @Test("Spinners, unfinished progress bars and busy elements in view count as busy, and are never listed")
    func countsBusyIndicators() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 800)
        let bar = CGRect(x: 200, y: 200, width: 300, height: 10)
        let results = CGRect(x: 500, y: 300, width: 400, height: 300)
        let tree = Tree(nodes: [
            0: (raw("AXWindow", frame: window), [1, 2, 3, 4, 5, 6, 7]),
            1: (raw("AXBusyIndicator", frame: CGRect(x: 110, y: 110, width: 16, height: 16)), []),
            2: (raw("AXProgressIndicator", frame: bar, number: 40, maximum: 100), []),
            // Finished: not busy.
            3: (raw("AXProgressIndicator", frame: bar, number: 100, maximum: 100), []),
            // Indeterminate, but scrolled out of its list's view.
            4: (raw("AXScrollArea", frame: CGRect(x: 100, y: 600, width: 300, height: 100)), [8]),
            // A region that says it's still loading, like `aria-busy`.
            5: (raw("AXGroup", title: "Results", frame: results, busy: true), []),
            // Outside the window.
            6: (raw("AXBusyIndicator", frame: CGRect(x: 1200, y: 110, width: 16, height: 16)), []),
            7: (raw("AXButton", title: "Refresh", frame: CGRect(x: 150, y: 110, width: 60, height: 20)), []),
            8: (raw("AXProgressIndicator", frame: CGRect(x: 110, y: 750, width: 200, height: 10)), [])
        ])
        var builder = AXSnapshotBuilder(source: tree, window: 0, windowFrame: window)
        let snapshot = builder.build(generation: 1).snapshot
        #expect(snapshot.busyIndicators == 3)
        #expect(!snapshot.nodes.contains { $0.role == "AXBusyIndicator" || $0.role == "AXProgressIndicator" })
        let idle = AXSnapshot(
            generation: 2, windowFrame: window, nodes: snapshot.nodes, webURL: nil, dialogOpen: false, webContent: nil)
        #expect(snapshot.isBusier(than: idle))
        #expect(!idle.isBusier(than: snapshot))
        // A spinner already showing before the action never counts as its work.
        #expect(!snapshot.isBusier(than: snapshot))
        #expect(snapshot.isBusier(than: nil))
    }
}
