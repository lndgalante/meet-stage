import Carbon
import CoreGraphics
import Foundation
import JavaScriptCore
import Testing

@testable import MeetStage

@Suite("Browser scripting")
struct BrowserScriptingTests {
    // MARK: Scripting definitions

    private static let diaLike = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
        <dictionary title="Dia">
          <suite name="Standard Suite" code="core">
            <class name="window" code="cwin" plural="windows">
              <property name="id" code="ID  " type="text" access="r"/>
              <property name="name" code="pnam" type="text" access="r"/>
              <property name="active tab" code="acTa" type="tab" access="r"/>
              <property name="index" code="pidx" type="integer" access="r"/>
              <property name="minimized" code="pmnd" type="boolean" access="rw"/>
              <property name="visible" code="pvis" type="boolean" access="rw"/>
            </class>
          </suite>
          <suite name="Dia Suite" code="DiaS">
            <class name="tab" code="DiaT" plural="tabs">
              <property name="URL" code="URL " type="text" access="rw"/>
              <property name="loading" code="ldng" type="boolean" access="r"/>
            </class>
            <command name="execute" code="CrSuExJa">
              <direct-parameter type="specifier"/>
              <parameter name="javascript" code="JvSc" type="text"/>
              <result type="text"/>
            </command>
          </suite>
        </dictionary>
        """

    private static let chromeLike = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary title="Dictionary">
          <suite name="Standard Suite" code="core">
            <class name="window" code="cwin">
              <property name="name" code="pnam" type="text" access="r"/>
              <property name="id" code="ID  " type="text" access="r"/>
              <property name="index" code="pidx" type="integer"/>
              <property name="bounds" code="pbnd" type="rectangle"/>
              <property name="active tab" code="acTa" type="tab" access="r"/>
            </class>
          </suite>
          <suite name="Chromium Suite" code="CrSu">
            <class name="tab" code="CrTb">
              <property name="title" code="pnam" type="text" access="r"/>
              <property name="URL" code="URL " type="text"/>
            </class>
            <class name="bookmark item" code="CrBI">
              <property name="URL" code="bURL" type="text"/>
            </class>
            <command name="execute" code="CrSuExJa">
              <direct-parameter type="specifier"/>
              <parameter name="javascript" code="JvSc" type="text"/>
            </command>
          </suite>
        </dictionary>
        """

