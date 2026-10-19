import AppKit
import Carbon
import Foundation
import MeetStageCore

// MARK: - Client

/// Drives browser tabs in the background through the browser's own public
/// scripting: it opens addresses by setting a tab's URL, which needs only
/// Automation permission, and runs BetterMeets' fixed page script in the tab,
/// which also needs the browser's Allow JavaScript from Apple Events. Every
/// Apple Event waits on a dedicated queue, never on the main actor.
@MainActor
final class BrowserScripting {
    static let shared = BrowserScripting()

    private let channel = AppleEventChannel()
    private var definitions: [URL: BrowserScriptingDefinition?] = [:]
    private var windowIDs: [CGWindowID: ScriptingWindowID] = [:]
    /// What this run found out about each browser's JavaScript, by bundle ID.
    private var javaScriptStates: [String: BrowserJavaScriptState] = [:]

    // MARK: Setup

    /// The browser's scripting definition, or nil when it can't run JavaScript
    /// in a tab. Cached per bundle URL.
    func definition(forBundleAt bundleURL: URL) async -> BrowserScriptingDefinition? {
        if let known = definitions[bundleURL] { return known }
        let definition = try? await channel.run { BrowserScriptingDefinition.load(bundleURL: bundleURL) }
        definitions.updateValue(definition, forKey: bundleURL)
        return definition
    }

