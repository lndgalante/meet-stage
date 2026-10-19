import AppKit
import ApplicationServices
import CoreGraphics

/// Real input from the person at the Mac. Only its kind is kept, never which key or where.
enum DemoRealInput: Sendable {
    case key
    /// Moving, clicking, dragging or scrolling, any of which a moved pointer would throw off.
    case pointer
}

/// The app, and its focused window, the person was using before a borrowed moment.
struct DemoLeaseFront {
    let pid: pid_t
    /// Raised again on restore, for when the demo window belongs to the same app. Nil when unknown.
    let window: AXUIElement?
}

/// The window a borrowed moment brings forward.
struct DemoLeaseTarget {
    let pid: pid_t
    let windowID: CGWindowID
    let name: String
    /// Whether that exact window, not just another window of its app, has focus.
    let isExactlyFocused: @MainActor () -> Bool
}

extension DemoLeaseTarget {
    @MainActor
    init(_ window: WindowSource, name: String) {
        self.init(pid: window.processIdentifier, windowID: window.id, name: name) {
            SourceWindowFocusValidator.isExactlyFocused(window)
        }
    }
}

/// Everything the lease asks of macOS, so tests can stand in a clock, a person and the window server.
@MainActor
protocol DemoScreenLeaseEnvironment: AnyObject {
    var now: ContinuousClock.Instant { get }
    func sleep(for duration: Duration) async throws
    /// Seconds since any input reached the system, the person's or posted. Nil when unknown.
    func secondsSinceLastInput() -> Double?
    /// An app is taking a password, so keys go only to it and monitors can't see them.
    var isSecureInputOn: Bool { get }
    /// Reports the person's input until `stopWatchingInput()`; the demo's own posted events never arrive.
    func watchInput(_ handler: @escaping @MainActor @Sendable (DemoRealInput) -> Void)
    func stopWatchingInput()
    var frontmostPID: pid_t? { get }
    func currentFront() -> DemoLeaseFront?
    /// Asks for the target's app and window to come to the front. False when the app is gone.
    func raise(_ target: DemoLeaseTarget) -> Bool
    func restore(_ front: DemoLeaseFront)
    var pointerLocation: CGPoint? { get }
    func movePointer(to point: CGPoint)
}

/// Lends the screen to a demo step that only works with its app in front, without
/// taking the Mac away from the person using it. A borrow waits until they've left
/// the keyboard and pointer alone for a moment, brings the demo window forward for
/// the step, then puts their app, window and pointer back. If they come back before
/// the step commits, it puts things back and runs the step again at the next pause,
/// so a step must be repeatable until it commits. Building and testing use it;
/// presenting keeps the app in front instead.
@MainActor
final class DemoScreenLease {
    struct Limits {
        /// How long the person must leave the keyboard and pointer alone.
        var pause: Duration = .milliseconds(1_500)
        var poll: Duration = .milliseconds(100)
        /// How long the demo window may take to have focus.
        var focusTimeout: Duration = .milliseconds(1_500)
        var focusPoll: Duration = .milliseconds(50)
        /// Lets the app take in the step's input before its window loses the front.
        var settle: Duration = .milliseconds(120)
        /// How long the person's app may take to be in front again.
        var restoreTimeout: Duration = .milliseconds(600)
        /// Tries per step, counting the first.
        var tries = 8
    }

    /// True while a step waits for the person to pause; never called when it can go at once.
    var onWaitingChanged: ((Bool) -> Void)?
    /// True while the demo window is borrowed, so its overlay can hide; false once things are back.
    var onBorrowingChanged: ((Bool) -> Void)?
    /// How long steps have waited for the person to pause, in all.
    private(set) var waited: Duration = .zero

    private let environment: any DemoScreenLeaseEnvironment
    private let limits: Limits
    /// Borrows waiting or running. Input is watched only while there are any.
    private var borrowers = 0
    private var isLent = false
    private var queue: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    /// When the monitor last saw the person's input, and their pointer input.
    private var lastSeen: ContinuousClock.Instant?
    private var lastSeenPointer: ContinuousClock.Instant?
    /// Recent borrowed moments. The system's idle time counts posted events too, so
    /// activity inside one is taken to be the demo's; the monitor still sees the person's.
    private var moments: [ClosedRange<ContinuousClock.Instant>] = []
    /// The person's app when an interrupted try raised the demo window but put
    /// nothing back, since that raise can still land after the try gave up.
    private var owedFront: DemoLeaseFront?