    private static let safariLike = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dictionary xmlns:xi="http://www.w3.org/2003/XInclude">
          <xi:include href="file:///System/Library/ScriptingDefinitions/CocoaStandard.sdef" \
        xpointer="xpointer(/dictionary/suite)"/>
          <suite name="Safari suite" code="sfri">
            <class-extension extends="window">
              <property type="tab" name="current tab" code="cTab"/>
            </class-extension>
            <class name="tab" plural="tabs" code="bTab">
              <property type="text" name="URL" code="pURL"/>
            </class>
            <command name="do JavaScript" code="sfridojs">
              <direct-parameter type="text"/>
              <parameter name="in" code="dcnm" optional="yes"><type type="document"/><type type="tab"/></parameter>
            </command>
          </suite>
        </dictionary>
        """

    private static let cocoaStandardLike = """
        <dictionary>
          <suite name="Standard Suite" code="????">
            <class name="window" code="cwin">
              <property name="name" code="pnam" type="text" access="r"/>
              <property name="id" code="ID  " type="integer" access="r"/>
              <property name="index" code="pidx" type="integer"/>
              <property name="bounds" code="pbnd" type="rectangle"/>
            </class>
          </suite>
        </dictionary>
        """

    private func definition(_ dialect: BrowserScriptingDialect, bounds: Bool, url: String)
        -> BrowserScriptingDefinition
    {
        BrowserScriptingDefinition(dialect: dialect, windowsHaveBounds: bounds, tabURLProperty: code(url))
    }

    @Test("Dia and Chrome definitions read as Chromium, with bounds only where windows report them")
    func chromiumDefinitions() {
        let dia = BrowserScriptingDefinition.parse(Data(Self.diaLike.utf8))
        #expect(dia == definition(.chromium, bounds: false, url: "URL "))
        let chrome = BrowserScriptingDefinition.parse(Data(Self.chromeLike.utf8))
        #expect(chrome == definition(.chromium, bounds: true, url: "URL "))
        #expect(chrome?.tabProperty == code("acTa"))
    }

    @Test("Safari's definition follows its include into Apple's standard window class")
    func safariDefinition() throws {
        var requested: [URL] = []
        let included = BrowserScriptingDefinition.parse(Data(Self.safariLike.utf8)) { url in
            requested.append(url)
            return Data(Self.cocoaStandardLike.utf8)
        }
        #expect(requested.map(\.absoluteString) == ["file:///System/Library/ScriptingDefinitions/CocoaStandard.sdef"])
        #expect(included == definition(.safari, bounds: true, url: "pURL"))
        #expect(included?.tabProperty == code("cTab"))

        let alone = BrowserScriptingDefinition.parse(Data(Self.safariLike.utf8))
        #expect(alone?.dialect == .safari)
        #expect(alone?.windowsHaveBounds == false)

        // The live resolver reads the real system file.
        let system = BrowserScriptingDefinition.parse(
            Data(Self.safariLike.utf8), include: BrowserScriptingDefinition.systemInclude)
        #expect(system?.windowsHaveBounds == true)
    }

    @Test("Includes are read only from Apple's shared scripting definitions")
    func includesStayInSystemDefinitions() throws {
        for address in [
            "file:///etc/hosts", "https://example.com/CocoaStandard.sdef",
            "file:///System/Library/ScriptingDefinitions/../../../etc/hosts"
        ] {
            #expect(BrowserScriptingDefinition.systemInclude(try #require(URL(string: address))) == nil)
        }
    }

    @Test("Browsers without page scripting, and malformed definitions, have no dialect")
    func definitionsWithoutDialect() {
        let firefoxLike = """
            <dictionary><suite name="Standard Suite" code="core"><class name="window" code="cwin">
            <property name="bounds" code="pbnd" type="rectangle"/></class></suite></dictionary>
            """
        #expect(BrowserScriptingDefinition.parse(Data(firefoxLike.utf8)) == nil)
        let noActiveTab = Self.diaLike.replacingOccurrences(of: "code=\"acTa\"", with: "code=\"xxxx\"")
        #expect(BrowserScriptingDefinition.parse(Data(noActiveTab.utf8)) == nil)
        #expect(BrowserScriptingDefinition.parse(Data("<dictionary><suite>".utf8)) == nil)
    }

    @Test("A tab class named in a child type element supplies its URL property")
    func tabTypeFromChildElement() {
        let sdef = """
            <dictionary><suite name="S" code="core">
            <class name="window" code="cwin">
              <property name="active tab" code="acTa"><type type="browser tab"/></property>
            </class>
            <class name="browser tab" code="XxTb"><property name="url" code="xURL" type="text"/></class>
            <command name="execute" code="CrSuExJa"/></suite></dictionary>
            """
        #expect(BrowserScriptingDefinition.parse(Data(sdef.utf8))?.tabURLProperty == code("xURL"))
    }

    // MARK: Window matching

    private static let windowFrame = CGRect(x: 0, y: 25, width: 1200, height: 800)

    private func captured(
        _ title: String, _ frame: CGRect = Self.windowFrame, id: CGWindowID = 7
    ) -> BrowserWindowMatcher.Captured {
        BrowserWindowMatcher.Captured(id: id, title: title, frame: frame)
    }

    private func candidate(_ id: String, _ name: String, index: Int, bounds: CGRect? = nil) -> ScriptingWindowInfo {
        ScriptingWindowInfo(id: .text(id), name: name, index: index, bounds: bounds)
    }

    @Test("Bounds within 4 points identify a window, whatever its title")
    func matchesByBounds() {
        let frame = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let windows = [
            candidate("a", "Subtis", index: 1, bounds: CGRect(x: 300, y: 25, width: 900, height: 700)),
            candidate("b", "Something else", index: 2, bounds: frame.offsetBy(dx: 3, dy: -2))
        ]
        #expect(BrowserWindowMatcher.match(captured("Subtis", frame), among: windows, screenWindows: []) == .text("b"))
        let farOff = [candidate("c", "Other", index: 1, bounds: frame.offsetBy(dx: 5, dy: 0))]
        #expect(BrowserWindowMatcher.match(captured("Subtis", frame), among: farOff, screenWindows: []) == nil)
    }

    @Test("Same-sized windows are told apart by title")
    func boundsTiesBrokenByTitle() {
        let frame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windows = [
            candidate("a", "Inbox", index: 1, bounds: frame),
            candidate("b", "Subtis", index: 2, bounds: frame)
        ]
        #expect(BrowserWindowMatcher.match(captured("Subtis", frame), among: windows, screenWindows: []) == .text("b"))
    }

    @Test("Without bounds, an exact title beats one that only starts the same")
    func matchesByTitle() {
        let windows = [
            candidate("a", "Subtis – Search", index: 1),
            candidate("b", "Subtis", index: 2),
            candidate("c", "Ledger", index: 3)
        ]
        #expect(BrowserWindowMatcher.match(captured("Subtis"), among: windows, screenWindows: []) == .text("b"))
        let prefixOnly = [candidate("a", "Subtis - Dia", index: 1), candidate("c", "Ledger", index: 2)]
        #expect(BrowserWindowMatcher.match(captured("Subtis"), among: prefixOnly, screenWindows: []) == .text("a"))
        #expect(BrowserWindowMatcher.match(captured("Figma"), among: prefixOnly, screenWindows: []) == nil)
        #expect(
            BrowserWindowMatcher.match(captured(""), among: [candidate("a", "", index: 1)], screenWindows: []) == nil)
    }

    @Test("Look-alike windows are told apart by their front-to-back order")
    func tiesBrokenByZOrder() {
        let windows = [
            candidate("back", "New Tab", index: 3),
            candidate("front", "New Tab", index: 1),
            candidate("other", "Docs", index: 2)
        ]
        let screen = [
            OnScreenWindow(id: 4, title: "New Tab", frame: .null),
            OnScreenWindow(id: 5, title: "Docs", frame: .null),
            OnScreenWindow(id: 7, title: "New Tab", frame: .null)
        ]
        #expect(
            BrowserWindowMatcher.match(captured("New Tab", id: 7), among: windows, screenWindows: screen)
                == .text("back"))
        #expect(
            BrowserWindowMatcher.match(captured("New Tab", id: 4), among: windows, screenWindows: screen)
                == .text("front"))
        // A third look-alike the window server doesn't show, such as one on another Space, leaves it ambiguous.
        let extra = windows + [candidate("hidden", "New Tab", index: 4)]
        #expect(BrowserWindowMatcher.match(captured("New Tab", id: 7), among: extra, screenWindows: screen) == nil)
    }

    // MARK: Pages

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    @Test("A tab matches the page by scheme, host, port, and path, ignoring query and fragment")
    func pageAddressMatching() throws {
        let page = try #require(PageAddress(url: url("https://subtis.io/search?q=matrix#results")))
        #expect(page.matches(try url("https://subtis.io/search?q=other")))
        #expect(page.matches(try url("https://Subtis.IO/search")))
        #expect(page.matches(try url("https://subtis.io:443/search")))
        #expect(!page.matches(try url("https://subtis.io:8443/search")))
        #expect(!page.matches(try url("http://subtis.io/search")))
        #expect(!page.matches(try url("https://subtis.io/search/")))
        #expect(!page.matches(try url("https://www.subtis.io/search")))
        #expect(!page.matches(nil))
        #expect(try #require(PageAddress(url: url("https://subtis.io"))).matches(try url("https://subtis.io/")))
        #expect(try #require(PageAddress(url: url("https://subtis.io/caf%C3%A9"))).path == "/café")
    }

    @Test("Navigation arrives at the destination's host, a www twin, or a subdomain, never a lookalike")
    func navigationArrival() throws {
        let destination = try url("https://subtis.io/movies")
        #expect(PageAddress.hasReached(try url("https://subtis.io/"), destination))
        #expect(PageAddress.hasReached(try url("https://www.subtis.io/"), destination))
        #expect(PageAddress.hasReached(try url("https://en.subtis.io/"), destination))
        #expect(!PageAddress.hasReached(try url("https://notsubtis.io/"), destination))
        #expect(!PageAddress.hasReached(try url("https://subtis.io.example.com/"), destination))
        #expect(!PageAddress.hasReached(nil, destination))
        #expect(PageAddress.isWebAddress(try url("https://subtis.io")))
        #expect(!PageAddress.isWebAddress(try url("ftp://subtis.io")))
        #expect(!PageAddress.isWebAddress(try url("https://user:secret@subtis.io")))
        #expect(!PageAddress.isWebAddress(try url("javascript:alert(1)")))
    }

    // MARK: Errors and permission

    @Test("Apple Event errors map to what the demo can do about them")
    func errorMapping() {
        #expect(BrowserScriptingError(code: -1743, message: nil, duringJavaScript: false) == .notPermitted)
        #expect(BrowserScriptingError(code: -1744, message: nil, duringJavaScript: false) == .needsConsent)
        #expect(BrowserScriptingError(code: -600, message: nil, duringJavaScript: true) == .appNotRunning)
        #expect(BrowserScriptingError(code: -609, message: nil, duringJavaScript: false) == .appNotRunning)
        #expect(BrowserScriptingError(code: -1712, message: nil, duringJavaScript: true) == .timedOut)
        let chrome =
            "Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to "
            + "View > Developer > Allow JavaScript from Apple Events."
        let safari =
            "You must enable the 'Allow JavaScript from Apple Events' option in Safari's Develop menu "
            + "to use 'do JavaScript'."
        #expect(BrowserScriptingError(code: 12, message: chrome, duringJavaScript: true) == .javaScriptOff)
        #expect(BrowserScriptingError(code: 8, message: safari, duringJavaScript: true) == .javaScriptOff)
        #expect(BrowserScriptingError(code: 12, message: chrome, duringJavaScript: false) == .failed(chrome))
        #expect(
            BrowserScriptingError(code: -1728, message: nil, duringJavaScript: true)
                == .failed("Apple Event error -1728"))
        #expect(BrowserScriptingError.notPermitted.blocksScripting)
        #expect(BrowserScriptingError.timedOut.blocksScripting)
        #expect(!BrowserScriptingError.tabMismatch.blocksScripting)
        #expect(!BrowserScriptingError.failed("x").blocksScripting)
    }

    @Test("Only the browser saying so turns page scripts off; a page that runs no scripts says nothing")
    func probeOutcomes() throws {
        #expect(try BrowserJavaScriptState.probed(.success(2)) == .on)
        #expect(try BrowserJavaScriptState.probed(.failure(.javaScriptOff)) == .off)
        // A browser's own page, a crashed renderer, or a page mid-replacement.
        #expect(try BrowserJavaScriptState.probed(.success(nil)) == .unknown)
        #expect(try BrowserJavaScriptState.probed(.success(0)) == .unknown)
        #expect(try BrowserJavaScriptState.probed(.failure(.failed("Apple Event error -1728"))) == .unknown)
        #expect(throws: BrowserScriptingError.notPermitted) {
            try BrowserJavaScriptState.probed(.failure(.notPermitted))
        }
        #expect(throws: BrowserScriptingError.timedOut) { try BrowserJavaScriptState.probed(.failure(.timedOut)) }
    }

    @Test("Automation permission reads macOS's answer")
    func automationPermission() {
        #expect(AutomationPermission(status: 0) == .granted)
        #expect(AutomationPermission(status: -1743) == .denied)
        #expect(AutomationPermission(status: -1744) == .notDetermined)
        #expect(AutomationPermission(status: -600) == .notDetermined)
    }

    // MARK: Apple Event descriptors

    private func code(_ text: String) -> OSType {
        ScriptingCode.fourCharCode(text) ?? 0
    }

    private func key(_ descriptor: NSAppleEventDescriptor?, _ keyword: Int) -> NSAppleEventDescriptor? {
        descriptor?.forKeyword(AEKeyword(keyword))
    }

    @Test("Four-character codes are exactly four Mac Roman characters")
    func fourCharCodes() {
        #expect(ScriptingCode.fourCharCode("cwin") == OSType(cWindow))
        #expect(ScriptingCode.fourCharCode("URL ") == 0x5552_4C20)
        #expect(ScriptingCode.fourCharCode("URL") == nil)
        #expect(ScriptingCode.fourCharCode("CrSuExJa") == nil)
    }

    @Test("A tab's URL is addressed through its window's id, as AppleScript compiles it")
    func objectSpecifiers() throws {
        let dia = BrowserScriptingDefinition(dialect: .chromium, windowsHaveBounds: false, tabURLProperty: code("URL "))
        let specifier = ScriptingSpecifier.property(
            dia.tabURLProperty, of: ScriptingSpecifier.tab(of: .text("w1"), dia))
        #expect(specifier.descriptorType == typeObjectSpecifier)
        #expect(key(specifier, keyAEDesiredClass)?.typeCodeValue == cProperty)
        #expect(key(specifier, keyAEKeyForm)?.enumCodeValue == OSType(formPropertyID))
        #expect(key(specifier, keyAEKeyData)?.typeCodeValue == code("URL "))

        let tab = try #require(key(specifier, keyAEContainer))
        #expect(tab.descriptorType == typeObjectSpecifier)
        #expect(key(tab, keyAEKeyData)?.typeCodeValue == code("acTa"))

        let window = try #require(key(tab, keyAEContainer))
        #expect(key(window, keyAEDesiredClass)?.typeCodeValue == OSType(cWindow))
        #expect(key(window, keyAEKeyForm)?.enumCodeValue == OSType(formUniqueID))
        #expect(key(window, keyAEKeyData)?.stringValue == "w1")
        #expect(key(window, keyAEContainer)?.descriptorType == typeNull)

        let safariWindow = ScriptingSpecifier.window(.number(42))
        #expect(key(safariWindow, keyAEKeyData)?.descriptorType == typeSInt32)
        #expect(key(safariWindow, keyAEKeyData)?.int32Value == 42)
    }

    @Test("Every window is the absolute ordinal “all”")
    func everyWindowSpecifier() throws {
        let every = ScriptingSpecifier.everyWindow()
        #expect(key(every, keyAEDesiredClass)?.typeCodeValue == OSType(cWindow))
        #expect(key(every, keyAEKeyForm)?.enumCodeValue == OSType(formAbsolutePosition))
        let ordinal = try #require(key(every, keyAEKeyData))
        #expect(ordinal.descriptorType == typeAbsoluteOrdinal)
        #expect(ordinal.data.withUnsafeBytes { $0.loadUnaligned(as: OSType.self) } == OSType(kAEAll))
    }

    @Test("JavaScript and navigation events use each browser's own command")
    func events() throws {
        let chrome = BrowserScriptingDefinition(
            dialect: .chromium, windowsHaveBounds: true, tabURLProperty: code("URL "))
        let execute = ScriptingEvent.javaScript("1+1", inTabOf: .text("9"), chrome, target: nil)
        #expect(execute.eventClass == code("CrSu"))
        #expect(execute.eventID == code("ExJa"))
        #expect(execute.paramDescriptor(forKeyword: code("JvSc"))?.stringValue == "1+1")
        let tab = try #require(execute.paramDescriptor(forKeyword: keyDirectObject))
        #expect(key(tab, keyAEKeyData)?.typeCodeValue == code("acTa"))

        let safari = BrowserScriptingDefinition(dialect: .safari, windowsHaveBounds: true, tabURLProperty: code("pURL"))
        let doJavaScript = ScriptingEvent.javaScript("1+1", inTabOf: .number(3), safari, target: nil)
        #expect(doJavaScript.eventClass == code("sfri"))
        #expect(doJavaScript.eventID == code("dojs"))
        #expect(doJavaScript.paramDescriptor(forKeyword: keyDirectObject)?.stringValue == "1+1")
        let currentTab = try #require(doJavaScript.paramDescriptor(forKeyword: code("dcnm")))
        #expect(key(currentTab, keyAEKeyData)?.typeCodeValue == code("cTab"))

        let url = ScriptingSpecifier.property(safari.tabURLProperty, of: ScriptingSpecifier.tab(of: .number(3), safari))
        let set = ScriptingEvent.set(url, to: NSAppleEventDescriptor(string: "https://subtis.io"), target: nil)
        #expect(set.eventClass == kAECoreSuite)
        #expect(set.eventID == kAESetData)
        #expect(set.paramDescriptor(forKeyword: keyAEData)?.stringValue == "https://subtis.io")
        #expect(key(set.paramDescriptor(forKeyword: keyDirectObject), keyAEKeyData)?.typeCodeValue == code("pURL"))
        #expect(ScriptingEvent.get(url, target: nil).eventID == kAEGetData)
    }

    @Test("Window ids, bounds, and lists read back from reply descriptors")
    func replyValues() throws {
        #expect(ScriptingWindowID(NSAppleEventDescriptor(string: "w1")) == .text("w1"))
        #expect(ScriptingWindowID(NSAppleEventDescriptor(int32: 42)) == .number(42))
        #expect(ScriptingWindowID(NSAppleEventDescriptor(string: "")) == nil)

        let list = NSAppleEventDescriptor.list()
        for edge: Int32 in [10, 20, 1210, 820] { list.insert(NSAppleEventDescriptor(int32: edge), at: 0) }
        #expect(ScriptingValues.rect(list) == CGRect(x: 10, y: 20, width: 1200, height: 800))

        var quickDraw: (Int16, Int16, Int16, Int16) = (20, 10, 820, 1210)
        let rectangle = try #require(
            NSAppleEventDescriptor(descriptorType: typeQDRectangle, bytes: &quickDraw, length: 8))
        #expect(ScriptingValues.rect(rectangle) == CGRect(x: 10, y: 20, width: 1200, height: 800))

        #expect(ScriptingValues.items(list).count == 4)
        #expect(ScriptingValues.items(NSAppleEventDescriptor(string: "one")).count == 1)
        #expect(ScriptingValues.items(nil).isEmpty)
        #expect(
            ScriptingValues.url(NSAppleEventDescriptor(string: " https://subtis.io/ "))
                == URL(string: "https://subtis.io/"))
    }

    // MARK: Page script parameters

    private func page() throws -> PageAddress {
        try #require(PageAddress(url: url("https://subtis.io/search")))
    }

    private static let trickyText = "He said \"hi\" \\ 'there'\n</script>${x}`😀🇦🇷\u{2028}é"

    @Test("Typed text reaches the script as JSON data, whatever characters it has")
    func parametersAreJSON() throws {
        let operation = BrowserPageOperation.insertText(Self.trickyText, at: PagePoint(x: 0.25, y: 0.5))
        let arguments = operation.arguments(page: try page())
        let json = try BrowserPageScripts.encode(arguments)
        #expect(!json.contains("\n"))
        #expect(!json.contains("\u{2028}"))
        #expect(json.contains(#"He said \"hi\" \\ 'there'\n"#))
        #expect(json.contains("\\u2028"))
        #expect(try JSONDecoder().decode(BrowserPageScripts.Arguments.self, from: Data(json.utf8)) == arguments)
        let script = try operation.script(on: try page())
        #expect(script.contains("const args = " + json + ";"))
        #expect(script.components(separatedBy: json).count == 2)
    }

    @Test("Points are clamped to the page, and impossible numbers never reach it")
    func parameterValidation() throws {
        let clamped = BrowserPageOperation.click(at: PagePoint(x: 1.4, y: -0.2)).arguments(page: try page())
        let json = try BrowserPageScripts.encode(clamped)
        let decoded = try JSONDecoder().decode(BrowserPageScripts.Arguments.self, from: Data(json.utf8))
        #expect(decoded.x == 1)
        #expect(decoded.y == 0)
        #expect(throws: BrowserScriptingError.self) {
            try BrowserPageOperation.click(at: PagePoint(x: .nan, y: 0.5)).script(on: try page())
        }
        #expect(throws: BrowserScriptingError.self) {
            try BrowserPageOperation.scroll(at: PagePoint(x: 0.5, y: 0.5), points: 200, webAreaWidth: 0).script(
                on: try page())
        }
        #expect(
            PagePoint(CGPoint(x: 300, y: 250), in: CGRect(x: 100, y: 50, width: 800, height: 400))
                == PagePoint(x: 0.25, y: 0.5))
        #expect(!BrowserPageOperation.inspect(at: PagePoint(x: 0, y: 0)).changesPage)
        #expect(BrowserPageOperation.key(.escape).changesPage)
    }

    @Test("Results tolerate missing flags and unknown reasons")
    func resultDecoding() {
        let result = BrowserPageResult.decode(#"{"ok":false,"reason":"somethingNew","label":"Search"}"#)
        #expect(result?.reason == .exception)
        #expect(result?.acted == false)
        #expect(result?.label == "Search")
        #expect(BrowserPageResult.decode("not json") == nil)
    }

    // MARK: Page script behavior

    /// A tiny page: one element under every point, events recorded in `events`.
    private static let fakePage = """
        var events = [];
        var window = { innerWidth: 1000, innerHeight: 800 };
        function Event(type, init) { this.type = type; this.init = init || {}; }
        window.MouseEvent = Event;
        window.PointerEvent = Event;
        window.KeyboardEvent = Event;
        window.Event = Event;
        var location = { protocol: "https:", hostname: "subtis.io", port: "", pathname: "/search" };
        function element(tag, props) {
          var node = { nodeType: 1, tagName: tag, isConnected: true, parentElement: null, labels: [],
            attributes: {}, prevent: {},
            getAttribute: function (name) { return this.attributes[name] == null ? null : this.attributes[name]; },
            hasAttribute: function (name) { return this.attributes[name] != null; },
            matches: function (selector) { return selector.indexOf(tag.toLowerCase()) >= 0; },
            getRootNode: function () { return {}; },
            focus: function () { events.push("focus " + tag); },
            select: function () {},
            click: function () { events.push("click() " + tag); },
            dispatchEvent: function (event) {
              events.push(event.type + (event.keyCode ? " " + event.keyCode + "/" + event.charCode : ""));
              if (event.init.clientX != null) window.lastPoint = [event.init.clientX, event.init.clientY];
              return !this.prevent[event.type];
            } };
          for (var key in props) node[key] = props[key];
          return node;
        }
        var field = element("INPUT", { type: "text", value: "old" });
        var hits = [];
        var document = { activeElement: null, body: null,
          elementFromPoint: function (x, y) { hits.push([x, y]); return field; },
          execCommand: function (command, ui, text) {
            events.push("execCommand " + command);
            if (command === "insertText") field.value = text;
            return true;
          } };
        field.ownerDocument = document;
        """

    private func run(_ operation: BrowserPageOperation, setup: String = "") throws -> (BrowserPageResult, JSContext) {
        let context = try #require(JSContext())
        context.evaluateScript(Self.fakePage + "\n" + setup)
        let output = context.evaluateScript(try operation.script(on: try page()))
        #expect(context.exception == nil)
        let text = try #require(output?.toString())
        return (try #require(BrowserPageResult.decode(text)), context)
    }

    private func events(_ context: JSContext) -> [String] {
        context.objectForKeyedSubscript("events")?.toArray()?.compactMap { $0 as? String } ?? []
    }

    @Test("Every operation's script compiles and answers with JSON")
    func scriptsCompile() throws {
        let point = PagePoint(x: 0.5, y: 0.5)
        let operations: [BrowserPageOperation] = [
            .inspect(at: point), .click(at: point), .insertText("x", at: point),
            .submit(at: point, expectedValue: "x"), .key(.tab), .scroll(at: point, points: 120, webAreaWidth: 1000)
        ]
        for operation in operations {
            // A page somewhere else: the script must refuse before touching it.
            let (result, context) = try run(operation, setup: #"location.pathname = "/elsewhere";"#)
            #expect(result.reason == .tabMismatch)
            #expect(!result.acted)
            #expect(events(context).isEmpty)
        }
    }

    @Test("Typing round-trips any text exactly, at the point the fractions name")
    func insertTextRoundTrip() throws {
        let (result, context) = try run(.insertText(Self.trickyText, at: PagePoint(x: 0.25, y: 0.5)))
        #expect(result.ok)
        #expect(result.value == Self.trickyText)
        #expect(result.acted)
        #expect(result.tag == "input")
        #expect(result.role == "textbox")
        #expect(events(context) == ["focus INPUT", "execCommand insertText"])
        let hit = context.objectForKeyedSubscript("hits")?.toArray()?.first as? [Double]
        #expect(hit == [250, 400])
    }

    @Test("Password, payment, and one-time-code fields are refused before anything reads them")
    func sensitiveFieldsRefused() throws {
        for setup in [
            #"field.type = "password";"#, #"field.attributes.autocomplete = "one-time-code";"#,
            #"field.attributes.autocomplete = "billing cc-number";"#
        ] {
            let (result, context) = try run(.insertText("1234", at: PagePoint(x: 0.5, y: 0.5)), setup: setup)
            #expect(result.reason == .sensitiveField)
            #expect(!result.acted)
            #expect(result.value == nil)
            #expect(events(context).isEmpty)
        }
    }

    @Test("A click sends pointer and mouse events in a real click's order, and checks the label first")
    func clickSequence() throws {
        let button =
            #"field = element("BUTTON", { type: "submit", innerText: "Search" }); field.ownerDocument = document;"#
        let (result, context) = try run(.click(at: PagePoint(x: 0.1, y: 0.1), expecting: "Search"), setup: button)
        #expect(result.ok)
        #expect(result.label == "Search")
        #expect(result.role == "button")
        #expect(
            events(context) == [
                "pointerover", "mouseover", "pointerdown", "mousedown", "focus BUTTON", "pointerup", "mouseup", "click"
            ])
        let point = context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("lastPoint")?.toArray()
        #expect(point as? [Double] == [100, 80])

        let (changed, changedContext) = try run(
            .click(at: PagePoint(x: 0.1, y: 0.1), expecting: "Delete"), setup: button)
        #expect(changed.reason == .targetChanged)
        #expect(events(changedContext).isEmpty)

        // A cancelled pointerdown drops the compatibility mouse events but still moves focus.
        let cancelled = button + #" field.prevent.pointerdown = true;"#
        let (_, cancelledContext) = try run(.click(at: PagePoint(x: 0.1, y: 0.1)), setup: cancelled)
        #expect(
            events(cancelledContext) == [
                "pointerover", "mouseover", "pointerdown", "focus BUTTON", "pointerup", "click"
            ])
    }

    @Test("Return submits through the form's default button, as a real Return does")
    func submitUsesDefaultButton() throws {
        let form = """
            field.value = "The Matrix";
            var button = element("BUTTON", { type: "submit", innerText: "Search" });
            field.form = { elements: [field, button], getAttribute: function () { return null; },
              requestSubmit: function () { events.push("requestSubmit"); } };
            """
        let (result, context) = try run(
            .submit(at: PagePoint(x: 0.5, y: 0.5), expectedValue: "The Matrix"), setup: form)
        #expect(result.ok)
        #expect(result.submitted)
        #expect(result.label == "Search")
        #expect(events(context) == ["focus INPUT", "keydown 13/0", "keypress 13/13", "click() BUTTON", "keyup 13/0"])

        let prevented = form + #" field.prevent.keydown = true;"#
        let (kept, keptContext) = try run(
            .submit(at: PagePoint(x: 0.5, y: 0.5), expectedValue: "The Matrix"), setup: prevented)
        #expect(!kept.submitted)
        #expect(events(keptContext) == ["focus INPUT", "keydown 13/0", "keyup 13/0"])

        let (mismatch, mismatchContext) = try run(
            .submit(at: PagePoint(x: 0.5, y: 0.5), expectedValue: "Matrix"), setup: form)
        #expect(mismatch.reason == .valueMismatch)
        #expect(events(mismatchContext).isEmpty)
    }

    /// A list that scrolls inside a page that also scrolls.
    private static let scrollingPage = """
        window.getComputedStyle = function (node) { return { overflowY: node.overflowY || "visible" }; };
        function scroller(name, scrollTop, overflowY) {
          return element("DIV", { name: name, overflowY: overflowY, scrollTop: scrollTop, scrollHeight: 2000,
            clientHeight: 400, ownerDocument: document,
            scrollBy: function (options) {
              events.push("scrollBy " + name + " " + options.top + " " + options.behavior);
              this.scrollTop = Math.max(0, Math.min(this.scrollHeight - this.clientHeight, this.scrollTop + options.top));
            } });
        }
        var list = scroller("list", 0, "auto");
        document.scrollingElement = scroller("page", 0, "visible");
        field = list;
        """

    @Test("Scrolling converts points to CSS pixels and chains outward once the nearest list can't move")
    func scrollConvertsAndChains() throws {
        let scroll = BrowserPageOperation.scroll(at: PagePoint(x: 0.5, y: 0.5), points: 120, webAreaWidth: 500)
        let (result, context) = try run(scroll, setup: Self.scrollingPage)
        #expect(result.ok)
        #expect(result.scrolled == 120)
        #expect(events(context) == ["scrollBy list 240 instant"])

        let (chained, chainedContext) = try run(scroll, setup: Self.scrollingPage + "\nlist.scrollTop = 1600;")
        #expect(chained.scrolled == 120)
        #expect(events(chainedContext) == ["scrollBy list 240 instant", "scrollBy page 240 instant"])

        let (pageDown, pageDownContext) = try run(
            .key(.pageDown), setup: Self.scrollingPage + "\ndocument.activeElement = list;")
        #expect(pageDown.scrolled == 350)
        #expect(events(pageDownContext) == ["keydown 34/0", "scrollBy list 350 instant", "keyup 34/0"])
    }

    @Test("Tab moves focus in tab order: positive tabindex first, then document order, skipping -1")
    func tabOrder() throws {
        let buttons = """
            window.getComputedStyle = function () { return { visibility: "visible" }; };
            function button(name, tabIndex) {
              var node = element("BUTTON", { innerText: name, tabIndex: tabIndex, ownerDocument: document,
                getClientRects: function () { return [1]; } });
              node.focus = function () { events.push("focus " + name); document.activeElement = node; };
              return node;
            }
            var first = button("First", 0), second = button("Second", 2), third = button("Third", 0);
            var skipped = button("Skipped", -1);
            document.body = element("BODY", {});
            document.createTreeWalker = function () {
              var nodes = [first, skipped, second, third], index = -1;
              return { nextNode: function () { index += 1; return nodes[index] || null; } };
            };
            document.activeElement = first;
            """
        let (forward, forwardContext) = try run(.key(.tab), setup: buttons)
        #expect(forward.label == "Third")
        #expect(events(forwardContext) == ["keydown 9/0", "focus Third", "keyup 9/0"])

        let (backward, _) = try run(.key(.shiftTab), setup: buttons)
        #expect(backward.label == "Second")

        let (wrapped, _) = try run(.key(.tab), setup: buttons + "\ndocument.activeElement = third;")
        #expect(wrapped.label == "Second")

        let (kept, keptContext) = try run(.key(.tab), setup: buttons + "\nfirst.prevent.keydown = true;")
        #expect(kept.label == "First")
        #expect(events(keptContext) == ["keydown 9/0", "keyup 9/0"])
    }

    @Test("Without a default button, Return submits only a form with one blocking field")
    func implicitSubmissionWithoutButton() throws {
        let single = """
            field.value = "matrix";
            field.form = { elements: [field], getAttribute: function () { return null; },
              requestSubmit: function () { events.push("requestSubmit"); } };
            """
        let (result, context) = try run(.submit(at: PagePoint(x: 0.5, y: 0.5), expectedValue: "matrix"), setup: single)
        #expect(result.submitted)
        #expect(events(context).contains("requestSubmit"))

        let two = single + #" field.form.elements.push(element("INPUT", { type: "email" }));"#
        let (blocked, blockedContext) = try run(
            .submit(at: PagePoint(x: 0.5, y: 0.5), expectedValue: "matrix"), setup: two)
        #expect(!blocked.submitted)
        #expect(!events(blockedContext).contains("requestSubmit"))
    }
}
