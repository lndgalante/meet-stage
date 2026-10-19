import CoreGraphics
import Foundation
import Testing

@testable import MeetStage

@Suite("Demo screen lease")
@MainActor
struct DemoScreenLeaseTests {
    @Test("Goes at once while the person is away, then gives their app the front back")
    func goesAtOnceWhenIdle() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        var tries = 0
        try await lease.borrow(desk.target) { token in
            tries += 1
            #expect(desk.frontPID == FakeDesk.demoPID)
            #expect(desk.isWatching)
            try token.commit {}
        }
        #expect(tries == 1)
        #expect(log.waiting.isEmpty)
        #expect(lease.waited == .zero)
        #expect(log.borrowing == [true, false])
        #expect(desk.restores == [FakeDesk.personPID])
        #expect(desk.frontPID == FakeDesk.personPID)
        #expect(!desk.isWatching)
    }

    @Test("Waits until the person pauses, and starts counting again when they carry on")
    func waitsForAPause() async throws {
        let desk = FakeDesk()
        desk.lastSystemInput = desk.now.advanced(by: .milliseconds(-200))
        var typedAgain = false
        desk.onSleep = { desk in
            guard !typedAgain, desk.elapsed >= .milliseconds(800) else { return }
            typedAgain = true
            desk.personTypes()
        }
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        var startedAt: Duration?
        var waitingWhenStarted: [Bool] = []
        try await lease.borrow(desk.target) { token in
            startedAt = desk.elapsed
            waitingWhenStarted = log.waiting
            try token.commit {}
        }
        let started = try #require(startedAt)
        // The system’s idle time is in floating-point seconds, so it may take one more poll.
        #expect(started >= .milliseconds(2_300))
        #expect(started <= .milliseconds(2_400))
        #expect(waitingWhenStarted == [true, false])
        #expect(log.waiting == [true, false])
        // Up to bringing the window forward, all of it went to waiting, which the timings log counts.
        #expect(lease.waited >= .milliseconds(2_300))
        #expect(lease.waited <= started)
    }

    @Test("Input before the commit puts everything back and tries again at the next pause")
    func retriesWhenInterruptedBeforeCommit() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        var tries: [Duration] = []
        var commits = 0
        try await lease.borrow(desk.target) { token in
            tries.append(desk.elapsed)
            if tries.count == 1 { desk.personTypes() }
            try token.commit { commits += 1 }
        }
        #expect(tries.count == 2)
        #expect(commits == 1)
        #expect(tries.count == 2 && tries[1] - tries[0] >= .milliseconds(1_500))
        #expect(desk.raises == 2)
        #expect(desk.restores == [FakeDesk.personPID, FakeDesk.personPID])
        #expect(log.waiting == [true, false])
        #expect(log.borrowing == [true, false, true, false])
    }

    @Test("Losing focus before the commit counts as an interruption")
    func retriesFocusLossBeforeCommit() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        var tries = 0
        try await lease.borrow(desk.target) { token in
            tries += 1
            if tries == 1 { throw DemoError.focusChanged }
            try token.commit {}
        }
        #expect(tries == 2)
    }

    @Test("Another app taking the front before the commit vetoes it")
    func vetoesWhenAnotherAppTakesTheFront() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        var tries = 0
        var commits = 0
        try await lease.borrow(desk.target) { token in
            tries += 1
            if tries == 1 { desk.frontPID = 77 }
            try token.commit { commits += 1 }
        }
        #expect(tries == 2)
        #expect(commits == 1)
    }

    @Test("A step that failed for its own reasons isn't retried")
    func keepsUnrelatedFailures() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        var tries = 0
        await #expect(throws: DemoError.inputNotDelivered("Save")) {
            try await lease.borrow(desk.target) { _ in
                tries += 1
                throw DemoError.inputNotDelivered("Save")
            }
        }
        #expect(tries == 1)
        #expect(desk.restores == [FakeDesk.personPID])
    }

    @Test("Once the step commits, input is its own business and errors come through")
    func neverRetriesAfterCommit() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        var tries = 0
        await #expect(throws: DemoError.focusChanged) {
            try await lease.borrow(desk.target) { token in
                tries += 1
                try token.commit {}
                desk.personTypes()
                try token.check()
                throw DemoError.focusChanged
            }
        }
        #expect(tries == 1)
        #expect(desk.restores == [FakeDesk.personPID])
    }

    @Test("Gives up after the retry limit without ever committing, saying it never got a pause")
    func givesUpAfterTheLimit() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk, limits: .init(tries: 3))
        var tries = 0
        var commits = 0
        await #expect(throws: DemoError.noPause("Ledger")) {
            try await lease.borrow(desk.target) { token in
                tries += 1
                desk.personTypes()
                try token.commit { commits += 1 }
            }
        }
        #expect(tries == 3)
        #expect(commits == 0)
        #expect(desk.restores.count == 3)
        #expect(!desk.isWatching)
    }

    @Test("Cancelling while it waits stops without bringing anything forward")
    func cancelsWhileWaiting() async throws {
        let desk = FakeDesk()
        desk.keepsTyping = true
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        let task = Task { try await lease.borrow(desk.target) { _ in Issue.record("The step ran") } }
        for _ in 0..<1_000 where log.waiting.isEmpty { await Task.yield() }
        #expect(log.waiting == [true])
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.waiting == [true, false])
        #expect(log.borrowing.isEmpty)
        #expect(desk.raises == 0)
        #expect(!desk.isWatching)
    }

    @Test("Puts the pointer back only when the step moved it")
    func restoresAMovedPointer() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        try await lease.borrow(desk.target) { token in try token.commit {} }
        #expect(desk.warps.isEmpty)

        try await lease.borrow(desk.target) { token in
            try token.commit { desk.demoPosts(movingPointerTo: CGPoint(x: 400, y: 300)) }
            // Typing doesn't use the pointer, so it still comes back.
            desk.personTypes()
        }
        #expect(desk.warps == [FakeDesk.restingPointer])
        #expect(desk.pointer == FakeDesk.restingPointer)
    }

    @Test("Leaves the pointer alone while the person is moving it")
    func leavesThePersonsPointer() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        try await lease.borrow(desk.target) { token in
            try token.commit { desk.demoPosts(movingPointerTo: CGPoint(x: 400, y: 300)) }
            desk.personMovesPointer(to: CGPoint(x: 250, y: 250))
        }
        #expect(desk.warps.isEmpty)
        #expect(desk.pointer == CGPoint(x: 250, y: 250))
    }

    @Test("Leaves the person in an app they switched to themselves")
    func leavesTheAppThePersonChose() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        try await lease.borrow(desk.target) { token in
            try token.commit {}
            desk.frontPID = 77
        }
        #expect(desk.restores.isEmpty)
        #expect(desk.frontPID == 77)
    }

    @Test("Doesn't bring forward or put back a window that's already in front")
    func skipsAWindowAlreadyInFront() async throws {
        let desk = FakeDesk()
        desk.frontPID = FakeDesk.demoPID
        desk.focusedWindow = FakeDesk.demoWindow
        let lease = DemoScreenLease(environment: desk)
        try await lease.borrow(desk.target) { token in try token.commit {} }
        #expect(desk.raises == 0)
        #expect(desk.restores.isEmpty)
    }

    @Test("Gives back another window of the same app")
    func restoresAnotherWindowOfTheSameApp() async throws {
        let desk = FakeDesk()
        desk.frontPID = FakeDesk.demoPID
        let lease = DemoScreenLease(environment: desk)
        try await lease.borrow(desk.target) { token in
            #expect(desk.focusedWindow == FakeDesk.demoWindow)
            try token.commit {}
        }
        #expect(desk.raises == 1)
        #expect(desk.restores == [FakeDesk.demoPID])
        #expect(desk.focusedWindow == FakeDesk.personWindow)
    }

    @Test("Input while the window comes forward retries, and a raise that lands late is still put back")
    func handlesALateRaise() async throws {
        let desk = FakeDesk()
        desk.arrivalPolls = 3
        var typed = false
        desk.onSleep = { desk in
            guard !typed, desk.raises == 1 else { return }
            typed = true
            desk.personTypes()
        }
        let lease = DemoScreenLease(environment: desk)
        var tries = 0
        try await lease.borrow(desk.target) { token in
            tries += 1
            try token.commit {}
        }
        #expect(tries == 1)
        // The interrupted try waits for its raise and undoes it; the next try puts things back too.
        #expect(desk.restores == [FakeDesk.personPID, FakeDesk.personPID])
        #expect(desk.frontPID == FakeDesk.personPID)
    }

    @Test("A raise that lands after the person came back is undone at once, while they keep typing")
    func undoesALateRaiseAtOnce() async throws {
        let desk = FakeDesk()
        desk.arrivalPolls = 3
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        var typingUntil: Duration?
        var demoInFrontWhileTyping = 0
        var demoInFrontAfterTheMoment = false
        desk.onSleep = { desk in
            if typingUntil == nil, desk.raises == 1 { typingUntil = desk.elapsed + .seconds(1) }
            guard let until = typingUntil, desk.elapsed < until else { return }
            if desk.frontPID == FakeDesk.demoPID {
                demoInFrontWhileTyping += 1
                // Keys that reach the demo app outside a borrowed moment would pause the run.
                if log.borrowing.last != true { demoInFrontAfterTheMoment = true }
            }
            desk.personTypes()
        }
        var tries = 0
        try await lease.borrow(desk.target) { token in
            tries += 1
            try token.commit {}
        }
        #expect(tries == 1)
        // The demo app was in front for one poll at most, inside the moment, before the person's app came back.
        #expect(demoInFrontWhileTyping <= 1)
        #expect(!demoInFrontAfterTheMoment)
        #expect(desk.restores.first == FakeDesk.personPID)
        #expect(log.borrowing == [true, false, true, false])
    }

    @Test("Never starts while an app takes a password, however long the person has paused")
    func waitsOutSecureInput() async throws {
        let desk = FakeDesk()
        desk.secureInput = true
        desk.onSleep = { desk in
            if desk.elapsed >= .seconds(3) { desk.secureInput = false }
        }
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        var startedAt: Duration?
        try await lease.borrow(desk.target) { token in
            startedAt = desk.elapsed
            try token.commit {}
        }
        #expect(try #require(startedAt) >= .seconds(3))
        #expect(log.waiting == [true, false])
    }

    @Test("Reports a window that never gets focus, or an app that's gone")
    func reportsAWindowThatNeverComes() async throws {
        let desk = FakeDesk()
        desk.arrivalPolls = nil
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        await #expect(throws: DemoError.inputNotDelivered("Ledger")) {
            try await lease.borrow(desk.target) { _ in Issue.record("The step ran") }
        }
        #expect(desk.elapsed >= .milliseconds(1_500))
        #expect(log.borrowing == [true, false])
        #expect(desk.restores.isEmpty)

        desk.appIsRunning = false
        await #expect(throws: DemoError.inputNotDelivered("Ledger")) {
            try await lease.borrow(desk.target) { _ in Issue.record("The step ran") }
        }
    }

    @Test("The demo's own posted input never makes the next step wait")
    func ignoresItsOwnInput() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        try await lease.borrow(desk.target) { token in
            try await desk.sleep(for: .milliseconds(30))
            try token.commit { desk.demoPosts() }
        }
        try await lease.borrow(desk.target) { token in try token.commit {} }
        #expect(log.waiting.isEmpty)

        // The person's own input a moment later does, even with nothing observing it.
        try await desk.sleep(for: .milliseconds(200))
        desk.personTypes()
        try await lease.borrow(desk.target) { token in try token.commit {} }
        #expect(log.waiting == [true, false])
    }

    @Test("Lends the screen to one step at a time")
    func lendsToOneStepAtATime() async throws {
        let desk = FakeDesk()
        let lease = DemoScreenLease(environment: desk)
        let log = LeaseLog(lease)
        func step() -> Task<Void, any Error> {
            Task {
                try await lease.borrow(desk.target) { token in
                    log.inside += 1
                    log.mostInside = max(log.mostInside, log.inside)
                    for _ in 0..<5 { await Task.yield() }
                    try token.commit {}
                    log.inside -= 1
                }
            }
        }
        let first = step()
        let second = step()
        try await first.value
        try await second.value
        #expect(log.mostInside == 1)
        #expect(desk.raises == 2)
        #expect(!desk.isWatching)
    }
}