    /// Whether BetterMeets may send this browser Apple Events. With
    /// `askIfNeeded`, macOS asks the person, and this waits for their answer,
    /// so call it while BetterMeets is in front.
    func automationPermission(pid: pid_t, askIfNeeded: Bool) async -> AutomationPermission {
        let status = try? await channel.run { () -> OSStatus in
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            guard let address = target.aeDesc else { return OSStatus(procNotFound) }
            return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askIfNeeded)
        }
        return status.map(AutomationPermission.init(status:)) ?? .notDetermined
    }

    /// Starts a run: the browser is probed again and windows are matched again.
    func reset() {
        javaScriptStates.removeAll()
        windowIDs.removeAll()
    }

    // MARK: Tabs

    /// Opens `url` in the target window's tab by setting its URL, which needs no
    /// JavaScript. `commit` runs, and may veto by throwing, right before the
    /// address is set; errors before then mean nothing happened. True once the
    /// tab's address reaches the destination's host, false after 3 seconds.
    @discardableResult
    func navigate(
        _ target: BrowserScriptTarget, to url: URL, commit: @MainActor () throws -> Void = {}
    ) async throws -> Bool {
        guard PageAddress.isWebAddress(url) else {
            throw BrowserScriptingError.failed("Only web addresses can be opened.")
        }
        guard let definition = await definition(forBundleAt: target.bundleURL) else {
            throw BrowserScriptingError.unsupported
        }
        let window = try await verifiedWindow(target, definition, page: target.page)
        try Task.checkCancellation()
        try commit()
        let pid = target.pid
        let address = url.absoluteString
        try await channel.run { try ScriptingConnection(pid: pid).setTabURL(address, of: window, definition) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            if PageAddress.hasReached(try? await tabURL(of: window, pid: pid, definition), url) { return true }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        return false
    }

    /// Runs `operation` in the target window's tab once JavaScript is on and the
    /// tab shows the target's page. `commit` runs, and may veto by throwing,
    /// right before a step that changes the page is sent. Thrown errors before
    /// then, and results with `acted == false`, mean the page wasn't touched;
    /// `.timedOut` after it means the step may have run.
    func perform(
        _ operation: BrowserPageOperation, in target: BrowserScriptTarget, commit: @MainActor () throws -> Void = {}
    ) async throws -> BrowserPageResult {
        if case .insertText(let text, _) = operation, DemoActionPolicy.containsControlCharacters(text) {
            throw BrowserScriptingError.failed("Typed text can’t contain line breaks, tabs, or control characters.")
        }
        guard let definition = await definition(forBundleAt: target.bundleURL) else {
            throw BrowserScriptingError.unsupported
        }
        switch try await javaScriptState(in: target, definition) {
        case .on: break
        case .off: throw BrowserScriptingError.javaScriptOff
        case .unknown: throw BrowserScriptingError.failed("The page didn’t run the probe.")
        }
        guard let page = target.page else { throw BrowserScriptingError.tabMismatch }
        let window = try await verifiedWindow(target, definition, page: page)
        let script = try operation.script(on: page)
        try Task.checkCancellation()
        if operation.changesPage { try commit() }
        let pid = target.pid
        let reply = try await channel.run {
            try ScriptingConnection(pid: pid).runJavaScript(script, inTabOf: window, definition)?.stringValue
        }
        guard let reply, let result = BrowserPageResult.decode(reply) else {
            throw BrowserScriptingError.failed("The page returned an unreadable result.")
        }
        if result.reason == .tabMismatch {
            windowIDs[target.windowID] = nil
            throw BrowserScriptingError.tabMismatch
        }
        return result
    }

    // MARK: Matching and verification

    /// Whether JavaScript runs in the browser, found out once per run. `.unknown`,
    /// which isn't kept, when this page can't tell; throws when the tab can't be
    /// verified or scripting stopped.
    private func javaScriptState(
        in target: BrowserScriptTarget, _ definition: BrowserScriptingDefinition
    ) async throws -> BrowserJavaScriptState {
        if let known = javaScriptStates[target.bundleID] { return known }
        // Never run even the probe in a tab that isn't verified.
        guard let page = target.page else { throw BrowserScriptingError.tabMismatch }
        let window = try await verifiedWindow(target, definition, page: page)
        let pid = target.pid
        let outcome: Result<Double?, BrowserScriptingError>
        do {
            outcome = .success(
                try await channel.run {
                    try ScriptingConnection(pid: pid).runJavaScript(
                        BrowserPageScripts.probe, inTabOf: window, definition)?
                        .doubleValue
                })
        } catch let error as BrowserScriptingError {
            outcome = .failure(error)
        }
        let state = try BrowserJavaScriptState.probed(outcome)
        if state != .unknown { javaScriptStates[target.bundleID] = state }
        return state
    }

    /// The scripting window that is the target's window and, given a page,
    /// whose tab shows it. A cached window that fails or shows another page is
    /// matched again once; then the tab must match or this throws `.tabMismatch`.
    private func verifiedWindow(
        _ target: BrowserScriptTarget, _ definition: BrowserScriptingDefinition, page: PageAddress?
    ) async throws -> ScriptingWindowID {
        if let cached = windowIDs[target.windowID] {
            do {
                let url = try await tabURL(of: cached, pid: target.pid, definition)
                if page?.matches(url) ?? true { return cached }
            } catch let error as BrowserScriptingError where error.blocksScripting {
                throw error
            } catch {}
            windowIDs[target.windowID] = nil
        }
        let window = try await matchWindow(target, definition)
        let url = try await tabURL(of: window, pid: target.pid, definition)
        guard page?.matches(url) ?? true else { throw BrowserScriptingError.tabMismatch }
        return window
    }

    private func matchWindow(
        _ target: BrowserScriptTarget, _ definition: BrowserScriptingDefinition
    ) async throws -> ScriptingWindowID {
        let pid = target.pid
        let withBounds = definition.windowsHaveBounds
        let candidates = try await channel.run { try ScriptingConnection(pid: pid).windows(withBounds: withBounds) }
        let screen = WindowFrameResolver.onScreenWindows(of: pid)
        let live = screen.first { $0.id == target.windowID }
        let captured = BrowserWindowMatcher.Captured(
            id: target.windowID, title: live.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? target.windowTitle,
            frame: live.map(\.frame).flatMap { $0.isNull ? nil : $0 } ?? target.windowFrame)
        guard let window = BrowserWindowMatcher.match(captured, among: candidates, screenWindows: screen) else {
            throw BrowserScriptingError.windowNotFound
        }
        windowIDs[target.windowID] = window
        return window
    }

    private func tabURL(
        of window: ScriptingWindowID, pid: pid_t, _ definition: BrowserScriptingDefinition
    ) async throws -> URL? {
        try await channel.run { try ScriptingConnection(pid: pid).tabURL(of: window, definition) }
    }
}

