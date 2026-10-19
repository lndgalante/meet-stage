import Foundation
import MeetStageCore
import Testing

@testable import MeetStage

@Suite("Demo input routes")
struct DemoInputRouteTests {
    private static let javaScriptOn = DemoBrowserAccess(scriptable: true, automation: .granted, javaScript: .on)
    private static let notProbed = DemoBrowserAccess(scriptable: true, automation: .notDetermined, javaScript: .unknown)
    private static let javaScriptOff = DemoBrowserAccess(scriptable: true, automation: .granted, javaScript: .off)
    private static let denied = DemoBrowserAccess(scriptable: true, automation: .denied, javaScript: .unknown)

    private func routes(
        _ input: DemoInputRoute.Input, background: Bool = true, web: Bool = true,
        _ browser: DemoBrowserAccess = javaScriptOn, from recorded: DemoStepRoute = .accessibility
    ) -> [DemoInputRoute] {
        DemoInputRoute.routes(for: input, background: background, inWebArea: web, browser: browser, from: recorded)
    }

    @Test("Presenting keeps today's paths: Accessibility first, then real input with the app in front")
    func presenting() {
        #expect(routes(.click, background: false) == [.accessibility, .foreground])
        #expect(routes(.click, background: false, from: .pointer) == [.foreground])
        #expect(routes(.type, background: false) == [.accessibility, .foreground])
        #expect(routes(.type, background: false, web: false, .none) == [.accessibility, .foreground])
        #expect(routes(.submit, background: false) == [.foreground])
        #expect(routes(.submit, background: false, web: false) == [.foreground])
        #expect(routes(.key(.tab), background: false) == [.foreground])
        #expect(routes(.navigate, background: false) == [.foreground])
        #expect(routes(.scroll, background: false) == [.foreground])
        #expect(routes(.scrollToVisible, background: false) == [.accessibility])
        // Accessibility's stand-ins for keys and scrolling are for the background only.
        for key in DemoKey.allCases {
            #expect(routes(.key(key), background: false, web: false, .none) == [.foreground])
        }
        #expect(routes(.scroll, background: false, web: false, .none) == [.foreground])
    }

    @Test("Building in a page with JavaScript on scripts the page before borrowing the screen")
    func pageWithJavaScript() {
        #expect(routes(.click) == [.accessibility, .browser, .borrowedScreen])
        #expect(routes(.type) == [.accessibility, .browser, .selectedText, .borrowedScreen])
        #expect(routes(.submit) == [.browser, .borrowedScreen])
        #expect(routes(.key(.tab)) == [.browser, .borrowedScreen])
        #expect(routes(.scroll) == [.browser, .borrowedScreen])
        #expect(routes(.navigate) == [.browser, .borrowedScreen])
        #expect(routes(.scrollToVisible) == [.accessibility])
    }

    @Test("A browser not probed yet this run still tries its page script")
    func notProbedYet() {
        #expect(routes(.click, Self.notProbed) == [.accessibility, .browser, .borrowedScreen])
        #expect(routes(.navigate, Self.notProbed) == [.browser, .borrowedScreen])
    }

    @Test("A pointer step goes straight to a real click on the borrowed screen")
    func pointerSteps() {
        #expect(routes(.click, from: .pointer) == [.borrowedScreen])
        #expect(routes(.click, web: false, .none, from: .pointer) == [.borrowedScreen])
    }

    @Test("A step that needed the page's click starts there, and gets a real click where the page can't")
    func pageScriptSteps() {
        #expect(routes(.click, from: .pageScript) == [.browser, .borrowedScreen])
        #expect(routes(.click, Self.javaScriptOff, from: .pageScript) == [.borrowedScreen])
        #expect(routes(.click, Self.denied, from: .pageScript) == [.borrowedScreen])
        #expect(routes(.click, web: false, .none, from: .pageScript) == [.borrowedScreen])
        // Presenting keeps real input.
        #expect(routes(.click, background: false, from: .pageScript) == [.foreground])
    }