    init(environment: any DemoScreenLeaseEnvironment = SystemScreenLeaseEnvironment(), limits: Limits = Limits()) {
        self.environment = environment
        self.limits = limits
    }

    /// Runs `body` with the target's window in front once the person pauses, then puts
    /// their app, window and pointer back. `body` must route its commit through the token.
    /// Throws `DemoError.noPause` when the person keeps interrupting, and
    /// `DemoError.inputNotDelivered` when the window never gets focus.
    func borrow(_ target: DemoLeaseTarget, _ body: @MainActor (DemoLeaseToken) async throws -> Void) async throws {
        addBorrower()
        defer { removeBorrower() }
        try await waitTurn()
        defer { passTurn() }
        owedFront = nil
        defer { owedFront = nil }
        var interruptedAt: ContinuousClock.Instant?
        for number in 1...max(1, limits.tries) {
            try await waitForPause(after: interruptedAt)
            let token = DemoLeaseToken(lease: self, pid: target.pid, start: environment.now)
            do {
                try await lend(target, to: token, body)
                return
            } catch let error where shouldRetry(after: error, of: token) {
                AppLog.demoMode.info("Demo step interrupted by the presenter on try \(number); retrying at a pause")
                interruptedAt = environment.now
            }
        }
        throw DemoError.noPause(target.name)
    }

    // MARK: Waiting

    /// Returns once the person has left the keyboard and pointer alone for a pause,
    /// counted from the last interruption too. A pause partway through a password
    /// doesn't count: the rest of it would go to the demo window.
    private func waitForPause(after interruption: ContinuousClock.Instant?) async throws {
        var waitingSince: ContinuousClock.Instant?
        defer {
            if let waitingSince {
                waited += environment.now - waitingSince
                onWaitingChanged?(false)
            }
        }
        while true {
            try Task.checkCancellation()
            let busy = [lastInput(), interruption].compactMap { $0 }.max()
            let paused = busy.map { environment.now - $0 >= limits.pause } ?? true
            guard !paused || environment.isSecureInputOn else { return }
            if waitingSince == nil {
                waitingSince = environment.now
                onWaitingChanged?(true)
            }
            try await environment.sleep(for: limits.poll)
        }
    }

    /// The person's last input: what the monitor saw, or the system's idle time when
    /// that falls outside every borrowed moment. The idle time also covers input from
    /// before the monitor started, and keys that secure input hides from monitors.
    private func lastInput() -> ContinuousClock.Instant? {
        guard let seconds = environment.secondsSinceLastInput(), seconds.isFinite, seconds >= 0 else {
            return lastSeen
        }
        let system = environment.now - .seconds(seconds)
        guard !moments.contains(where: { $0.contains(system) }) else { return lastSeen }
        return max(system, lastSeen ?? system)
    }

    // MARK: Borrowing

    /// Brings the target forward, runs one try of the step, and always puts things back.
    private func lend(
        _ target: DemoLeaseTarget, to token: DemoLeaseToken, _ body: @MainActor (DemoLeaseToken) async throws -> Void
    ) async throws {
        let isFocused = target.isExactlyFocused()
        let current = environment.currentFront()
        let front: DemoLeaseFront?
        if current?.pid == target.pid {
            // The demo's app is already in front. If that's a late raise from an interrupted
            // try, the person's app is still owed the front; otherwise they're using this app,
            // and only another of its windows needs putting back.
            front = owedFront ?? (isFocused ? nil : current)
        } else {
            front = current
        }
        let pointer = environment.pointerLocation
        onBorrowingChanged?(true)
        var failure: (any Error)?
        var arrived = isFocused
        do {
            if !isFocused {
                try await bringForward(target, token: token)
                arrived = true
            }
            try await body(token)
        } catch {
            failure = error
        }
        if failure == nil || token.isCommitted { try? await environment.sleep(for: limits.settle) }
        await putBack(
            front, pointer: pointer, target: target, raised: !isFocused,
            raiseInFlight: !arrived && failure is DemoLeaseInterruption, since: token.start)
        onBorrowingChanged?(false)
        if let failure { throw failure }
    }

