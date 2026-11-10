import Foundation

/// Converts romaji typed on a Latin keyboard into hiragana ("taberu" → たべる).
/// Accepts Hepburn and the common IME spellings (si, tu, zi...).
public enum Romaji {
    private static let table: [String: String] = {
        var t: [String: String] = [
            "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
            "sa": "さ", "shi": "し", "si": "し", "su": "す", "se": "せ", "so": "そ",
            "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "ta": "た", "chi": "ち", "ti": "ち", "tsu": "つ", "tu": "つ", "te": "て", "to": "と",
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
            "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
            "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
            "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "ya": "や", "yu": "ゆ", "yo": "よ",
            "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
            "wa": "わ", "wo": "を",
            "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "she": "しぇ",
            "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
            "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "che": "ちぇ",
            "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",
            "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "je": "じぇ",
            "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ", "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ",
            "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ",
            "thi": "てぃ", "dhi": "でぃ", "tsa": "つぁ",
            "-": "ー",
        ]
        for (c, k) in [("k", "き"), ("g", "ぎ"), ("n", "に"), ("h", "ひ"), ("b", "び"),
                       ("p", "ぴ"), ("m", "み"), ("r", "り")] {
            t[c + "ya"] = k + "ゃ"
            t[c + "yu"] = k + "ゅ"
            t[c + "yo"] = k + "ょ"
        }
        return t
    }()

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o", "y"]

    /// A long vowel written with a macron or a circumflex, and the ways it is
    /// spelled in kana: ō is おう in 東京, おお in 大阪 and オー in コーヒー.
    private static let longVowels: [Character: [String]] = [
        "ā": ["aa", "a-"], "â": ["aa", "a-"],
        "ī": ["ii", "i-"], "î": ["ii", "i-"],
        "ū": ["uu", "u-"], "û": ["uu", "u-"],
        "ē": ["ei", "ee", "e-"], "ê": ["ei", "ee", "e-"],
        "ō": ["ou", "oo", "o-"], "ô": ["ou", "oo", "o-"],
    ]

    /// Every kana spelling the input can stand for, likeliest first. One for
    /// plain romaji; several when long vowels are written with a macron
    /// ("tōkyō" → とうきょう, とうきょお, …), since the mark does not say which.
    /// Empty unless the whole input is valid romaji.
    public static func readings(_ input: String) -> [String] {
        var spellings = [""]
        for c in input.lowercased().precomposedStringWithCanonicalMapping {
            if let options = longVowels[c] {
                spellings = Array(spellings.flatMap { s in options.map { s + $0 } }.prefix(27))
            } else {
                spellings = spellings.map { $0 + String(c) }
            }
        }
        var out: [String] = []
        for spelling in spellings {
            if let kana = toHiragana(spelling), !out.contains(kana) { out.append(kana) }
        }
        return out
    }

    /// Returns nil unless the whole input is valid romaji.
    public static func toHiragana(_ input: String) -> String? {
        let chars = Array(input.lowercased().filter { !$0.isWhitespace })
        guard !chars.isEmpty else { return nil }
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // Older Hepburn writes ん as m before b, p and m: shimbun, sampo, gemmai.
            if c == "m", i + 1 < chars.count, chars[i + 1] == "b" || chars[i + 1] == "p" || chars[i + 1] == "m" {
                out += "ん"
                i += 1
                continue
            }
            // Doubled consonant → small っ (kk, tt, tch...).
            if i + 1 < chars.count, c.isLetter, !vowels.contains(c), c != "n",
               chars[i + 1] == c || (c == "t" && chars[i + 1] == "c") {
                out += "っ"
                i += 1
                continue
            }
            // ん: n at the end, before a consonant, n', or nn (konnichiwa, konnnichiwa).
            if c == "n" {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let afterNext: Character? = i + 2 < chars.count ? chars[i + 2] : nil
                if next == nil || (!vowels.contains(next!) && next != "n" && next != "'") {
                    out += "ん"; i += 1; continue
                }
                if next == "'" { out += "ん"; i += 2; continue }
                if next == "n" {
                    out += "ん"
                    // "nni" = ん + に, "nnni" = ん + ん... the second n starts the next kana if a vowel follows.
                    i += (afterNext.map { vowels.contains($0) } ?? false) ? 1 : 2
                    continue
                }
            }
            var matched = false
            for length in stride(from: 3, through: 1, by: -1) where i + length <= chars.count {
                if let kana = table[String(chars[i..<(i + length)])] {
                    out += kana
                    i += length
                    matched = true
                    break
                }
            }
            if !matched { return nil }
        }
        return out
    }
}