    @Test("A key or a scroll that needed real input goes straight to it")
    func realInputSteps() {
        #expect(routes(.key(.escape), web: false, .none, from: .realKey) == [.borrowedScreen])
        #expect(routes(.key(.escape), from: .realKey) == [.borrowedScreen])
        #expect(routes(.scroll, web: false, .none, from: .realWheel) == [.borrowedScreen])
        #expect(routes(.scroll, from: .realWheel) == [.borrowedScreen])
        #expect(routes(.key(.down), background: false, web: false, .none, from: .realKey) == [.foreground])
        #expect(routes(.scroll, background: false, web: false, .none, from: .realWheel) == [.foreground])
    }

    @Test("Only the route a step needed and those after it stay open to it")
    func recordedRoutesAllow() {
        let all: [DemoInputRoute] = [.accessibility, .browser, .selectedText, .borrowedScreen, .foreground]
        #expect(all.filter(DemoStepRoute.accessibility.allows) == all)
        #expect(all.filter(DemoStepRoute.pageScript.allows) == [.browser, .borrowedScreen, .foreground])
        for route in [DemoStepRoute.pointer, .realKey, .realWheel] {
            #expect(all.filter(route.allows) == [.borrowedScreen, .foreground])
        }
    }

    @Test("With JavaScript off, page steps borrow the screen, but addresses still open in the background")
    func javaScriptOff() {
        #expect(routes(.click, Self.javaScriptOff) == [.accessibility, .borrowedScreen])
        #expect(routes(.type, Self.javaScriptOff) == [.accessibility, .selectedText, .borrowedScreen])
        #expect(routes(.submit, Self.javaScriptOff) == [.borrowedScreen])
        #expect(routes(.key(.tab), Self.javaScriptOff) == [.borrowedScreen])
        // A page's keys and scrolling never take Accessibility's stand-ins.
        #expect(routes(.key(.escape), Self.javaScriptOff) == [.borrowedScreen])
        #expect(routes(.scroll, Self.javaScriptOff) == [.borrowedScreen])
        #expect(routes(.navigate, Self.javaScriptOff) == [.browser, .borrowedScreen])
    }

    @Test("Without Automation, nothing goes through the browser's scripting")
    func automationOff() {
        let access = Self.denied
        #expect(routes(.click, access) == [.accessibility, .borrowedScreen])
        #expect(routes(.submit, access) == [.borrowedScreen])
        #expect(routes(.navigate, access) == [.borrowedScreen])
        #expect(!access.canOpenAddresses)
        #expect(!access.canRunPageScripts)
    }

    @Test("Only keys the page script carries out go through it; arrows always get the real key")
    func keys() {
        for key in [DemoKey.tab, .shiftTab, .escape, .pageUp, .pageDown] {
            #expect(key.pageScriptActsLikeTheKey)
            #expect(routes(.key(key)) == [.browser, .borrowedScreen])
        }
        for key in [DemoKey.up, .down, .left, .right] {
            #expect(!key.pageScriptActsLikeTheKey)
            #expect(routes(.key(key)) == [.borrowedScreen])
            #expect(routes(.key(key), background: false) == [.foreground])
        }
    }

    @Test("A web step that borrowed the screen names the setting its own access was missing")
    func tipKinds() {
        // Automation turned down at the macOS prompt, before any event was sent.
        #expect(DemoBrowserTip.Kind.missing(in: Self.denied, needsJavaScript: true) == .automation)
        #expect(DemoBrowserTip.Kind.missing(in: Self.denied, needsJavaScript: false) == .automation)
        #expect(DemoBrowserTip.Kind.missing(in: Self.javaScriptOff, needsJavaScript: true) == .javaScript)
        // Opening an address needs no JavaScript.
        #expect(DemoBrowserTip.Kind.missing(in: Self.javaScriptOff, needsJavaScript: false) == nil)
        #expect(DemoBrowserTip.Kind.missing(in: Self.notProbed, needsJavaScript: true) == nil)
        #expect(DemoBrowserTip.Kind.missing(in: Self.javaScriptOn, needsJavaScript: true) == nil)
        #expect(DemoBrowserTip.Kind.missing(in: .none, needsJavaScript: true) == nil)
    }