/// The captured browser window a demo drives, and the page Accessibility sees in it.
struct BrowserScriptTarget: Sendable, Equatable {
    var pid: pid_t
    var bundleID: String
    var bundleURL: URL
    var windowID: CGWindowID
    /// The window's title and global frame as last seen. The window server's
    /// live values win while the window is on screen.
    var windowTitle: String
    var windowFrame: CGRect
    /// The address of the window's web area (its AXURL). JavaScript runs only
    /// in a tab showing this page.
    var pageURL: URL?

    var page: PageAddress? { pageURL.flatMap(PageAddress.init(url:)) }
}

extension BrowserScriptTarget {
    /// Nil when the source's app is no longer running.
    init?(source: WindowSource, pageURL: URL?) {
        guard let bundleURL = NSRunningApplication(processIdentifier: source.processIdentifier)?.bundleURL else {
            return nil
        }
        self.init(
            pid: source.processIdentifier, bundleID: source.bundleIdentifier, bundleURL: bundleURL,
            windowID: source.id, windowTitle: source.title,
            windowFrame: WindowFrameResolver.currentFrame(for: source.id, fallback: source.window.frame),
            pageURL: pageURL)
    }
}

// MARK: - Errors and permissions

/// Why the browser's scripting didn't run a step. Never shown: each one falls to
/// another route, so only its kind is logged.
enum BrowserScriptingError: Error, Equatable, Sendable {
    /// The browser's scripting can't run JavaScript in a tab.
    case unsupported
    /// Automation for this browser is off (-1743).
    case notPermitted
    /// Automation for this browser hasn't been asked yet (-1744); events never prompt.
    case needsConsent
    case appNotRunning
    /// The browser refuses JavaScript from Apple Events.
    case javaScriptOff
    case windowNotFound
    /// The window's tab isn't showing the page Accessibility sees.
    case tabMismatch
    /// The browser didn't answer in time. A step may or may not have run; never repeat it.
    case timedOut
    case failed(String)

    init(code: Int, message: String?, duringJavaScript: Bool) {
        switch code {
        case errAEEventNotPermitted: self = .notPermitted
        case errAEEventWouldRequireUserConsent: self = .needsConsent
        case procNotFound, connectionInvalid: self = .appNotRunning
        case errAETimeout: self = .timedOut
        default:
            if duringJavaScript, Self.saysJavaScriptIsOff(message) {
                self = .javaScriptOff
            } else {
                self = .failed(message ?? "Apple Event error \(code)")
            }
        }
    }

    /// Chrome: “Executing JavaScript through AppleScript is turned off…”; Safari:
    /// “You must enable the 'Allow JavaScript from Apple Events' option…”.
    private static func saysJavaScriptIsOff(_ message: String?) -> Bool {
        guard let message = message?.lowercased(), message.contains("javascript") else { return false }
        return ["allow javascript from apple events", "turned off", "not allowed", "disabled"].contains {
            message.contains($0)
        }
    }

    /// Stops scripting this browser for now, so matching windows again can't help.
    var blocksScripting: Bool {
        switch self {
        case .notPermitted, .needsConsent, .appNotRunning, .timedOut: true
        default: false
        }
    }
}

enum AutomationPermission: Sendable, Equatable {
    case granted, denied
    /// Not asked yet, or the browser isn't running so macOS can't tell.
    case notDetermined

    init(status: OSStatus) {
        switch Int(status) {
        case Int(noErr): self = .granted
        case errAEEventNotPermitted: self = .denied
        default: self = .notDetermined
        }
    }
}

/// Whether a browser runs JavaScript from Apple Events, as last found out.
enum BrowserJavaScriptState: Sendable, Equatable {
    case unknown, on, off

    /// What the probe's outcome says. Only the browser saying the setting is off
    /// counts as off: a page that runs no scripts, like a browser's own page or one
    /// being replaced, fails or answers something else whatever the setting, so the
    /// next page is probed again. Errors that stop scripting, Automation's among
    /// them, are rethrown.
    static func probed(_ outcome: Result<Double?, BrowserScriptingError>) throws -> BrowserJavaScriptState {
        switch outcome {
        case .success(let value): value == 2 ? .on : .unknown
        case .failure(.javaScriptOff): .off
        case .failure(.failed): .unknown
        case .failure(let error): throw error
        }
    }
}