/// What the lease told the driver, in order.
@MainActor
private final class LeaseLog {
    var waiting: [Bool] = []
    var borrowing: [Bool] = []
    var inside = 0
    var mostInside = 0

    init(_ lease: DemoScreenLease) {
        lease.onWaitingChanged = { [unowned self] in self.waiting.append($0) }
        lease.onBorrowingChanged = { [unowned self] in self.borrowing.append($0) }
    }
}

/// A Mac with a person at it: a clock that moves only when the lease sleeps, the
/// person's app in front, and a demo window that comes forward when asked.
@MainActor
private final class FakeDesk: DemoScreenLeaseEnvironment {
    static let personPID: pid_t = 10
    static let personWindow: CGWindowID = 3
    static let demoPID: pid_t = 42
    static let demoWindow: CGWindowID = 7
    static let restingPointer = CGPoint(x: 100, y: 100)

    private(set) var now = ContinuousClock.now
    private let start: ContinuousClock.Instant
    /// The system's last input, the person's or posted.
    var lastSystemInput: ContinuousClock.Instant?
    /// The person never stops typing, so the system is never idle.
    var keepsTyping = false
    /// An app is taking a password.
    var secureInput = false
    var frontPID: pid_t? = FakeDesk.personPID
    var focusedWindow: CGWindowID? = FakeDesk.personWindow
    var pointer = FakeDesk.restingPointer
    /// Sleeps before the demo window has focus after a raise; nil never.
    var arrivalPolls: Int? = 0
    var appIsRunning = true
    /// Runs after each sleep, once the clock has moved.
    var onSleep: ((FakeDesk) -> Void)?
    private(set) var raises = 0
    private(set) var restores: [pid_t] = []
    private(set) var warps: [CGPoint] = []
    private var pendingArrival: Int?
    private var watcher: (@MainActor @Sendable (DemoRealInput) -> Void)?