    @Test("The page's own click runs only on controls the policy allows outright, judging a dialog's as a dialog's")
    func pageClicks() throws {
        func allowed(_ role: String?, _ label: String, _ fallback: DemoPolicyElement.Kind? = nil, dialog: Bool = false)
            throws -> Bool
        {
            try DemoInputRoute.pageClickAllowed(webRole: role, label: label, fallback: fallback, inDialog: dialog)
        }
        #expect(try allowed("button", "Search"))
        // No web role: the kind Accessibility gives the target at the point.
        #expect(try allowed("", "Search", .button))
        #expect(try !allowed(nil, "Search"))
        // Questions the presenter would be asked fall to the real click.
        #expect(try !allowed("link", "Delete account"))
        #expect(try !allowed("menuitem", "Delete"))
        #expect(try !allowed("button", ""))
        // A dialog's button other than a dismissal asks, so it falls to the real click too.
        #expect(try allowed("button", "Continue"))
        #expect(try !allowed("button", "Continue", dialog: true))
        #expect(try allowed("button", "Close", dialog: true))
        // Denials stop the step.
        #expect(throws: DemoError.self) { try allowed("button", "Delete account") }
    }

    @Test("A native app's input uses Accessibility, then borrows the screen; Return tries the field's confirm")
    func nativeApp() {
        #expect(routes(.click, web: false, .none) == [.accessibility, .borrowedScreen])
        // A field that ignores a new value may still take the text as its selection's replacement.
        #expect(routes(.type, web: false, .none) == [.accessibility, .selectedText, .borrowedScreen])
        #expect(routes(.submit, web: false, .none) == [.accessibility, .borrowedScreen])
        #expect(routes(.scroll, web: false, .none) == [.accessibility, .borrowedScreen])
        #expect(routes(.navigate, web: false, .none) == [.borrowedScreen])
    }

    @Test("In an app's own views, Escape, Up, Down, Page Up and Page Down try Accessibility; others borrow")
    func nativeKeys() {
        for key in [DemoKey.escape, .up, .down, .pageUp, .pageDown] {
            #expect(key.accessibilityActsLikeTheKey)
            #expect(routes(.key(key), web: false, .none) == [.accessibility, .borrowedScreen])
        }
        for key in [DemoKey.tab, .shiftTab, .left, .right] {
            #expect(!key.accessibilityActsLikeTheKey)
            #expect(routes(.key(key), web: false, .none) == [.borrowedScreen])
        }
        // A page keeps its own script first, and arrows over a page still get the real key.
        #expect(routes(.key(.escape)) == [.browser, .borrowedScreen])
        #expect(routes(.key(.pageDown)) == [.browser, .borrowedScreen])
        #expect(routes(.key(.down)) == [.borrowedScreen])
    }

    @Test("Browser chrome outside the page never gets page scripts or Accessibility's confirm")
    func browserChrome() {
        #expect(routes(.key(.tab), web: false) == [.borrowedScreen])
        #expect(routes(.key(.escape), web: false) == [.accessibility, .borrowedScreen])
        #expect(routes(.scroll, web: false) == [.accessibility, .borrowedScreen])
        #expect(routes(.type, web: false) == [.accessibility, .selectedText, .borrowedScreen])
        // A page's field in an app BetterMeets can't script still gets a real Return, never confirm.
        #expect(routes(.submit, web: true, .none) == [.borrowedScreen])
    }