// MARK: - Pages

/// The parts of a page's address that identify the tab showing it. Queries
/// and fragments change as a page runs, so they don't count.
struct PageAddress: Codable, Sendable, Equatable {
    var scheme: String
    var host: String
    /// Only a port other than the scheme's default.
    var port: Int?
    /// Percent-decoded; "/" for an empty path.
    var path: String

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return nil }
        self.scheme = scheme
        host = (url.host(percentEncoded: false) ?? "").lowercased()
        port = url.port == ["http": 80, "https": 443][scheme] ? nil : url.port
        let path = url.path(percentEncoded: false)
        self.path = path.isEmpty ? "/" : path
    }

    func matches(_ url: URL?) -> Bool {
        url.flatMap(PageAddress.init(url:)) == self
    }

    /// Whether a tab at `url` has reached `destination`'s site: the same host,
    /// ignoring “www.”, or a subdomain of it, where redirects often land.
    static func hasReached(_ url: URL?, _ destination: URL) -> Bool {
        guard let current = url?.host()?.lowercased(), let wanted = destination.host()?.lowercased() else {
            return false
        }
        func bare(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return bare(current) == bare(wanted) || bare(current).hasSuffix("." + bare(wanted))
    }

    /// HTTP or HTTPS with a host and no embedded credentials.
    static func isWebAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return !(url.host() ?? "").isEmpty && url.user == nil && url.password == nil
    }
}

// MARK: - Windows

/// A window's `id` in a browser's scripting: text in Chromium browsers, a number in Safari.
enum ScriptingWindowID: Sendable, Hashable {
    case text(String)
    case number(Int32)

    init?(_ descriptor: NSAppleEventDescriptor) {
        let integers: Set<DescType> = [typeSInt16, typeSInt32, typeSInt64, typeUInt16, typeUInt32, typeUInt64]
        if integers.contains(descriptor.descriptorType) {
            self = .number(descriptor.int32Value)
        } else if let text = descriptor.stringValue, !text.isEmpty {
            self = .text(text)
        } else {
            return nil
        }
    }

    /// The key a unique-ID specifier sends back, in the type the browser gave it.
    var descriptor: NSAppleEventDescriptor {
        switch self {
        case .text(let text): NSAppleEventDescriptor(string: text)
        case .number(let number): NSAppleEventDescriptor(int32: number)
        }
    }
}

/// One of a browser's windows, as its scripting reports it.
struct ScriptingWindowInfo: Sendable, Equatable {
    var id: ScriptingWindowID
    var name: String
    /// Front to back, from 1.
    var index: Int
    /// Global, top-left origin; nil when the browser's windows don't report bounds.
    var bounds: CGRect?
}

/// Finds which of a browser's scripting windows is the captured one. Bounds
/// identify a window best; titles narrow same-sized windows or stand in where
/// windows report no bounds; z-order separates windows alike in both. When
/// that still leaves a choice, it fails closed.
enum BrowserWindowMatcher {
    struct Captured: Sendable, Equatable {
        var id: CGWindowID
        var title: String
        /// Global, top-left origin.
        var frame: CGRect
    }

    private static let boundsTolerance: CGFloat = 4

    /// `screenWindows` are the app's layer-0 on-screen windows, front to back.
    static func match(
        _ captured: Captured, among candidates: [ScriptingWindowInfo], screenWindows: [OnScreenWindow]
    ) -> ScriptingWindowID? {
        var pool = candidates.filter { $0.bounds.map { isClose($0, captured.frame) } ?? false }
        var peers = screenWindows
        let sized = !pool.isEmpty
        if sized {
            if pool.count == 1 { return pool[0].id }
            peers = peers.filter { isClose($0.frame, captured.frame) }
        } else {
            pool = candidates
        }
        if let narrowed = narrow(pool, peers, to: captured.title, exact: true)
            ?? narrow(pool, peers, to: captured.title, exact: false)
        {
            (pool, peers) = narrowed
        } else if !sized {
            return nil
        }
        if pool.count == 1 { return pool[0].id }
        // Look-alikes: the captured window's place among them, front to back.
        guard pool.count == peers.count, let rank = peers.firstIndex(where: { $0.id == captured.id }) else {
            return nil
        }
        return pool.sorted { $0.index < $1.index }[rank].id
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        guard !a.isNull, !b.isNull else { return false }
        return abs(a.minX - b.minX) <= boundsTolerance && abs(a.minY - b.minY) <= boundsTolerance
            && abs(a.width - b.width) <= boundsTolerance && abs(a.height - b.height) <= boundsTolerance
    }