    init() {
        start = now
        lastSystemInput = now.advanced(by: .seconds(-10))
    }

    var elapsed: Duration { now - start }
    var isWatching: Bool { watcher != nil }

    var target: DemoLeaseTarget {
        DemoLeaseTarget(pid: Self.demoPID, windowID: Self.demoWindow, name: "Ledger") { [unowned self] in
            self.frontPID == Self.demoPID && self.focusedWindow == Self.demoWindow
        }
    }

    func personTypes() {
        lastSystemInput = now
        watcher?(.key)
    }

    func personMovesPointer(to point: CGPoint) {
        pointer = point
        lastSystemInput = now
        watcher?(.pointer)
    }

    /// Input the demo posts, which only the system's idle time counts.
    func demoPosts(movingPointerTo point: CGPoint? = nil) {
        if let point { pointer = point }
        lastSystemInput = now
    }

    // MARK: DemoScreenLeaseEnvironment

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        now = now.advanced(by: duration)
        if let polls = pendingArrival {
            if polls <= 1 { arrive() } else { pendingArrival = polls - 1 }
        }
        onSleep?(self)
        await Task.yield()
    }

    func secondsSinceLastInput() -> Double? {
        guard !keepsTyping else { return 0 }
        return lastSystemInput.map { (now - $0) / .seconds(1) }
    }

    var isSecureInputOn: Bool { secureInput }

    func watchInput(_ handler: @escaping @MainActor @Sendable (DemoRealInput) -> Void) {
        watcher = handler
    }

    func stopWatchingInput() {
        watcher = nil
    }

    var frontmostPID: pid_t? { frontPID }

    func currentFront() -> DemoLeaseFront? {
        frontPID.map { DemoLeaseFront(pid: $0, window: nil) }
    }

    func raise(_ target: DemoLeaseTarget) -> Bool {
        guard appIsRunning else { return false }
        raises += 1
        switch arrivalPolls {
        case 0: arrive()
        case let polls?: pendingArrival = polls
        case nil: break
        }
        return true
    }

    func restore(_ front: DemoLeaseFront) {
        restores.append(front.pid)
        frontPID = front.pid
        focusedWindow = Self.personWindow
    }

    var pointerLocation: CGPoint? { pointer }

    func movePointer(to point: CGPoint) {
        warps.append(point)
        pointer = point
    }

    private func arrive() {
        pendingArrival = nil
        frontPID = Self.demoPID
        focusedWindow = Self.demoWindow
    }
}
