import Foundation

/// Reverse lookup: Italian or English word → Japanese headwords, by searching
/// the definitions. Matching is done with SQLite full-text search; this file
/// holds the pure parts: what gets indexed and how hits are ranked.
public enum ReverseSearch {
    /// The pieces of a glossary worth indexing: short Latin-script segments.
    /// Long sentences (usually examples) are left out, so "ciao" finds the
    /// words that *mean* ciao, not every example that happens to contain it.
    public static func indexText(fromGlossaryJSON data: Data) -> String {
        segments(of: GlossaryText.items(fromJSON: data)).joined(separator: "\n")
    }

    static func segments(of items: [String]) -> [String] {
        var out: [String] = []
        for item in items {
            for line in item.split(separator: "\n") {
                for part in line.split(whereSeparator: { ";；,，、/／".contains($0) }) {
                    let s = part.trimmingCharacters(in: .whitespaces)
                    guard s.count <= 60, s.unicodeScalars.contains(where: isLatinLetter) else { continue }
                    out.append(s)
                }
            }
        }
        return out
    }

    /// Lowercase, no accents, no bracketed notes, no Japanese, no grammar
    /// placeholders: "(攻めること)Assalto [-chi]" → "assalto".
    public static func normalize(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        for (open, close) in [("(", ")"), ("[", "]"), ("【", "】"), ("〔", "〕"), ("{", "}")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        let kept = s.unicodeScalars.map { isLatinLetter($0) ? Character($0) : " " }
        let words = String(kept).split(separator: " ").map(String.init)
            .filter { !placeholders.contains($0) }
        return words.joined(separator: " ")
    }

    private static let placeholders: Set<String> = ["qlcu", "ql", "co", "qlco", "qc", "qd", "sb", "sth", "something", "someone", "etc"]

    static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: return s.properties.isAlphabetic
        default: return false
        }
    }

    /// How well an indexed text answers the query. 0 means "not a real match".
    public static func score(query: String, indexText: String) -> Int {
        var q = normalize(query)
        if q.hasPrefix("to ") { q.removeFirst(3) } // "to run" is asked as "run"
        guard !q.isEmpty else { return 0 }
        let qWords = Set(q.split(separator: " "))
        var best = 0
        for (position, raw) in indexText.split(separator: "\n").enumerated() {
            var s = normalize(String(raw))
            if s.hasPrefix("to ") { s.removeFirst(3) } // English infinitive: "to eat" == "eat"
            let positionPenalty = min(position, 10)
            var value = 0
            if s == q {
                value = 100
            } else {
                let words = s.split(separator: " ")
                if qWords.isSubset(of: Set(words)) {
                    // All query words present: shorter segments are closer meanings.
                    value = max(60 - (words.count - qWords.count) * 6, 20)
                }
            }
            if value > 0 { best = max(best, value - positionPenalty) }
        }
        return best
    }

    /// FTS5 query: every word must appear; the last one may be a prefix while typing.
    /// Words like "to" or "il" are left out of the match (they are in half of
    /// all definitions and make it slow) but still count when ranking.
    public static func ftsQuery(for text: String) -> String? {
        let all = normalize(text).split(separator: " ").map(String.init)
        guard !all.isEmpty else { return nil }
        let meaningful = all.filter { !stopwords.contains($0) }
        let words = meaningful.isEmpty ? all : meaningful
        let lastTyped = all.last
        return words.enumerated().map { i, w in
            let quoted = "\"" + w.replacingOccurrences(of: "\"", with: "") + "\""
            let isLast = i == words.count - 1 && w == lastTyped
            return isLast && w.count >= 3 ? quoted + "*" : quoted
        }.joined(separator: " ")
    }

    private static let stopwords: Set<String> = [
        "to", "a", "an", "the", "of", "be",
        "il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "di", "da", "del", "della", "e",
    ]

    /// Bilingual dictionaries like 和伊 tuck compounds inside the main entry:
    /// under 仕立て there is "◎仕立屋 (人)sarto". When the match is in such a
    /// sub-entry, this returns the compound (仕立屋), so the result can show
    /// the word that actually means "sarto" rather than its parent.
    public static func subentry(matching query: String, glossaryJSON: Data) -> String? {
        let lines = GlossaryText.items(fromJSON: glossaryJSON).flatMap { $0.split(separator: "\n").map(String.init) }
        guard let hit = lines.firstIndex(where: { score(query: query, indexText: segments(of: [$0]).joined(separator: "\n")) > 0 }) else {
            return nil
        }
        var j = hit - 1
        while j > 0 {
            let line = lines[j]
            if line.unicodeScalars.contains(where: isLatinLetter) { j -= 1; continue }
            return compound(from: line)
        }
        return nil // reached the entry's own header: the match belongs to the main word
    }

    /// "◎衣装係［方］" → 衣装係. nil for sentences, labels and headers.
    static func compound(from line: String) -> String? {
        var s = line.trimmingCharacters(in: .whitespaces)
        while let first = s.first, "◎◇◆○●・".contains(first) { s.removeFirst() }
        if let cut = s.firstIndex(where: { "［[（(〔【".contains($0) }) { s = String(s[..<cut]) }
        s = s.trimmingCharacters(in: .whitespaces)
        guard (1...10).contains(s.count), Kana.containsJapanese(s),
              !s.contains(where: { "、。，！？「」…".contains($0) }) else { return nil }
        return s
    }

    /// Reads a Yomitan frequency value: a number, {value}, or {reading, frequency}.
    public static func frequencyValue(_ json: Any) -> Double? {
        switch json {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.split(separator: " ").first ?? "")
        case let o as [String: Any]:
            if let f = o["frequency"] { return frequencyValue(f) }
            if let v = o["value"] { return frequencyValue(v) }
            return nil
        default: return nil
        }
    }
}