    /// Equal titles, or one starting with the other, since a window's title
    /// can carry the app's name or a profile after the page's.
    private static func titlesMatch(_ name: String, _ title: String, exact: Bool) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !title.isEmpty else { return false }
        return exact ? name == title : name.hasPrefix(title) || title.hasPrefix(name)
    }

    /// The candidates and screen windows with matching titles; nil when no candidate's matches.
    private static func narrow(
        _ pool: [ScriptingWindowInfo], _ peers: [OnScreenWindow], to title: String, exact: Bool
    ) -> ([ScriptingWindowInfo], [OnScreenWindow])? {
        let matching = pool.filter { titlesMatch($0.name, title, exact: exact) }
        guard !matching.isEmpty else { return nil }
        return (matching, peers.filter { titlesMatch($0.title, title, exact: exact) })
    }
}

// MARK: - Scripting definition

/// How a browser runs JavaScript in a tab.
enum BrowserScriptingDialect: String, Sendable, Equatable {
    /// `execute <tab> javascript` (CrSu/ExJa, JvSc) on a window's `active tab`, as in Chrome and Dia.
    case chromium
    /// `do JavaScript … in <tab>` (sfri/dojs, dcnm) on a window's `current tab`, as in Safari.
    case safari
}

/// What BetterMeets needs from a browser's scripting definition (sdef).
struct BrowserScriptingDefinition: Sendable, Equatable {
    var dialect: BrowserScriptingDialect
    /// Windows report `bounds` (pbnd), which matches them to captured windows best. Dia's don't.
    var windowsHaveBounds: Bool
    /// The tab's URL property: "URL " in Chromium browsers, "pURL" in Safari.
    var tabURLProperty: OSType

    /// The window property holding the tab it shows.
    var tabProperty: OSType {
        dialect == .chromium ? ScriptingCode.activeTab : ScriptingCode.currentTab
    }

    /// Reads sdef XML. `include` supplies the documents its `xi:include`
    /// elements name, which `OSACopyScriptingDefinitionFromURL` leaves
    /// unexpanded; Safari takes its window class from CocoaStandard.sdef that way.
    static func parse(_ data: Data, include: (URL) -> Data? = { _ in nil }) -> BrowserScriptingDefinition? {
        var summary = SdefSummary()
        summary.read(data, include: include, depth: 0)
        return summary.definition
    }

    /// The installed app's definition, or nil when it can't run JavaScript in a
    /// tab. Reads files only; blocking, so it runs off the main actor.
    static func load(bundleURL: URL) -> BrowserScriptingDefinition? {
        var sdef: Unmanaged<CFData>?
        let status = OSACopyScriptingDefinitionFromURL(bundleURL as CFURL, 0, &sdef)
        guard let data = sdef?.takeRetainedValue(), status == noErr else { return nil }
        return parse(data as Data, include: systemInclude)
    }

    /// Follows an include only into Apple's shared definitions, where Safari's points.
    static func systemInclude(_ url: URL) -> Data? {
        guard url.isFileURL, url.standardizedFileURL.path.hasPrefix("/System/Library/ScriptingDefinitions/") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}

/// The commands and classes of an sdef that decide its dialect.
private struct SdefSummary {
    struct Property {
        var name: String
        var code: String
        var type: String?
    }

    struct ScriptingClass {
        var name: String
        var code: String?
        var extends: String?
        var properties: [Property] = []
    }

    var commands: Set<String> = []
    var classes: [ScriptingClass] = []

