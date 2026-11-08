import Foundation
import KotobaCore

/// One headword with every dictionary's definitions merged under it
/// (Yomitan's "merge" result mode, which is how you have it set up).
struct HeadwordGroup: Identifiable, Sendable {
    let id: String
    let expression: String
    let reading: String
    let matchedText: String
    let reasons: [Reason]
    var partsOfSpeech: [String] = []
    /// HTML fragments per dictionary, in dictionary priority order.
    var definitions: [(dictionary: String, items: [String])] = []
    var frequencies: [FrequencyInfo] = []
    var pitches: [PitchInfo] = []
    /// Value from the sort dictionary; lower = more common.
    var sortRank: Double?

    static func group(_ results: [(entry: TermEntry, matchedText: String, reasons: [Reason])]) -> [HeadwordGroup] {
        var order: [String] = []
        var groups: [String: HeadwordGroup] = [:]
        for r in results {
            let key = r.entry.expression + "|" + r.entry.reading
            let dictionary = r.entry.dictionary
            let items = GlossaryHTML.items(fromJSON: r.entry.glossaryJSON) { MediaSchemeHandler.url(dictionary: dictionary, path: $0) }
            if groups[key] == nil {
                order.append(key)
                groups[key] = HeadwordGroup(id: key, expression: r.entry.expression, reading: r.entry.reading,
                                            matchedText: r.matchedText, reasons: r.reasons)
            }
            for tag in r.entry.definitionTags where !groups[key]!.partsOfSpeech.contains(tag) {
                groups[key]!.partsOfSpeech.append(tag)
            }
            if let i = groups[key]!.definitions.firstIndex(where: { $0.dictionary == r.entry.dictionary }) {
                groups[key]!.definitions[i].items += items
            } else {
                groups[key]!.definitions.append((r.entry.dictionary, items))
            }
        }
        return order.compactMap { groups[$0] }
    }

    /// Adds frequencies and pitch accents, keeping only those for this reading.
    static func attachMeta(_ groups: inout [HeadwordGroup], from store: DictionaryStore, sortDictionary: String?) {
        let bundle = store.termMeta(for: Array(Set(groups.map(\.expression))))
        let sortDictionary = sortDictionary ?? store.frequencyDictionaries().first
        for i in groups.indices {
            let reading = Kana.toHiragana(groups[i].reading)
            groups[i].frequencies = (bundle.frequencies[groups[i].expression] ?? []).filter {
                $0.reading == nil || Kana.toHiragana($0.reading!) == reading
            }
            groups[i].pitches = (bundle.pitches[groups[i].expression] ?? []).filter { Kana.toHiragana($0.reading) == reading }
            groups[i].sortRank = groups[i].frequencies.first { $0.dictionary == sortDictionary }?.value
        }
    }

    /// Longest match first, then fewer grammar steps, then more common words.
    static func sortedForScan(_ groups: [HeadwordGroup]) -> [HeadwordGroup] {
        groups.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.matchedText.count != y.matchedText.count { return x.matchedText.count > y.matchedText.count }
            if x.reasons.count != y.reasons.count { return x.reasons.count < y.reasons.count }
            switch (x.sortRank, y.sortRank) {
            case let (p?, q?) where p != q: return p < q
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    func miningContext(sentence: String) -> MiningContext {
        MiningContext(expression: expression, reading: reading, sentence: sentence, matchedText: matchedText,
                      reasons: reasons, definitions: definitions.map { ($0.dictionary, $0.items) },
                      frequencies: frequencies, pitches: pitches, partsOfSpeech: partsOfSpeech)
    }

    var minedKey: String { expression + "|" + reading }
}

extension LookupResult {
    var groupInput: (entry: TermEntry, matchedText: String, reasons: [Reason]) {
        (entry, matchedText, deinflection.reasons)
    }
}
