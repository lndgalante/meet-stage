import Foundation
import Testing
@testable import MeetStage

@Suite("Demo action executor")
struct DemoActionExecutorTests {
    @Test("Stops before posting to a different focused field")
    func stopsOnFocusedFieldChange() async {
        let harness = TypingHarness(focuses: [1, 1, 2, 2])

        await DemoActionExecutor.typeCharacters(
            "abcd",
            pid: 42,
            expectedFocus: .testing(1),
            isStillValid: { true },
            resolveFocusedElement: { _ in harness.nextFocus() },
            post: { harness.record($0) },
            sleep: { _ in }
        )

        #expect(harness.postedText == "ab")
        #expect(harness.focusChecks == 3)
    }

    @Test("Revalidates the source before every character")
    func revalidatesSourcePerCharacter() async {
        let harness = TypingHarness(focuses: [1, 1, 1, 1], validChecksBeforeFailure: 2)

        await DemoActionExecutor.typeCharacters(
            "abcd",
            pid: 42,
            expectedFocus: .testing(1),
            isStillValid: { harness.isStillValid() },
            resolveFocusedElement: { _ in harness.nextFocus() },
            post: { harness.record($0) },
            sleep: { _ in }
        )

        #expect(harness.postedText == "ab")
        #expect(harness.validityChecks == 3)
        #expect(harness.focusChecks == 2)
    }
}

private final class TypingHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var focuses: [Int]
    private var characters: [Character] = []
    private let validChecksBeforeFailure: Int?
    private var storedFocusChecks = 0
    private var storedValidityChecks = 0

    init(focuses: [Int], validChecksBeforeFailure: Int? = nil) {
        self.focuses = focuses
        self.validChecksBeforeFailure = validChecksBeforeFailure
    }

    func nextFocus() -> DemoActionExecutor.EditableFocusToken? {
        lock.withLock {
            storedFocusChecks += 1
            guard !focuses.isEmpty else { return nil }
            return .testing(focuses.removeFirst())
        }
    }

    func isStillValid() -> Bool {
        lock.withLock {
            storedValidityChecks += 1
            return validChecksBeforeFailure.map { storedValidityChecks <= $0 } ?? true
        }
    }

    func record(_ character: Character) {
        lock.withLock {
            characters.append(character)
        }
    }

    var postedText: String {
        lock.withLock { String(characters) }
    }

    var focusChecks: Int {
        lock.withLock { storedFocusChecks }
    }

    var validityChecks: Int {
        lock.withLock { storedValidityChecks }
    }
}