    @Test("Up and Down move a list's selection one row, staying inside the list")
    func rowSelection() {
        #expect(DemoAccessibilityMotion.row(after: [2], count: 5, down: true) == 3)
        #expect(DemoAccessibilityMotion.row(after: [2], count: 5, down: false) == 1)
        // At either end there's nothing to move to.
        #expect(DemoAccessibilityMotion.row(after: [4], count: 5, down: true) == nil)
        #expect(DemoAccessibilityMotion.row(after: [0], count: 5, down: false) == nil)
        // With several selected, Down goes below the last and Up above the first.
        #expect(DemoAccessibilityMotion.row(after: [1, 3], count: 5, down: true) == 4)
        #expect(DemoAccessibilityMotion.row(after: [3, 1], count: 5, down: false) == 0)
        // With none selected, Down selects the first row and Up the last.
        #expect(DemoAccessibilityMotion.row(after: [], count: 5, down: true) == 0)
        #expect(DemoAccessibilityMotion.row(after: [], count: 5, down: false) == 4)
        #expect(DemoAccessibilityMotion.row(after: [9], count: 5, down: true) == 0)
        #expect(DemoAccessibilityMotion.row(after: [], count: 0, down: true) == nil)
        #expect(DemoAccessibilityMotion.row(after: [0], count: 1, down: true) == nil)
    }

