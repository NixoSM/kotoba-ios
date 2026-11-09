import Foundation

/// Picks the word under an aim point (a fingertip, or the lens's dot) in a
/// line of recognized text.
///
/// Yomitan looks up from the character under the mouse. A camera can't aim
/// that precisely: a tremor moves the dot onto the particle before the word,
/// and a finger covers two characters. So every start a few characters around
/// the aim point is tried, and the one whose dictionary word best contains the
/// point wins. Content words (kanji, katakana, long words) beat lone particles
/// near a boundary, and the word already on screen gets a bonus, so it doesn't
/// flicker away on a small tremor.
public enum WordAim {
    public struct Pick: Hashable, Sendable {
        /// The whole line (a column, for vertical text).
        public var text: [Character]
        public var start: Int
        /// Characters the longest dictionary word from `start` covers (at least 1).
        public var length: Int

        public init(text: [Character], start: Int, length: Int) {
            self.text = text
            self.start = min(max(0, start), max(0, text.count - 1))
            self.length = max(1, min(length, text.count - self.start))
        }

        public var word: String { String(text[start..<(start + length)]) }
        /// What to look up: from the start on, like Yomitan (the scanner finds the longest word).
        public var query: String { String(text[start...].prefix(24)) }
        /// The sentence the word is in, for Anki.
        public var sentence: String { WordAim.sentence(in: text, around: start) }
    }

    /// - Parameters:
    ///   - position: the aim point in characters along the line: 3.5 is the middle of the fourth character.
    ///   - favoring: the word on screen now.
    ///   - matchLength: how many characters the longest dictionary word starting there covers (0: none).
    public static func pick(in text: [Character], at position: Double, favoring: String? = nil,
                            matchLength: (ArraySlice<Character>) -> Int) -> Pick? {
        guard !text.isEmpty else { return nil }
        let p = min(max(position, 0), Double(text.count) - 0.001)
        let hit = Int(p)
        var best: (score: Double, pick: Pick)?
        for s in max(0, hit - 5)...min(text.count - 1, hit + 1) where canStartWord(text[s]) {
            let matched = min(matchLength(text[s...]), text.count - s)
            let span = max(1, matched)
            let end = Double(s + span)
            // How far the aim point is outside this word, in characters.
            let outside = p < Double(s) ? Double(s) - p : max(0, p - end)
            guard outside <= 1 else { continue }
            var score = -3 * outside + 0.15 * Double(min(span, 3))
            // Yomitan-like: of two words that both contain the point, the one starting nearer wins.
            if Double(s) <= p { score -= 0.05 * (p - Double(s)) }
            if matched == 0 { score -= 0.6 }
            if span == 1, isHiragana(text[s]) { score -= 0.35 }
            let pick = Pick(text: text, start: s, length: span)
            if let favoring, pick.word == favoring { score += 0.5 }
            if best == nil || score > best!.score { best = (score, pick) }
        }
        return best?.pick
    }

    /// The sentence around `index`: from the previous 。！？ to the next one (with its closing bracket).
    public static func sentence(in text: [Character], around index: Int) -> String {
        guard !text.isEmpty else { return "" }
        let i = min(max(index, 0), text.count - 1)
        let enders: Set<Character> = ["。", "！", "？", "!", "?", "．"]
        let closers: Set<Character> = ["」", "』", "）", ")", "】", "〉", "》"]
        var a = i
        while a > 0, !enders.contains(text[a - 1]) { a -= 1 }
        while a < i, closers.contains(text[a]) { a += 1 }
        var b = i
        while b < text.count, !enders.contains(text[b]) { b += 1 }
        if b < text.count { b += 1 }
        while b < text.count, closers.contains(text[b]) { b += 1 }
        return String(text[a..<b]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isHiragana(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3041...0x3096).contains(v)
    }

    /// Punctuation, small kana and the long vowel mark never begin a word.
    static func canStartWord(_ c: Character) -> Bool {
        if c.isWhitespace || c.isPunctuation || c.isSymbol { return false }
        return !"ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶーｰ・、。「」『』（）〔〕【】〈〉《》…‥―—〜～".contains(c)
    }
}

/// Keeps the lens's word steady: a new word shows only once several camera
/// frames agree on it, and stays until another one clearly wins.
public struct PickStabilizer: Sendable {
    public private(set) var shown: WordAim.Pick?
    private var recent: [(word: String?, pick: WordAim.Pick?, time: Double)] = []
    /// Seconds a frame's vote counts.
    public var memory = 1.6

    public init() {}

    public mutating func reset() {
        shown = nil
        recent = []
    }

    /// Feeds what one frame read under the dot (nil: nothing).
    /// Returns the pick to show when the word on screen changes.
    public mutating func feed(_ pick: WordAim.Pick?, at time: Double) -> WordAim.Pick? {
        recent.append((pick?.word, pick, time))
        recent.removeAll { time - $0.time > memory }
        if recent.count > 5 { recent.removeFirst(recent.count - 5) }
        // Only switch to what the camera sees right now.
        guard let latest = recent.last, let word = latest.word, word != shown?.word else { return nil }
        let votes = recent.filter { $0.word == word }.count
        let current = shown.map { s in recent.filter { $0.word == s.word }.count } ?? 0
        // Nothing to defend: two frames are enough. Otherwise three, and more than the word on screen.
        let needed = current == 0 ? 2 : 3
        guard votes >= needed, votes > current else { return nil }
        shown = latest.pick
        return shown
    }
}