    mutating func read(_ data: Data, include: (URL) -> Data?, depth: Int) {
        let reader = SdefReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        // A malformed definition counts as none, so the demo falls back to Accessibility.
        guard parser.parse() else { return }
        commands.formUnion(reader.commands)
        classes += reader.classes
        guard depth < 2 else { return }
        for url in reader.includes {
            if let included = include(url) { read(included, include: include, depth: depth + 1) }
        }
    }

    var definition: BrowserScriptingDefinition? {
        let window = properties(of: "window", code: "cwin")
        let dialect: BrowserScriptingDialect
        if commands.contains("CrSuExJa"), window.contains(where: { $0.code == "acTa" }) {
            dialect = .chromium
        } else if commands.contains("sfridojs") {
            dialect = .safari
        } else {
            return nil
        }
        let tabCode = dialect == .chromium ? "acTa" : "cTab"
        let tabClass = window.first { $0.code == tabCode }?.type ?? "tab"
        let url = properties(of: tabClass, code: nil).first {
            $0.name.caseInsensitiveCompare("URL") == .orderedSame
        }
        return BrowserScriptingDefinition(
            dialect: dialect, windowsHaveBounds: window.contains { $0.code == "pbnd" },
            tabURLProperty: url.flatMap { ScriptingCode.fourCharCode($0.code) }
                ?? (dialect == .chromium ? ScriptingCode.chromiumURL : ScriptingCode.safariURL))
    }

    /// A class's properties together with every extension's, across suites.
    private func properties(of name: String, code: String?) -> [Property] {
        classes.filter { $0.name == name || $0.extends == name || (code != nil && $0.code == code) }
            .flatMap(\.properties)
    }
}

private final class SdefReader: NSObject, XMLParserDelegate {
    var commands: Set<String> = []
    var classes: [SdefSummary.ScriptingClass] = []
    var includes: [URL] = []
    private var currentClass: SdefSummary.ScriptingClass?
    private var currentProperty: SdefSummary.Property?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "command":
            if let code = attributes["code"] { commands.insert(code) }
        case "class":
            currentClass = SdefSummary.ScriptingClass(name: attributes["name"] ?? "", code: attributes["code"])
        case "class-extension":
            currentClass = SdefSummary.ScriptingClass(name: "", extends: attributes["extends"])
        case "property":
            if let code = attributes["code"] {
                currentProperty = SdefSummary.Property(
                    name: attributes["name"] ?? "", code: code, type: attributes["type"])
            }
        case "type":
            // A property can name its type in a child element instead of an attribute.
            if currentProperty != nil, currentProperty?.type == nil { currentProperty?.type = attributes["type"] }
        case "xi:include", "include":
            if let href = attributes["href"], let url = URL(string: href) { includes.append(url) }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        switch elementName {
        case "property":
            if let property = currentProperty { currentClass?.properties.append(property) }
            currentProperty = nil
        case "class", "class-extension":
            if let currentClass { classes.append(currentClass) }
            currentClass = nil
        default:
            break
        }
    }
}

// MARK: - Apple Events

/// Builds object specifiers by hand, the way AppleScript compiles
/// `URL of active tab of window id "…"`.
enum ScriptingSpecifier {
    static func everyWindow() -> NSAppleEventDescriptor {
        var all = OSType(kAEAll)
        let ordinal = NSAppleEventDescriptor(
            descriptorType: typeAbsoluteOrdinal, bytes: &all, length: MemoryLayout<OSType>.size)
        return object(
            ScriptingCode.window, form: OSType(formAbsolutePosition), data: ordinal ?? NSAppleEventDescriptor.null(),
            in: nil)
    }

    static func window(_ id: ScriptingWindowID) -> NSAppleEventDescriptor {
        object(ScriptingCode.window, form: OSType(formUniqueID), data: id.descriptor, in: nil)
    }

    static func property(_ code: OSType, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(cProperty, form: OSType(formPropertyID), data: NSAppleEventDescriptor(typeCode: code), in: container)
    }

    /// The tab a window shows: its `active tab` (Chromium) or `current tab` (Safari).
    static func tab(of window: ScriptingWindowID, _ definition: BrowserScriptingDefinition) -> NSAppleEventDescriptor {
        property(definition.tabProperty, of: self.window(window))
    }

