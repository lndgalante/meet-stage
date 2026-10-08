import Foundation
import Testing

@testable import MeetStage

@Suite("Script following")
struct ScriptFollowerTests {
    private let line = "The status tells us whether it's confirmed on-chain, so you don't have to check an explorer."

    @Test("Follows a line read aloud, word by word, with the recognizer's partial words")
    func followsReading() {
        var follower = ScriptFollower(line: line)
        #expect(follower.nextWord == 0)
        follower.advance(heard: "the status")
        #expect(follower.nextWord == 2)
        follower.advance(heard: "the status tells us wheth")
        #expect(follower.nextWord == 5)
        follower.advance(heard: "the status tells us whether it's confirmed on chain")
        #expect(follower.nextWord == 8)
        #expect(!follower.isComplete)
        follower.advance(heard: "whether it's confirmed on chain so you don't have to check an explorer")
        #expect(follower.isComplete)
    }

    @Test("Tolerates misheard words and swallowed endings")
    func toleratesNoise() {
        var follower = ScriptFollower(line: "Here are the transactions for this account.")
        follower.advance(heard: "here are the transaction for")
        #expect(follower.nextWord == 5)
        follower.advance(heard: "here are the transaction for this")
        // Only the last word is left, which the recognizer often hasn't caught yet.
        #expect(follower.isComplete)
    }

    @Test("An ad-lib that shares one word with a later sentence doesn't jump ahead")
    func ignoresDistantSingleWords() {
        var follower = ScriptFollower(line: line)
        follower.advance(heard: "um so basically you know")
        #expect(follower.nextWord == 0)
        follower.advance(heard: "anyway explorer")
        #expect(follower.nextWord == 0)
    }

    @Test("Never moves backwards when an earlier word is repeated")
    func monotonic() {
        var follower = ScriptFollower(line: "Open the details, then the details panel shows the fee.")
        follower.advance(heard: "open the details then the details panel")
        let position = follower.nextWord
        follower.advance(heard: "the details")
        #expect(follower.nextWord == position)
    }

    @Test("Skipping marks the line said")
    func skip() {
        var follower = ScriptFollower(line: line)
        follower.complete()
        #expect(follower.isComplete)
        #expect(ScriptFollower(line: "").isComplete)
    }
}

@Suite("Presenter pacing")
@MainActor
struct PresenterPacingTests {
    @Test("A line always gets at least the time it takes to say it")
    func speakingTime() {
        let line = Array(repeating: "word", count: 20).joined(separator: " ")
        #expect(DemoStep.speakingTime(for: line) == 8)
        #expect(DemoStep.hold(for: line, action: .press(.escape)) >= 8)
        #expect(DemoStep.hold(for: "", action: .press(.escape)) < 1)
    }

    @Test("Without a listening microphone the hold uses the timer, and Skip ends it early")
    func holdFallsBackAndSkips() async throws {
        let defaults = UserDefaults(suiteName: "prompter-\(UUID().uuidString)")!
        let prompter = PresenterPrompter(defaults: defaults)
        #expect(prompter.followsVoice)
        prompter.show(.step(0), text: "Here are the transactions for this account.", heading: "", upNext: nil, position: nil)
        let started = ContinuousClock.now
        try await prompter.hold(seconds: 0.2)
        #expect(ContinuousClock.now - started < .seconds(1))

        let waiting = Task { try await prompter.hold(seconds: 30) }
        try await Task.sleep(for: .milliseconds(150))
        prompter.skipLine()
        try await waiting.value
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    @Test("Short words must match exactly, and a jump needs the words it skips")
    func strictMatching() {
        #expect(!ScriptFollower.similar("then", "the", partial: false))
        #expect(!ScriptFollower.similar("your", "you", partial: false))
        var follower = ScriptFollower(line: "Pick a movie, and the movie page opens with its subtitles.")
        follower.advance(heard: "pick a movie")
        #expect(follower.nextWord == 3)
        follower.advance(heard: "pick a movie page")
        #expect(follower.nextWord == 3)
    }

    @Test("Following your voice, a line holds until it's said, with no timer")
    func voiceHoldsHaveNoTimer() async throws {
        let prompter = PresenterPrompter(defaults: UserDefaults(suiteName: "prompter-\(UUID().uuidString)")!)
        prompter.listener.simulateHearing("")
        prompter.show(.step(0), text: "Here are the transactions for this account.", heading: "", upNext: nil, position: nil)
        let holding = Task { try await prompter.hold(seconds: 0.1) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(prompter.isWaitingForVoice)
        prompter.listener.simulateHearing("here are the transactions for this", isFinal: true)
        try await holding.value
    }

    @Test("A step without a line moves on when you say “next” and pause")
    func sayNext() async throws {
        let prompter = PresenterPrompter(defaults: UserDefaults(suiteName: "prompter-\(UUID().uuidString)")!)
        prompter.listener.simulateHearing("")
        prompter.show(.step(1), text: "", heading: "", upNext: nil, position: nil)
        let holding = Task { try await prompter.hold(seconds: 0.1) }
        try await Task.sleep(for: .milliseconds(300))
        prompter.listener.simulateHearing("okay next", isFinal: true)
        try await holding.value
    }

    @Test("“Next” as a word of the line is reading, not a command")
    func nextInsideTheLine() async throws {
        let prompter = PresenterPrompter(defaults: UserDefaults(suiteName: "prompter-\(UUID().uuidString)")!)
        prompter.listener.simulateHearing("")
        prompter.show(.step(2), text: "Next we open the details panel for this row.", heading: "", upNext: nil, position: nil)
        let holding = Task { try await prompter.hold(seconds: 0.1) }
        prompter.listener.simulateHearing("next", isFinal: true)
        try await Task.sleep(for: .milliseconds(900))
        #expect(prompter.isWaitingForVoice)
        #expect(prompter.follower.nextWord == 1)
        prompter.skipLine()
        try await holding.value
    }
}
