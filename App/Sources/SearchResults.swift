import Foundation
import KotobaCore

/// What a search returns, split by how each headword was found.
struct SearchResults {
    var direct: [HeadwordGroup] = []
    /// Set when Latin input was also valid romaji (taberu → たべる).
    var romajiReading: String?
    var byMeaning: [HeadwordGroup] = []
    /// The text the words were found in, used as the Anki sentence.
    var sentence = ""
    /// What this search was run for. The search box changes before the
    /// results do, so headings take the text from here, not from the box.
    var searchedText = ""
    /// Latin input is usually a meaning ("run"), so the romaji reading
    /// (るん) only goes first when it is a common word.
    var romajiFirst = true
    /// How long the search took, shown at the bottom of the results.
    var milliseconds: Int?
    /// Words that start with what was typed (しんぶ → 新聞, 新聞紙…). Only the
    /// search box asks for them.
    var startingWith: [WordSuggestion] = []
    /// What they start with, for the heading.
    var startingWithText = ""
    /// The words found do not cover everything that was typed, so the list
    /// of words that start with it is the likelier answer and goes first.
    var suggestionsFirst = false
    /// What the kanji dictionaries say about the characters of the first word
    /// (or of what was typed, when no word was found).
    var kanji: [KanjiEntry] = []
    /// The word those characters come from, for the heading.
    var kanjiSource = ""

    var isEmpty: Bool { direct.isEmpty && byMeaning.isEmpty && startingWith.isEmpty && kanji.isEmpty }

    func group(section: String, index: Int) -> HeadwordGroup? {
        let list = section == "meaning" ? byMeaning : direct
        return list.indices.contains(index) ? list[index] : nil
    }
}

/// One line of the "words that start with…" list: tap it to search the word.
struct WordSuggestion: Hashable, Sendable {
    var expression: String
    var reading: String
    /// Its first definition, as plain text.
    var gloss: String
}

/// The search itself, away from the screens so it can be tested anywhere.
enum SearchEngine {
    struct Request: Sendable {
        var text: String
        var sortDictionary: String?
        /// Dictionary order, so definitions under a word follow it.
        var priority: [String: Int] = [:]
        /// Also list words that start with the text (the search box does).
        var suggest = false
    }

    static let maxSuggestions = 24

    static func run(_ request: Request, store: DictionaryStore, scanner: TextScanner) -> SearchResults {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return SearchResults() }
        let started = Date()
        var outcome = SearchResults(sentence: text, searchedText: text)
        var typedKana: [String] = []

        func ranked(_ inputs: [(entry: TermEntry, matchedText: String, reasons: [Reason])]) -> [HeadwordGroup] {
            var groups = HeadwordGroup.group(inputs, priority: request.priority)
            HeadwordGroup.attachMeta(&groups, from: store, sortDictionary: request.sortDictionary)
            return groups
        }

        if Kana.containsJapanese(text) {
            outcome.direct = HeadwordGroup.sortedForScan(ranked(scanner.scan(text, in: store).map(\.groupInput)))
            typedKana = [text]
        } else {
            // Romaji is one word: "to run" is English, not とるん.
            if !text.contains(" ") {
                // A long vowel written ō can be おう, おお or オー: try each.
                typedKana = Romaji.readings(text)
                var inputs: [(entry: TermEntry, matchedText: String, reasons: [Reason])] = []
                for kana in typedKana {
                    // Only whole-word matches: "sake" should give 酒, not さ + rest.
                    let exact = scanner.scan(kana, in: store).filter { $0.matchedLength == kana.count }
                    guard !exact.isEmpty else { continue }
                    if outcome.romajiReading == nil { outcome.romajiReading = kana }
                    inputs += exact.map(\.groupInput)
                }
                if !inputs.isEmpty { outcome.direct = HeadwordGroup.sortedForScan(ranked(inputs)) }
            }
            // A match inside a compound (仕立て → ◎仕立屋 "sarto") shows the compound itself.
            var meaningInputs: [(entry: TermEntry, matchedText: String, reasons: [Reason])] = []
            for hit in store.reverseSearch(text, limit: 30) {
                if let sub = ReverseSearch.subentry(matching: text, glossaryJSON: hit.entry.glossaryJSON),
                   sub != hit.entry.expression {
                    let found = store.entries(matching: sub)
                    if !found.isEmpty {
                        meaningInputs += found.map { ($0, text, []) }
                        continue
                    }
                }
                meaningInputs.append((hit.entry, text, []))
            }
            outcome.byMeaning = ranked(meaningInputs)
            let romajiRank = outcome.direct.compactMap(\.sortRank).min()
            let meaningRank = outcome.byMeaning.prefix(3).compactMap(\.sortRank).min()
            if !outcome.byMeaning.isEmpty {
                switch (romajiRank, meaningRank) {
                case let (r?, m?): outcome.romajiFirst = r <= m
                case (_?, nil): outcome.romajiFirst = true
                default: outcome.romajiFirst = false
                }
            }
        }