    /// `container` nil means the application.
    static func object(
        _ desiredClass: OSType, form: OSType, data: NSAppleEventDescriptor, in container: NSAppleEventDescriptor?
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: desiredClass), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier) ?? record
    }
}

enum ScriptingEvent {
    static func get(_ specifier: NSAppleEventDescriptor, target: NSAppleEventDescriptor?) -> NSAppleEventDescriptor {
        event(kAECoreSuite, kAEGetData, target: target, direct: specifier)
    }

    static func set(
        _ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor, target: NSAppleEventDescriptor?
    ) -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAESetData, target: target, direct: specifier)
        event.setParam(value, forKeyword: keyAEData)
        return event
    }

    static func javaScript(
        _ source: String, inTabOf window: ScriptingWindowID, _ definition: BrowserScriptingDefinition,
        target: NSAppleEventDescriptor?
    ) -> NSAppleEventDescriptor {
        let tab = ScriptingSpecifier.tab(of: window, definition)
        let code = NSAppleEventDescriptor(string: source)
        switch definition.dialect {
        case .chromium:
            let event = event(ScriptingCode.chromiumSuite, ScriptingCode.executeJavaScript, target: target, direct: tab)
            event.setParam(code, forKeyword: ScriptingCode.javaScriptParameter)
            return event
        case .safari:
            let event = event(ScriptingCode.safariSuite, ScriptingCode.doJavaScript, target: target, direct: code)
            event.setParam(tab, forKeyword: ScriptingCode.doJavaScriptTab)
            return event
        }
    }

    private static func event(
        _ eventClass: AEEventClass, _ eventID: AEEventID, target: NSAppleEventDescriptor?,
        direct: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass, eventID: eventID, targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(direct, forKeyword: keyDirectObject)
        return event
    }
}

