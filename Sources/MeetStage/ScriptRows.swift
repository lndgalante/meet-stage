import CoreGraphics

/// The current line broken into rows that fit the island's text column, and
/// which row the island keeps in view: a pure function of the words and a
/// measure, so it can be checked without drawing.
struct ScriptRows: Equatable {
    /// A word, or part of one too wide for a row, with the index it has in the line.
    struct Piece: Equatable {
        var word: Int
        var text: String
    }

    /// Pieces of the same word follow each other with no space between them;
    /// other pieces are separated by one space.
    var rows: [[Piece]]

    /// Greedy breaking: a word goes on the row if it fits after a space, else it
    /// starts the next row. A word wider than a whole row (Japanese or Chinese
    /// with no spaces) is split into pieces that fit. An empty line is one empty row.
    static func make(words: [String], width: CGFloat, space: CGFloat, measure: (String) -> CGFloat) -> ScriptRows {
        let limit = width - 2
        var rows: [[Piece]] = []
        var row: [Piece] = []
        var x: CGFloat = 0
        for (index, word) in words.enumerated() {
            for chunk in chunks(of: word, limit: limit, measure: measure) {
                let width = measure(chunk)
                let continuesWord = row.last?.word == index
                let needed = row.isEmpty || continuesWord ? width : space + width
                if !row.isEmpty, x + needed > limit {
                    rows.append(row)
                    row = []
                    x = 0
                }
                x += row.isEmpty ? width : needed
                row.append(Piece(word: index, text: chunk))
            }
        }
        if !row.isEmpty || rows.isEmpty { rows.append(row) }
        return ScriptRows(rows: rows)
    }

    /// The word whole when it fits a row, else runs of characters that each do.
    private static func chunks(of word: String, limit: CGFloat, measure: (String) -> CGFloat) -> [String] {
        guard measure(word) > limit else { return [word] }
        var chunks: [String] = []
        var chunk = ""
        for character in word {
            // A character always makes progress, even one wider than the row.
            if !chunk.isEmpty, measure(chunk + String(character)) > limit {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    /// The row holding `word`'s first piece; the last row for a word past the end.
    func row(of word: Int) -> Int {
        rows.firstIndex { $0.contains { $0.word == word } } ?? max(0, rows.count - 1)
    }

    /// The first row in view: `anchor` rows above the row being read, never past
    /// the point where the last two rows fill the viewport, and never back up
    /// from `previous`, so a recognizer revising its result can't scroll the
    /// line backwards. Nil `previous` starts over (a new line, font or width).
    /// Textream's Near Top reading position (MarqueeTextView.swift:412-459), made forward only.
    static func top(activeRow: Int, rowCount: Int, anchor: Int, previous: Int?) -> Int {
        let desired = max(0, min(activeRow - anchor, rowCount - 2))
        return previous.map { max($0, desired) } ?? desired
    }

    /// Whether the top edge fades, saying the line goes on above: only over a
    /// row already read. With no row kept above it (large text), the row being
    /// read is the top one, and the fade would dim its capitals and accents.
    static func fadesTop(top: Int, activeRow: Int) -> Bool {
        top > 0 && activeRow > top
    }
}