    @Test("A scroll bar's value moves by the distance over the part of the content out of view")
    func scrollBarValues() throws {
        // 1,400 points of content in a 400-point view leave 1,000 to scroll.
        #expect(DemoAccessibilityMotion.scrollValue(from: 0, by: 100, visible: 400, content: 1_400) == 0.1)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0.5, by: -250, visible: 400, content: 1_400) == 0.25)
        let page = try #require(
            DemoAccessibilityMotion.scrollValue(
                from: 0, by: DemoAccessibilityMotion.pageFraction * 400, visible: 400, content: 1_400))
        #expect(abs(page - 0.35) < 1e-9)
        // Kept inside 0…1.
        #expect(DemoAccessibilityMotion.scrollValue(from: 0.95, by: 640, visible: 400, content: 1_400) == 1)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0.05, by: -640, visible: 400, content: 1_400) == 0)
        #expect(DemoAccessibilityMotion.scrollValue(from: 1.2, by: -100, visible: 400, content: 1_400) == 0.9)
        // Already at the edge in that direction, or content that fits: nothing to scroll.
        #expect(DemoAccessibilityMotion.scrollValue(from: 1, by: 100, visible: 400, content: 1_400) == nil)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0, by: -100, visible: 400, content: 1_400) == nil)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0.999_6, by: 100, visible: 400, content: 1_400) == nil)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0, by: 100, visible: 400, content: 400) == nil)
        #expect(DemoAccessibilityMotion.scrollValue(from: 0, by: 0, visible: 400, content: 1_400) == nil)
        #expect(DemoAccessibilityMotion.scrollValue(from: .nan, by: 100, visible: 400, content: 1_400) == nil)
    }

    @Test("Steps saved with usesPointer still load, as needing a real click, and save their route instead")
    func decodesSavedRoutes() throws {
        let step = DemoStep(
            title: "Open", script: "", holdSeconds: 0.4, action: .press(.escape),
            pre: ScreenSignature(urlKey: nil, selected: [], headings: [], dialogOpen: false))
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(step)) as? [String: Any])
        #expect(saved["route"] as? String == "accessibility")
        #expect(saved["usesPointer"] == nil)
        func load(_ changes: [String: Any?]) throws -> DemoStep {
            var json = saved
            for (key, value) in changes { json[key] = value }
            return try JSONDecoder().decode(DemoStep.self, from: JSONSerialization.data(withJSONObject: json))
        }
        #expect(try load(["route": nil]) == step)
        #expect(try load(["route": nil, "usesPointer": true]).route == .pointer)
        #expect(try load(["route": nil, "usesPointer": false]).route == .accessibility)
        // A route saved alongside wins over the old flag.
        #expect(try load(["route": "pageScript", "usesPointer": true]).route == .pageScript)
        let old = try load(["route": nil, "usesPointer": true])
        #expect(try JSONDecoder().decode(DemoStep.self, from: JSONEncoder().encode(old)) == old)
    }

    @Test("A scroll that needed no real wheel saves its hint as before, so fingerprints hold")
    func revealHintsKeepTheirBytes() throws {
        let hint = RevealHint(container: nil, directionDown: true, count: 2)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(hint)) as? [String: Any])
        #expect(Set(json.keys) == ["directionDown", "count"])
        var real = hint
        real.route = .realWheel
        #expect(try JSONDecoder().decode(RevealHint.self, from: JSONEncoder().encode(real)) == real)
    }

    @Test("Building, testing and going back to the start drive in the background; presenting in front")
    func driveModes() {
        #expect(DemoPhase.scouting.driveMode == .background(.building))
        #expect(DemoPhase.returning(then: .verify).driveMode == .background(.returning))
        #expect(DemoPhase.returning(then: .ready).driveMode == .background(.returning))
        #expect(DemoPhase.returning(then: .compose).driveMode == .background(.returning))
        #expect(DemoPhase.returning(then: .play).driveMode == .foreground)
        #expect(DemoPhase.running(.verify, next: 2, current: 1).driveMode == .background(.testing))
        #expect(DemoPhase.running(.present, next: 0, current: nil).driveMode == .foreground)
        #expect(DemoPhase.ready.driveMode == nil)
        #expect(DemoPhase.paused(.verify, next: 1, current: 0, reason: .user).driveMode == nil)
        #expect(DemoPhase.scoutPaused(.user).driveMode == nil)
        #expect(DemoDriveMode.background(.testing).isBackground)
        #expect(!DemoDriveMode.foreground.isBackground)
    }

    @Test("A page control's role maps onto the policy's kinds, so destructive labels stay denied")
    func webRoles() {
        #expect(DemoInputRoute.policyKind(webRole: "button") == .button)
        #expect(DemoInputRoute.policyKind(webRole: "link") == .link)
        #expect(DemoInputRoute.policyKind(webRole: "menuitem") == .menuItem)
        #expect(DemoInputRoute.policyKind(webRole: "switch") == .checkbox)
        #expect(DemoInputRoute.policyKind(webRole: "menuitemradio") == .radio)
        #expect(DemoInputRoute.policyKind(webRole: "searchbox") == .field)
        #expect(DemoInputRoute.policyKind(webRole: "gridcell") == .cell)
        #expect(DemoInputRoute.policyKind(webRole: "") == nil)
        #expect(DemoInputRoute.policyKind(webRole: nil) == nil)
    }

    @Test("A tip names the browser and where its setting lives")
    func tips() {
        let chrome = DemoBrowserTip(kind: .javaScript, browser: "Google Chrome", bundleID: "com.google.Chrome")
        #expect(chrome.message.contains("in View › Developer to keep it in the background"))
        #expect(chrome.message.hasPrefix("Google Chrome had to come forward for some steps."))
        let safari = DemoBrowserTip(kind: .javaScript, browser: "Safari", bundleID: "com.apple.Safari")
        #expect(safari.message.contains("Allow JavaScript from Apple Events in Develop › Developer Settings"))
        let dia = DemoBrowserTip(kind: .javaScript, browser: "Dia", bundleID: "company.thebrowser.dia")
        #expect(dia.message.contains("in its Developer menu"))
        let automation = DemoBrowserTip(kind: .automation, browser: "Dia", bundleID: "company.thebrowser.dia")
        #expect(automation.message.contains("System Settings → Privacy & Security → Automation"))
        #expect(automation.key != dia.key)
        #expect(dia.key == "company.thebrowser.dia|javaScript")
    }
}
