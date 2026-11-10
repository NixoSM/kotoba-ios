import Foundation

/// Grammatical classes a word form can belong to while it is being taken apart.
///
/// The first five are parts of speech that dictionaries tag entries with.
/// The rest are "in-between" forms (te-form, ta-form, masu-form) and `surface`,
/// which marks endings that can only appear at the very end of the text the
/// user looked up (ば, よう, imperative...).
public struct WordClass: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let v1      = WordClass(rawValue: 1 << 0) // ichidan verb (食べる)
    public static let v5      = WordClass(rawValue: 1 << 1) // godan verb (書く)
    public static let vk      = WordClass(rawValue: 1 << 2) // 来る
    public static let vs      = WordClass(rawValue: 1 << 3) // する and する-compounds
    public static let adjI    = WordClass(rawValue: 1 << 4) // i-adjective (高い), also ない/たい
    public static let te      = WordClass(rawValue: 1 << 5)
    public static let ta      = WordClass(rawValue: 1 << 6)
    public static let masu    = WordClass(rawValue: 1 << 7)
    public static let surface = WordClass(rawValue: 1 << 8)
    /// The form ます attaches to (連用形): 書き, 食べ. Endings such as ながら,
    /// やすい and 方 lead back to it, and it leads back to the verb.
    public static let stem    = WordClass(rawValue: 1 << 9)

    /// Classes that can match a dictionary entry's part of speech.
    public static let partsOfSpeech: WordClass = [.v1, .v5, .vk, .vs, .adjI]

    /// Maps the space-separated `rules` field of a Yomitan term entry.
    public init(yomitanRules: String) {
        var c: WordClass = []
        for tag in yomitanRules.split(separator: " ") {
            switch tag {
            case "v1", "v1-s": c.insert(.v1)
            case "v5": c.insert(.v5)
            case "vk": c.insert(.vk)
            case "vs", "vz": c.insert(.vs)
            case "adj-i": c.insert(.adjI)
            default:
                // Yomitan also uses detailed godan tags like v5k, v5r...
                if tag.hasPrefix("v5") { c.insert(.v5) }
            }
        }
        self = c
    }
}

/// One step of taking an inflected word back towards its dictionary form.
public struct InflectionRule: Hashable, Sendable {
    public let inflected: String
    public let base: String
    /// The class the inflected form belongs to. The rule only applies if the
    /// word currently has one of these classes (or no class yet).
    public let from: WordClass
    /// The class of the form we get back.
    public let to: WordClass
    public let reason: Reason
    /// For text exactly as typed: when what is left before the ending is kana
    /// only, it must be at least this long. Keeps one-kana accidents out
    /// (ねん is 年, not "does not sleep"), while 寝ん and 食べん still work.
    public let minKanaStem: Int

    public init(_ inflected: String, _ base: String, from: WordClass, to: WordClass, _ reason: Reason, minKanaStem: Int = 0) {
        self.inflected = inflected
        self.base = base
        self.from = from
        self.to = to
        self.reason = reason
        self.minKanaStem = minKanaStem
    }
}

/// Why a step was taken. Raw values are stable keys used for display/localisation.
public enum Reason: String, Hashable, Sendable, CaseIterable {
    case negative, past, te, polite, politePast, politeNegative, politeNegativePast, politeVolitional
    case conditional, tara, tari, potential, passive, causative, volitional, imperative
    case want, stem, progressive, completion, preparation, adverb, noun, seemingness, excess
    case negativeTe, nakereba, zu
    case whileDoing, easyTo, hardTo, wayOf, politeImperative, showsWant, nu, negativeVolitional, neba
}

/// A candidate dictionary form, with the chain of steps that produced it.
public struct Deinflection: Hashable, Sendable {
    public let term: String
    /// Empty means "unknown": the text exactly as typed, which may be any word.
    public let wordClass: WordClass
    /// Innermost step first, the way people read it: 食べなかった → [.negative, .past].
    public let reasons: [Reason]

    /// Whether a dictionary entry tagged with `rules` can be this candidate.
    public func matches(entryRules: WordClass) -> Bool {
        if wordClass.isEmpty { return true }
        return !wordClass.intersection(.partsOfSpeech).isDisjoint(with: entryRules)
    }
}

/// Breadth-first search over inflection rules.
public struct Deinflector: Sendable {
    public let rules: [InflectionRule]
    private let bySuffixLength: [Int: [String: [InflectionRule]]]
    private let maxSuffixLength: Int

    public init(rules: [InflectionRule] = JapaneseInflections.all) {
        self.rules = rules
        var index: [Int: [String: [InflectionRule]]] = [:]
        for r in rules {
            index[r.inflected.count, default: [:]][r.inflected, default: []].append(r)
        }
        self.bySuffixLength = index
        self.maxSuffixLength = rules.map(\.inflected.count).max() ?? 0
    }

    public func deinflect(_ text: String) -> [Deinflection] {
        var results = [Deinflection(term: text, wordClass: [], reasons: [])]
        var seen: Set<String> = []
        var i = 0
        while i < results.count {
            let current = results[i]
            i += 1
            let chars = Array(current.term)
            let isRaw = current.wordClass.isEmpty
            // Down to length 0: the stem of an ichidan verb is the verb without る,
            // so the "ending" taken off is empty (食べ → 食べる).
            for length in stride(from: min(maxSuffixLength, chars.count), through: 0, by: -1) {
                let suffix = String(chars[(chars.count - length)...])
                guard let candidates = bySuffixLength[length]?[suffix] else { continue }
                let stemChars = chars[..<(chars.count - length)]
                if length == 0, !Self.canEndIchidanStem(chars.last) { continue }
                let stem = String(stemChars)
                for rule in candidates {
                    guard isRaw || !current.wordClass.isDisjoint(with: rule.from) else { continue }
                    if isRaw, stemChars.count < rule.minKanaStem, stemChars.allSatisfy(Self.isHiragana) { continue }
                    let term = stem + rule.base
                    guard !term.isEmpty, term != current.term || rule.to != current.wordClass else { continue }
                    let key = "\(term)|\(rule.to.rawValue)"
                    guard seen.insert(key).inserted else { continue }
                    // "Stem" is worth saying only when it is the whole story:
                    // 書き is "stem of 書く", 書きながら is just "while".
                    let reasons = rule.reason == .stem && !current.reasons.isEmpty ? current.reasons : [rule.reason] + current.reasons
                    results.append(Deinflection(term: term, wordClass: rule.to, reasons: reasons))
                }
            }
        }
        return results
    }

    private static func isHiragana(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || $0.value == 0x30FC }
    }

    /// Ichidan stems end in an い-row or え-row kana (起き, 食べ) or, for the
    /// one-kanji verbs, in the kanji itself (見, 寝, 出).
    private static let ichidanStemEndings = Set("いきぎしじちぢにひびぴみりえけげせぜてでねへべぺめれ")

    private static func canEndIchidanStem(_ last: Character?) -> Bool {
        guard let last else { return false }
        if ichidanStemEndings.contains(last) { return true }
        return last.unicodeScalars.allSatisfy {
            switch $0.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3005: return true
            default: return false
            }
        }
    }
}
