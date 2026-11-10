import Foundation
import KotobaCore

/// A word sent to Anki, as listed in the "Parole" tab.
struct IndexedWord: Hashable, Identifiable, Sendable {
    var expression: String
    var reading: String
    var added: Date?

    /// The same key `AppSettings.mined` uses.
    var id: String { expression + "|" + reading }

    init(expression: String, reading: String, added: Date? = nil) {
        self.expression = expression
        self.reading = reading
        self.added = added
    }

    init?(minedKey: String, added: Date? = nil) {
        let parts = minedKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        self.init(expression: String(first), reading: parts.count > 1 ? String(parts[1]) : "", added: added)
    }
}

/// Orders words the way a Japanese dictionary does: by reading, in the ten
/// rows of the kana table (あ か さ た な は ま や ら わ). The rows are what the
/// thumb index on the edge of the "Parole" list jumps between.
enum WordIndex {
    static let rows = ["あ", "か", "さ", "た", "な", "は", "ま", "や", "ら", "わ"]
    /// Where words that do not start with kana go (ABC, 123).
    static let other = "＃"

    struct Section: Identifiable, Hashable {
        var row: String
        var words: [IndexedWord]
        var id: String { row }
    }

    /// The row a reading belongs to: が is in か, ぱ in は, カ in か.
    static func row(of reading: String) -> String {
        guard let first = Kana.toHiragana(reading).unicodeScalars.first?.value else { return other }
        switch first {
        case 0x3041...0x304A, 0x3094: return "あ"
        case 0x304B...0x3054: return "か"
        case 0x3055...0x305E: return "さ"
        case 0x305F...0x3069: return "た"
        case 0x306A...0x306E: return "な"
        case 0x306F...0x307D: return "は"
        case 0x307E...0x3082: return "ま"
        case 0x3083...0x3088: return "や"
        case 0x3089...0x308D: return "ら"
        case 0x308E...0x3093: return "わ"
        default: return other
        }
    }

    /// What a word is filed under: its reading, or itself when it has none.
    private static func sortKey(_ word: IndexedWord) -> String {
        Kana.toHiragana(word.reading.isEmpty ? word.expression : word.reading)
    }

    static func words(mined: Set<String>, dates: [String: Date] = [:]) -> [IndexedWord] {
        mined.compactMap { IndexedWord(minedKey: $0, added: dates[$0]) }
    }

    /// By kana row, each row in reading order. Empty rows are left out.
    static func sections(_ words: [IndexedWord]) -> [Section] {
        var byRow: [String: [IndexedWord]] = [:]
        for word in words { byRow[row(of: sortKey(word)), default: []].append(word) }
        return (rows + [other]).compactMap { row in
            guard let list = byRow[row] else { return nil }
            return Section(row: row, words: list.sorted {
                let (a, b) = (sortKey($0), sortKey($1))
                return a != b ? a < b : $0.expression < $1.expression
            })
        }
    }

    /// Newest first; words from before dates were kept go last, in reading order.
    static func newestFirst(_ words: [IndexedWord]) -> [IndexedWord] {
        words.sorted {
            switch ($0.added, $1.added) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let (a, b) = (sortKey($0), sortKey($1))
                return a != b ? a < b : $0.expression < $1.expression
            }
        }
    }
}
