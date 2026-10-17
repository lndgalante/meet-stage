import CoreGraphics
import Testing

@testable import MeetStage

@Suite("Script rows")
struct ScriptRowsTests {
    /// Every character is 10 points wide, and so is a space.
    private func rows(_ words: [String], width: CGFloat) -> ScriptRows {
        ScriptRows.make(words: words, width: width, space: 10) { CGFloat($0.count * 10) }
    }

    private func texts(_ rows: ScriptRows) -> [[String]] { rows.rows.map { $0.map(\.text) } }

    @Test("A word that fits after a space stays on the row; one that doesn't starts the next")
    func breaksAtTheLimit() {
        #expect(texts(rows(["aaa", "bb", "cccc", "d"], width: 82)) == [["aaa", "bb"], ["cccc", "d"]])
        // 40 + 10 + 30 is exactly the 80 points a row holds, two short of the width.
        #expect(texts(rows(["aaaa", "bbb"], width: 82)) == [["aaaa", "bbb"]])
        #expect(texts(rows(["aaaa", "bbb"], width: 81)) == [["aaaa"], ["bbb"]])
    }

    @Test("A word wider than a row splits into pieces that keep its index")
    func splitsOverlongWords() {
        let rows = rows(["ab", "あいうえおかきくけこ", "d"], width: 52)
        #expect(texts(rows) == [["ab"], ["あいうえお"], ["かきくけこ"], ["d"]])
        #expect(rows.rows.map { $0.map(\.word) } == [[0], [1], [1], [2]])
        #expect(rows.row(of: 1) == 1)
        #expect(rows.row(of: 2) == 3)
        // The last piece of a split word takes later words after a space.
        let shorter = self.rows(["aaaaaaa", "c"], width: 52)
        #expect(texts(shorter) == [["aaaaa"], ["aa", "c"]])
    }

    @Test("An empty line is one empty row")
    func emptyLine() {
        let rows = rows([], width: 200)
        #expect(rows.rows == [[]])
        #expect(rows.row(of: 0) == 0)
    }

    @Test("A word past the end belongs to the last row")
    func rowOfWord() {
        let rows = rows(["aaa", "bb", "cccc", "d"], width: 82)
        #expect(rows.row(of: 0) == 0)
        #expect(rows.row(of: 2) == 1)
        #expect(rows.row(of: 9) == 1)
    }

    @Test("The reading position keeps a row above, only moves forward, and starts over when reset")
    func topIsForwardOnly() {
        #expect(ScriptRows.top(activeRow: 0, rowCount: 6, anchor: 1, previous: nil) == 0)
        #expect(ScriptRows.top(activeRow: 3, rowCount: 6, anchor: 1, previous: nil) == 2)
        // A recognizer revising its result never scrolls the line back up.
        #expect(ScriptRows.top(activeRow: 1, rowCount: 6, anchor: 1, previous: 2) == 2)
        #expect(ScriptRows.top(activeRow: 4, rowCount: 6, anchor: 1, previous: 2) == 3)
        // The last two rows stay together at the bottom.
        #expect(ScriptRows.top(activeRow: 5, rowCount: 6, anchor: 1, previous: 3) == 4)
        #expect(ScriptRows.top(activeRow: 5, rowCount: 6, anchor: 0, previous: nil) == 4)
        #expect(ScriptRows.top(activeRow: 0, rowCount: 1, anchor: 1, previous: nil) == 0)
        // A new line, font or width starts from scratch.
        #expect(ScriptRows.top(activeRow: 2, rowCount: 6, anchor: 1, previous: nil) == 1)
    }

    @Test("The top edge fades over a row already read, never over the row being read")
    func topFade() {
        #expect(!ScriptRows.fadesTop(top: 0, activeRow: 1))
        #expect(ScriptRows.fadesTop(top: 1, activeRow: 2))
        // Large text keeps no row above, so the row being read is the top one.
        let top = ScriptRows.top(activeRow: 2, rowCount: 6, anchor: 0, previous: nil)
        #expect(top == 2)
        #expect(!ScriptRows.fadesTop(top: top, activeRow: 2))
        // At the end of the line, the last two rows show and the one above the last fades.
        #expect(ScriptRows.fadesTop(top: 4, activeRow: 5))
    }
}