        if request.suggest, let first = typedKana.first {
            let shown = Set(outcome.direct.map(\.minedKey))
            outcome.startingWith = suggestions(startingWith: typedKana, store: store, excluding: shown)
            outcome.startingWithText = first
            // しんぶ finds しん and leaves ぶ over: the word being typed is in the list.
            let covered = outcome.direct.map(\.matchedText.count).max() ?? 0
            outcome.suggestionsFirst = !outcome.startingWith.isEmpty && covered < first.count
        }
        // The characters of the word at the top, or of the text itself when
        // it is in no word dictionary (a rare kanji, a name).
        let top = outcome.romajiFirst ? outcome.direct.first ?? outcome.byMeaning.first : outcome.byMeaning.first ?? outcome.direct.first
        let source = top?.expression ?? (Kana.containsJapanese(text) ? text : "")
        let characters = kanjiCharacters(in: source)
        if !characters.isEmpty {
            outcome.kanji = store.kanji(characters)
            outcome.kanjiSource = source
        }
        outcome.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        return outcome
    }

    static let maxKanji = 4

    /// The different kanji of a word, in the order they appear.
    static func kanjiCharacters(in text: String) -> [String] {
        var seen: Set<Character> = []
        var out: [String] = []
        for character in text {
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { continue }
            let isKanji: Bool
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: isKanji = true
            default: isKanji = false
            }
            guard isKanji, seen.insert(character).inserted else { continue }
            out.append(String(character))
            if out.count == maxKanji { break }
        }
        return out
    }

    /// Words that start with any of `prefixes`: the common ones first, then the short ones.
    static func suggestions(startingWith prefixes: [String], store: DictionaryStore, excluding: Set<String> = []) -> [WordSuggestion] {
        var order: [String] = []
        var found: [String: TermEntry] = [:]
        // Katakana typed for a word whose reading is stored in hiragana.
        let all = prefixes.flatMap { [$0, Kana.toHiragana($0)] }
        var tried: Set<String> = []
        for prefix in all where tried.insert(prefix).inserted {
            // One kana alone starts tens of thousands of words: wait for the second.
            guard prefix.count >= 2 || prefix.unicodeScalars.contains(where: { $0.value >= 0x3400 }) else { continue }
            for entry in store.entriesStarting(with: prefix, limit: 300) {
                let key = entry.expression + "|" + entry.reading
                guard !excluding.contains(key), found[key] == nil else { continue }
                found[key] = entry
                order.append(key)
            }
        }
        guard !order.isEmpty else { return [] }
        let ranks = store.frequencyRanks(for: Array(Set(found.values.map(\.expression))))
        let sorted = order.enumerated().sorted { a, b in
            switch (ranks[found[a.element]!.expression], ranks[found[b.element]!.expression]) {
            case let (p?, q?) where p != q: return p < q
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }
        return sorted.prefix(maxSuggestions).map { item in
            let entry = found[item.element]!
            let gloss = GlossaryText.items(fromJSON: entry.glossaryJSON).first ?? ""
            return WordSuggestion(expression: entry.expression, reading: entry.reading == entry.expression ? "" : entry.reading,
                                  gloss: String(gloss.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces))
        }
    }
}

/// The address AnkiMobile opens when a note has really been added. It names
/// the word, so the tick appears for a note that exists, not for a tap.
enum MinedLink {
    /// A code only this copy of Kotoba knows, made once and kept. It travels
    /// in the address given to AnkiMobile, so that a web page or another app
    /// opening `kotoba://mined?k=…` cannot tick a word as sent. Kept where the
    /// share panel reads it too: it sends words to Anki, and the answer comes here.
    static var code: String {
        let key = "mined.code"
        if let saved = SharedStorage.defaults.string(forKey: key), !saved.isEmpty { return saved }
        let made = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        SharedStorage.defaults.set(made, forKey: key)
        return made
    }

    static func returnURL(for minedKey: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return "kotoba://mined?c=\(code)&k=" + (minedKey.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }

    /// The word a `kotoba://mined?c=…&k=…` address is about, when it carries this copy's code.
    static func minedKey(from url: URL) -> String? {
        guard url.scheme == "kotoba", url.host == "mined" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "c" })?.value == code else { return nil }
        let key = items.first { $0.name == "k" }?.value
        return key.flatMap { $0.isEmpty ? nil : $0 }
    }
}
