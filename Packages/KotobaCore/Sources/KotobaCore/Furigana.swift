import Foundation

/// Aligns a reading to a written form: 食べ物 + たべもの → 食(た)べ物(もの).
public enum Furigana {
    public struct Segment: Hashable, Sendable {
        public var text: String
        /// nil when the text is already kana and needs no reading.
        public var reading: String?
    }

    public static func segments(expression: String, reading: String) -> [Segment] {
        guard !reading.isEmpty, reading != expression else { return [Segment(text: expression, reading: nil)] }
        // Split the written form into runs of kana and runs of everything else (kanji, 々...).
        var runs: [(text: String, isKana: Bool)] = []
        for c in expression {
            let kana = isKana(c)
            if let last = runs.last, last.isKana == kana {
                runs[runs.count - 1].text.append(c)
            } else {
                runs.append((String(c), kana))
            }
        }
        if runs.count == 1 && !runs[0].isKana { return [Segment(text: expression, reading: reading)] }

        // Kana runs must appear literally in the reading; kanji runs take what is between them.
        let target = Array(Kana.toHiragana(reading))
        if let result = align(runs[...], target[...]) { return result }
        return [Segment(text: expression, reading: reading)]
    }

    private static func align(_ runs: ArraySlice<(text: String, isKana: Bool)>, _ reading: ArraySlice<Character>) -> [Segment]? {
        guard let first = runs.first else { return reading.isEmpty ? [] : nil }
        let rest = runs.dropFirst()
        if first.isKana {
            let kana = Array(Kana.toHiragana(first.text))
            guard reading.starts(with: kana) else { return nil }
            guard let tail = align(rest, reading.dropFirst(kana.count)) else { return nil }
            return [Segment(text: first.text, reading: nil)] + tail
        }
        // A kanji run needs at least one kana of reading; try the shortest first.
        let maxLength = reading.count - rest.filter(\.isKana).reduce(0) { $0 + $1.text.count }
        guard maxLength >= 1 else { return nil }
        for length in 1...maxLength {
            if rest.isEmpty && length != reading.count { continue }
            if let tail = align(rest, reading.dropFirst(length)) {
                return [Segment(text: first.text, reading: String(reading.prefix(length)))] + tail
            }
        }
        return nil
    }

    static func isKana(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) && $0.value != 0x30FB }
    }

    /// Anki's plain format: " 食[た]べ 物[もの]".
    public static func ankiPlain(expression: String, reading: String) -> String {
        segments(expression: expression, reading: reading).map { s in
            s.reading.map { " \(s.text)[\($0)]" } ?? s.text
        }.joined().trimmingCharacters(in: .whitespaces)
    }

    /// HTML ruby.
    public static func html(expression: String, reading: String) -> String {
        segments(expression: expression, reading: reading).map { s in
            s.reading.map { "<ruby>\(GlossaryHTML.escape(s.text))<rt>\(GlossaryHTML.escape($0))</rt></ruby>" }
                ?? GlossaryHTML.escape(s.text)
        }.joined()
    }
}