enum ScriptingValues {
    static func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
        guard let descriptor else { return [] }
        guard descriptor.descriptorType == typeAEList else { return [descriptor] }
        return (0..<descriptor.numberOfItems).compactMap { descriptor.atIndex($0 + 1) }
    }

    /// A window's bounds as a global rectangle, from QuickDraw's top, left,
    /// bottom, right or AppleScript's list of left, top, right, bottom.
    static func rect(_ descriptor: NSAppleEventDescriptor) -> CGRect? {
        if descriptor.descriptorType == typeQDRectangle, descriptor.data.count == 8 {
            let edges = descriptor.data.withUnsafeBytes { raw in
                (0..<4).map { CGFloat(raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
            }
            return CGRect(x: edges[1], y: edges[0], width: edges[3] - edges[1], height: edges[2] - edges[0])
        }
        let values = items(descriptor)
        guard descriptor.descriptorType == typeAEList, values.count == 4 else { return nil }
        let edges = values.map { CGFloat($0.doubleValue) }
        return CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
    }

    static func url(_ descriptor: NSAppleEventDescriptor?) -> URL? {
        guard let text = descriptor?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return URL(string: text)
    }
}

/// Runs blocking Apple Event work one job at a time on its own queue, so a
/// slow or hung browser never blocks the main actor.
struct AppleEventChannel: Sendable {
    private let queue = DispatchQueue(label: "com.lndgalante.bettermeets.browser-scripting")

    func run<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}

/// Sends events to one browser process. Every call blocks until the browser
/// answers or the timeout passes, so it's used only on `AppleEventChannel`'s queue.
struct ScriptingConnection {
    static let timeout: TimeInterval = 5
    /// Waits for the reply, never lets the browser show UI, and never asks for
    /// Automation consent, which `BrowserScripting.automationPermission` does.
    static let options: NSAppleEventDescriptor.SendOptions = [
        .waitForReply, .neverInteract, NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
    ]

    private let target: NSAppleEventDescriptor

    init(pid: pid_t) {
        target = NSAppleEventDescriptor(processIdentifier: pid)
    }

    /// The reply's direct object. Errors in the reply come back as a reply, not
    /// a thrown error, so both are checked.
    func send(_ event: NSAppleEventDescriptor, javaScript: Bool = false) throws -> NSAppleEventDescriptor? {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: Self.options, timeout: Self.timeout)
        } catch {
            throw BrowserScriptingError(code: (error as NSError).code, message: nil, duringJavaScript: javaScript)
        }
        if let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 {
            throw BrowserScriptingError(
                code: Int(number), message: reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue,
                duringJavaScript: javaScript)
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject)
    }

    func get(_ specifier: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
        try send(ScriptingEvent.get(specifier, target: target))
    }

    /// Every window's id, name, and index, and bounds when they exist. The
    /// browser lists windows front to back; reading the ids again catches a
    /// reorder in between.
    func windows(withBounds: Bool) throws -> [ScriptingWindowInfo] {
        let every = ScriptingSpecifier.everyWindow()
        func list(_ code: OSType) throws -> [NSAppleEventDescriptor] {
            ScriptingValues.items(try get(ScriptingSpecifier.property(code, of: every)))
        }
        func optionalList(_ code: OSType) throws -> [NSAppleEventDescriptor] {
            do { return try list(code) } catch BrowserScriptingError.failed { return [] }
        }
        for _ in 0..<2 {
            let ids = try list(ScriptingCode.windowID).map { ScriptingWindowID($0) }
            let names = try optionalList(ScriptingCode.name)
            let indexes = try optionalList(ScriptingCode.index)
            let bounds = try withBounds ? optionalList(ScriptingCode.bounds) : []
            guard try list(ScriptingCode.windowID).map({ ScriptingWindowID($0) }) == ids else { continue }
            return ids.enumerated().compactMap { offset, id in
                guard let id else { return nil }
                return ScriptingWindowInfo(
                    id: id, name: names.count == ids.count ? names[offset].stringValue ?? "" : "",
                    index: indexes.count == ids.count ? Int(indexes[offset].int32Value) : offset + 1,
                    bounds: bounds.count == ids.count ? ScriptingValues.rect(bounds[offset]) : nil)
            }
        }
        throw BrowserScriptingError.windowNotFound
    }

    func tabURL(of window: ScriptingWindowID, _ definition: BrowserScriptingDefinition) throws -> URL? {
        let tab = ScriptingSpecifier.tab(of: window, definition)
        return ScriptingValues.url(try get(ScriptingSpecifier.property(definition.tabURLProperty, of: tab)))
    }

    /// Sets the tab's URL property, which loads it in that tab.
    func setTabURL(_ address: String, of window: ScriptingWindowID, _ definition: BrowserScriptingDefinition) throws {
        let tab = ScriptingSpecifier.tab(of: window, definition)
        let url = ScriptingSpecifier.property(definition.tabURLProperty, of: tab)
        _ = try send(ScriptingEvent.set(url, to: NSAppleEventDescriptor(string: address), target: target))
    }

    func runJavaScript(
        _ source: String, inTabOf window: ScriptingWindowID, _ definition: BrowserScriptingDefinition
    ) throws -> NSAppleEventDescriptor? {
        try send(ScriptingEvent.javaScript(source, inTabOf: window, definition, target: target), javaScript: true)
    }
}

// MARK: - Codes

/// Four-character Apple Event codes, as the browsers' scripting definitions name them.
enum ScriptingCode {
    static let window = OSType(cWindow)
    static let windowID = code("ID  ")
    static let name = code("pnam")
    static let index = code("pidx")
    static let bounds = code("pbnd")
    static let activeTab = code("acTa")
    static let currentTab = code("cTab")
    static let chromiumURL = code("URL ")
    static let safariURL = code("pURL")
    static let chromiumSuite = code("CrSu")
    static let executeJavaScript = code("ExJa")
    static let javaScriptParameter = code("JvSc")
    static let safariSuite = code("sfri")
    static let doJavaScript = code("dojs")
    static let doJavaScriptTab = code("dcnm")

    /// Four Mac Roman characters as a code, such as "cwin"; nil for anything else.
    static func fourCharCode(_ text: String) -> OSType? {
        guard let bytes = text.data(using: .macOSRoman), bytes.count == 4 else { return nil }
        return bytes.reduce(0) { $0 << 8 | OSType($1) }
    }

    private static func code(_ text: String) -> OSType {
        fourCharCode(text) ?? 0
    }
}
