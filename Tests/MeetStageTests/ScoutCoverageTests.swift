import Testing

@testable import MeetStage

@Suite("Finish coverage")
struct ScoutCoverageTests {
    private let outline = ["Search", "Open the result", "Show the page"]
    private let tail = ". Show what’s missing, or call finish again if it can’t be shown."

    private func gap(
        _ coverage: [ScoutBeatCoverage]?, shown: Set<Int> = [1, 2, 4], highlighted: Bool = true,
        prompt: String = "Search for The Matrix and open the result"
    ) -> String? {
        ScoutCoverage.gap(
            outline: outline, coverage: coverage, shown: shown, highlighted: highlighted, prompt: prompt)
    }

    @Test("Every beat needs a step the demo keeps; a beat cited only by a step left out has none")
    func beatsNeedSteps() {
        let covered = [
            ScoutBeatCoverage(beat: 1, steps: [1]), ScoutBeatCoverage(beat: 2, steps: [2, 3]),
            ScoutBeatCoverage(beat: 3, steps: [4])
        ]
        #expect(gap(covered) == nil)
        // Turn 3 was a detour or a click that showed nothing, so the demo has no step from it.
        #expect(gap(covered, shown: [1, 2]) == "beat 3 “Show the page” has no step in the demo that shows it" + tail)
        #expect(
            gap([ScoutBeatCoverage(beat: 2, steps: [2]), ScoutBeatCoverage(beat: 9, steps: [1])])
                == "beats 1 “Search” and 3 “Show the page” have no step in the demo that shows them" + tail)
        #expect(
            gap([])
                == "beats 1 “Search”, 2 “Open the result” and 3 “Show the page” have no step in the demo that "
                + "shows them" + tail)
        // A reply that didn't say leaves the beats unjudged.
        #expect(gap(nil) == nil)
        #expect(ScoutCoverage.gap(outline: [], coverage: [], shown: [], highlighted: true, prompt: "") == nil)
    }

    @Test("A request to show something needs a highlight")
    func showingNeedsAHighlight() {
        let covered = [
            ScoutBeatCoverage(beat: 1, steps: [1]), ScoutBeatCoverage(beat: 2, steps: [2]),
            ScoutBeatCoverage(beat: 3, steps: [4])
        ]
        let prompt = "Show how search works"
        #expect(gap(covered, highlighted: true, prompt: prompt) == nil)
        #expect(
            gap(covered, highlighted: false, prompt: prompt)
                == "nothing is highlighted, though the request asks to show something" + tail)
        #expect(gap(covered, highlighted: false) == nil)
        #expect(
            gap([], highlighted: false, prompt: prompt)?.hasPrefix(
                "beats 1 “Search”, 2 “Open the result” and 3 “Show the page” have no step in the demo that shows "
                    + "them, and nothing is highlighted") == true)
    }

    @Test("Requests that ask to show something, in each language demos are written in")
    func recognizesRequestsToShow() {
        let showing = [
            "Show how search works", "Highlight the monthly total", "Point out the fees",
            "Walk me through the settings", "Where do I download a subtitle?", "Muéstrame las transacciones",
            "Mostrar el saldo", "Enseña dónde se descarga", "Mostre o saldo", "Montre les réglages",
            "Zeig mir die Umsätze", "Mostra il saldo", "Toon het saldo", "残高を見せて", "显示余额", "잔액을 보여줘"
        ]
        for prompt in showing { #expect(ScoutCoverage.asksToShow(prompt), "\(prompt)") }
        let doing = [
            "Search for The Matrix and open the result", "Open Transactions and the first transaction's details",
            "Schedule a daily summary", "Busca The Matrix", "Ouvre les paramètres", "Öffne die Einstellungen",
            "Shower thoughts board", "A wonderful tourism site"
        ]
        for prompt in doing { #expect(!ScoutCoverage.asksToShow(prompt), "\(prompt)") }
    }
}
