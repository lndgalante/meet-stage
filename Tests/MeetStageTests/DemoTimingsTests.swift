import Foundation
import Testing

@testable import MeetStage

@Suite("Demo timings")
struct DemoTimingsTests {
    private func turn(
        model: Duration = .zero, input: Int = 0, settle: Duration = .zero, pauseWait: Duration = .zero,
        reused: Bool = false, routes: [DemoInputRoute?] = []
    ) -> DemoTurnTimings {
        var turn = DemoTurnTimings()
        turn.model = model
        turn.modelCalls = model > .zero ? 1 : 0
        turn.tokens.input = input
        turn.settle = settle
        turn.pauseWait = pauseWait
        turn.reusedLook = reused
        turn.routes = routes
        return turn
    }

    @Test("A run adds up its turns: model and settle time, waits for a pause, reused looks and each route")
    func addsUpTurns() {
        var run = DemoRunTimings()
        run.add(turn(model: .milliseconds(8_000), input: 1_200, settle: .milliseconds(400), routes: [.accessibility]))
        run.add(
            turn(
                model: .milliseconds(6_500), input: 300, settle: .milliseconds(900), pauseWait: .milliseconds(1_600),
                reused: true, routes: [.accessibility, .borrowedScreen]))
        run.add(turn(model: .milliseconds(3_000), reused: true, routes: [nil]))
        run.add(turn())

        #expect(run.turns == 4)
        #expect(run.model == .milliseconds(17_500))
        #expect(run.modelCalls == 3)
        #expect(run.tokens.input == 1_500)
        #expect(run.settle == .milliseconds(1_300))
        #expect(run.pauseWait == .milliseconds(1_600))
        #expect(run.reusedLooks == 2)
        #expect(run.routes == ["accessibility": 2, "borrowedScreen": 1, "none": 1])
        #expect(
            run.summary("build ended")
                == "build ended turns=4 model=17500ms calls=3 in=1500 out=0 cacheRead=0 cacheWrite=0 settle=1300ms "
                + "pauseWait=1600ms reused=2 routes=accessibility:2,borrowedScreen:1,none:1")
        #expect(DemoRunTimings().summary("test ended").hasSuffix("reused=0 routes=-"))
    }

    @Test("A turn's line holds only numbers and route names, in milliseconds")
    func turnLine() {
        var timings = turn(
            model: .milliseconds(1_234.4), input: 10, settle: .microseconds(2_600), routes: [.browser, nil])
        timings.tokens.thinking = 4
        timings.walk = .milliseconds(85)
        timings.walks = 1
        timings.nodes = 412
        timings.settlePolls = 3
        timings.total = .seconds(2)
        #expect(
            timings.line("build turn=3 action=click")
                == "build turn=3 action=click total=2000ms model=1234ms calls=1 in=10 out=0 think=4 cacheRead=0 "
                + "cacheWrite=0 walk=85ms walks=1 nodes=412 reused=false screenshot=0ms settle=3ms polls=3 "
                + "unsettled=0 pauseWait=0ms routes=browser,none")
        #expect(DemoTurnTimings().line("test step=1 action=press outcome=done").hasSuffix("routes=-"))
    }
}
