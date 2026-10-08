import Foundation
import Testing

@testable import MeetStage

private struct TestKeyStore: DemoKeyStore {
    var key: String? { "test-key" }
    var hasKey: Bool { true }
    func save(_ value: String) -> Bool { true }
}

@Suite("Demo session")
@MainActor
struct DemoSessionTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "demo-session-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: DemoSession.consentKey)
        defaults.set(true, forKey: "demo.actuationApproved.com.example.app")
        return defaults
    }

    private func searchModel() -> ScriptedModel {
        ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: "")),
            reply(.click(elementID: 2, title: "Open the first result", script: "")),
            reply(.present([ScoutBeat(effect: .draw, elementIDs: [2], title: "Point at download", script: "Grab it here.")])),
            reply(.finish(title: "Find The Matrix", startDescription: "Subtis home", closingScript: "")),
        ])
    }

    private func session(_ app: FakeApp, _ model: ScriptedModel, _ defaults: UserDefaults) -> DemoSession {
        var limits = fastScoutLimits()
        limits.beatPreview = .milliseconds(1)
        let session = DemoSession(
            driver: app, defaults: defaults, model: model, keyStore: TestKeyStore(), observesUserInput: false,
            scoutLimits: limits, opensWindows: false)
        session.replayTuning = (0.001, .milliseconds(300))
        return session
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting")
    }

    @Test("Build explores the app, returns to the start, checks the demo and leaves it ready to play")
    func buildCheckPlay() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let session = session(app, searchModel(), defaults)
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        #expect(session.phase == .scouting)

        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        #expect(session.isChecked)
        #expect(app.current == "home")
        let pass = ["type The Matrix ⏎", "click The Matrix (1999)", "open https://subtis.io/"]
        #expect(app.log == pass + pass)
        // The script written during the check is kept, and words don't undo the check.
        #expect(session.demo?.openingScript == "Let's find a movie.")
        #expect(session.demo?.steps.first?.title == "Polished Search The Matrix")
        #expect(session.demo?.closingScript == "That's the whole flow.")

        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log == pass + pass + Array(pass.prefix(2)))

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        #expect(relaunched.phase == .ready)
        #expect(relaunched.demo?.steps.count == 3)
    }

    @Test("Play from the wrong screen goes back to the start first, then performs from the top")
    func playReturnsToStartFirst() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { session.phase == .ready && !session.isWritingScript }
        app.current = "movie"
        app.log = []
        session.play()
        try await waitUntil { session.phase == .finished }
        #expect(app.log == ["open https://subtis.io/", "type The Matrix ⏎", "click The Matrix (1999)"])
    }

    @Test("A check paused partway continues where it stopped and still ends checked")
    func resumesPausedCheck() async throws {
        let app = subtisApp()
        let session = session(app, searchModel(), defaults())
        var inputs = 0
        app.beforeInput = { input in
            inputs += 1
            // Inputs: scout type, scout click, return to start, check type, check click.
            if inputs == 5 { session.pause() }
        }
        session.prompt = "Search for The Matrix and open the result"
        session.build()
        try await waitUntil { if case .paused(.verify, _, _, _) = session.phase { true } else { false } }
        #expect(session.phase.nextStep == 1)
        session.play()
        try await waitUntil { session.phase == .ready }
        #expect(session.isChecked)
    }

    @Test("Stopping a build keeps its steps; a relaunch offers to keep building")
    func stopAndRelaunch() async throws {
        let app = subtisApp()
        let defaults = defaults()
        let model = ScriptedModel([
            reply(.typeText(elementID: 1, text: "The Matrix", submit: true, title: "Search The Matrix", script: ""))
        ])
        let session = session(app, model, defaults)
        session.prompt = "Search for The Matrix"
        app.beforeInput = { _ in session.pause() }
        session.build()
        try await waitUntil { if case .scoutPaused = session.phase { true } else { false } }
        #expect(session.phase == .scoutPaused(.user))

        let relaunched = self.session(app, ScriptedModel([]), defaults)
        if case .scoutPaused = relaunched.phase {} else if relaunched.phase != .composing {
            Issue.record("Unexpected phase \(relaunched.phase)")
        }
        #expect(relaunched.prompt == "Search for The Matrix")
    }

    @Test("A build asks for consent once per app before touching it")
    func asksForConsent() {
        let app = subtisApp()
        let defaults = UserDefaults(suiteName: "demo-session-consent-\(UUID().uuidString)")!
        defaults.set(true, forKey: DemoSession.consentKey)
        let session = session(app, searchModel(), defaults)
        session.prompt = "Search for The Matrix"
        session.build()
        #expect(session.needsActuationConsent)
        #expect(session.phase == .composing)
        #expect(app.log.isEmpty)
    }
}