    /// Raises the demo window and waits until it has focus.
    private func bringForward(_ target: DemoLeaseTarget, token: DemoLeaseToken) async throws {
        guard environment.raise(target) else { throw DemoError.inputNotDelivered(target.name) }
        let deadline = environment.now.advanced(by: limits.focusTimeout)
        while !target.isExactlyFocused() {
            // Input while the window comes forward means the pause is over.
            if saw(lastSeen, since: token.start) { throw DemoLeaseInterruption() }
            guard environment.now < deadline else { throw DemoError.inputNotDelivered(target.name) }
            try await environment.sleep(for: limits.focusPoll)
        }
    }

    /// Puts the pointer back unless the person is moving it, then gives the front back
    /// to their app unless they already went somewhere else. `raiseInFlight` says the
    /// person came back while the window was still coming forward.
    private func putBack(
        _ front: DemoLeaseFront?, pointer: CGPoint?, target: DemoLeaseTarget, raised: Bool, raiseInFlight: Bool,
        since start: ContinuousClock.Instant
    ) async {
        if let pointer, !saw(lastSeenPointer, since: start), let current = environment.pointerLocation,
            hypot(current.x - pointer.x, current.y - pointer.y) > 0.5
        {
            environment.movePointer(to: pointer)
        }
        if let front, raiseInFlight, front.pid != target.pid {
            // The raise can still land after the try gave up; wait for it, so it's undone
            // before the person's next keys reach the demo window.
            let deadline = environment.now.advanced(by: limits.focusTimeout)
            while environment.frontmostPID == front.pid, environment.now < deadline {
                do { try await environment.sleep(for: limits.focusPoll) } catch { break }
            }
        }
        if let front, environment.frontmostPID == target.pid {
            owedFront = nil
            environment.restore(front)
            // Wait for it to land, so a borrow right after finds the person's app in front, not the demo's.
            let deadline = environment.now.advanced(by: limits.restoreTimeout)
            while environment.frontmostPID != front.pid, environment.now < deadline {
                do { try await environment.sleep(for: limits.focusPoll) } catch { break }
            }
        } else {
            // The raise never landed, or the person went to another app: if it lands
            // after all, the next try gives their app the front back.
            owedFront = raised ? front : nil
        }
        remember(start...environment.now)
    }

    private func remember(_ moment: ClosedRange<ContinuousClock.Instant>) {
        moments.removeAll { $0.upperBound < moment.upperBound - limits.pause }
        moments.append(moment)
    }

    /// Whether a failed try runs again: the person came back before the step committed.
    /// Nothing is retried once committed.
    private func shouldRetry(after error: any Error, of token: DemoLeaseToken) -> Bool {
        guard !token.isCommitted, !(error is CancellationError) else { return false }
        if error is DemoLeaseInterruption { return true }
        guard let error = error as? DemoError else { return false }
        // Their own input may be what threw the step off, like a click that moved focus.
        return error == .focusChanged || (saw(lastSeen, since: token.start) && error.mayComeFromInterruption)
    }

    /// The person came back since `start`, or an app other than `pid` took the front.
    fileprivate func isInterrupted(since start: ContinuousClock.Instant, pid: pid_t) -> Bool {
        saw(lastSeen, since: start) || environment.frontmostPID != pid
    }

    private func saw(_ input: ContinuousClock.Instant?, since start: ContinuousClock.Instant) -> Bool {
        input.map { $0 >= start } ?? false
    }

    // MARK: Watching

    private func addBorrower() {
        borrowers += 1
        guard borrowers == 1 else { return }
        environment.watchInput { [weak self] input in self?.record(input) }
    }

    private func removeBorrower() {
        borrowers -= 1
        guard borrowers == 0 else { return }
        environment.stopWatchingInput()
    }

    private func record(_ input: DemoRealInput) {
        let now = environment.now
        lastSeen = now
        if input == .pointer { lastSeenPointer = now }
    }

    // MARK: One at a time

    /// Waits behind a borrow that's already waiting or running.
    private func waitTurn() async throws {
        try Task.checkCancellation()
        guard isLent else {
            isLent = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { queue.append((id, $0)) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.leaveQueue(id) }
        }
    }

    /// Hands the screen to the next borrow in line, if any.
    private func passTurn() {
        guard !queue.isEmpty else {
            isLent = false
            return
        }
        queue.removeFirst().continuation.resume()
    }

    private func leaveQueue(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// One borrowed moment, handed to the step running in it.
@MainActor
final class DemoLeaseToken {
    private let lease: DemoScreenLease
    private let pid: pid_t
    fileprivate let start: ContinuousClock.Instant
    /// The step passed its irreversible point, so it won't be retried.
    private(set) var isCommitted = false

    fileprivate init(lease: DemoScreenLease, pid: pid_t, start: ContinuousClock.Instant) {
        self.lease = lease
        self.pid = pid
        self.start = start
    }

    /// Throws when the person came back or another app took the front, so the lease
    /// puts things back and retries. Does nothing once the step has committed.
    func check() throws {
        guard !isCommitted, lease.isInterrupted(since: start, pid: pid) else { return }
        throw DemoLeaseInterruption()
    }

    /// Runs the step's own commit unless the person came back first, then marks the step committed.
    func commit(_ commit: @MainActor () throws -> Void) throws {
        try check()
        try commit()
        isCommitted = true
    }
}

/// The person came back before the step committed. Never leaves the lease.
private struct DemoLeaseInterruption: Error {}

extension DemoError {
    /// Errors that mean the step's input never landed, which the person's own input can cause.
    fileprivate var mayComeFromInterruption: Bool {
        if case .typingFailed = self { return true }
        return wasNotDelivered
    }
}

/// The real Mac, through public APIs only: AppKit's event monitors, the window
/// server's idle time, Carbon's secure input state, activation and Accessibility's
/// frontmost and raise.
@MainActor
final class SystemScreenLeaseEnvironment: DemoScreenLeaseEnvironment {
    /// Quartz's `kCGAnyInputEventType`, a macro Swift doesn't import.
    private static let anyInputEventType = CGEventType(rawValue: ~0)
    private var monitors: [GlobalLocalEventMonitor<DemoRealInput>] = []

    var now: ContinuousClock.Instant { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    func secondsSinceLastInput() -> Double? {
        Self.anyInputEventType.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
    }

    var isSecureInputOn: Bool { DemoAwayMonitor.isSecureInputOn() }

    func watchInput(_ handler: @escaping @MainActor @Sendable (DemoRealInput) -> Void) {
        stopWatchingInput()
        let keys = GlobalLocalEventMonitor<DemoRealInput>(
            eventMask: [.keyDown, .flagsChanged],
            transform: { DemoInputSynthesizer.isSynthetic($0.cgEvent) ? nil : .key },
            handler: handler)
        let pointer = GlobalLocalEventMonitor<DemoRealInput>(
            eventMask: [
                .mouseMoved, .scrollWheel, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
                .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged
            ],
            // A burst of movement arrives as one delivery, without waiting.
            coalescingInterval: .zero,
            transform: { DemoInputSynthesizer.isSynthetic($0.cgEvent) ? nil : .pointer },
            handler: handler)
        monitors = [keys, pointer]
        for monitor in monitors { monitor.start() }
    }

    func stopWatchingInput() {
        for monitor in monitors { monitor.stop() }
        monitors = []
    }

    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func currentFront() -> DemoLeaseFront? {
        guard let pid = frontmostPID else { return nil }
        guard pid != NSRunningApplication.current.processIdentifier else {
            return DemoLeaseFront(pid: pid, window: nil)
        }
        let window = AccessibilityWindowResolver.focusedWindow(in: WindowRaiser.element(pid))
        return DemoLeaseFront(pid: pid, window: window)
    }

    func raise(_ target: DemoLeaseTarget) -> Bool {
        WindowRaiser.raise(windowID: target.windowID, pid: target.pid)
    }

    func restore(_ front: DemoLeaseFront) {
        guard front.pid != NSRunningApplication.current.processIdentifier else {
            NSApp.activate()
            return
        }
        guard NSRunningApplication(processIdentifier: front.pid)?.isTerminated == false else { return }
        WindowRaiser.activate(WindowRaiser.element(front.pid), raising: front.window)
    }

    var pointerLocation: CGPoint? { CGEvent(source: nil)?.location }

    func movePointer(to point: CGPoint) {
        // Warping posts no event, so neither the apps nor the input monitor see a move.
        CGWarpMouseCursorPosition(point)
        // Warping briefly detaches the pointer from the mouse; reattach it so the person's next move isn't lost.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
