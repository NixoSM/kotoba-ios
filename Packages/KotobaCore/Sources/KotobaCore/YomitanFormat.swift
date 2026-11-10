import Foundation

/// The `index.json` at the root of every Yomitan dictionary zip.
public struct DictionaryIndex: Codable, Hashable, Sendable {
    public var title: String
    public var revision: String
    public var format: Int?
    public var version: Int?
    public var sequenced: Bool?
    public var author: String?
    public var url: String?
    public var description: String?
    public var attribution: String?
    public var sourceLanguage: String?
    public var targetLanguage: String?
    public var frequencyMode: String?

    /// Older dictionaries use `version`, newer ones `format`.
    public var formatVersion: Int { format ?? version ?? 1 }
}

/// One headword entry from a `term_bank_N.json` file.
public struct TermEntry: Hashable, Sendable {
    public var expression: String
    public var reading: String
    public var definitionTags: [String]
    public var rules: WordClass
    public var score: Int
    /// The glossary kept as raw JSON: it may hold plain strings, images or
    /// structured content, and is only interpreted when it is rendered.
    public var glossaryJSON: Data
    public var sequence: Int?
    public var termTags: [String]
    /// Title of the dictionary the entry came from (filled in by the store).
    public var dictionary: String = ""
    /// Row id in the store, so the glossary can be fetched later.
    public var rowID: Int64? = nil
}

public enum TermMetaKind: String, Sendable {
    case frequency = "freq", pitch, ipa
}

/// One entry from a `term_meta_bank_N.json` file (frequency, pitch accent, IPA).
public struct TermMetaEntry: Hashable, Sendable {
    public var expression: String
    public var kind: TermMetaKind
    public var dataJSON: Data
}

/// One character from a `kanji_bank_N.json` file.
public struct KanjiEntry: Hashable, Sendable {
    public var character: String
    /// Chinese-derived readings, usually in katakana.
    public var onyomi: [String]
    /// Native readings, usually in hiragana, with a dot before the okurigana.
    public var kunyomi: [String]
    public var tags: [String]
    public var meanings: [String]
    /// Extra facts the dictionary gives: stroke count, school grade, JLPT level…
    public var stats: [String: String]
    /// Title of the dictionary the entry came from (filled in by the store).
    public var dictionary: String = ""

    public init(character: String, onyomi: [String], kunyomi: [String], tags: [String], meanings: [String],
                stats: [String: String] = [:], dictionary: String = "") {
        self.character = character
        self.onyomi = onyomi
        self.kunyomi = kunyomi
        self.tags = tags
        self.meanings = meanings
        self.stats = stats
        self.dictionary = dictionary
    }
}

public enum YomitanFormatError: Error, Equatable {
    case notAnArray(file: String)
    case badRow(file: String, row: Int)
}

/// Parses the JSON banks. Uses JSONSerialization because rows are
/// heterogeneous arrays, which Codable handles badly.
public enum YomitanParser {
    public static func index(from data: Data) throws -> DictionaryIndex {
        try JSONDecoder().decode(DictionaryIndex.self, from: data)
    }

    public static func termBank(from data: Data, file: String = "term_bank") throws -> [TermEntry] {
        try termBankWithIndexText(from: data, file: file).map(\.entry)
    }

    /// The entries plus the text reverse search indexes for each, worked out
    /// from the glossary while it is parsed rather than by parsing it again.
    public static func termBankWithIndexText(from data: Data, file: String = "term_bank") throws -> [(entry: TermEntry, indexText: String)] {
        let rows = try array(data, file: file)
        return try rows.enumerated().map { i, raw in
            guard let row = raw as? [Any], row.count >= 6,
                  let expression = row[0] as? String,
                  let reading = row[1] as? String else {
                throw YomitanFormatError.badRow(file: file, row: i)
            }
            let glossary = (row[5] as? [Any]) ?? [row[5]]
            let glossaryJSON = try JSONSerialization.data(withJSONObject: glossary)
            let entry = TermEntry(
                expression: expression,
                reading: reading.isEmpty ? expression : reading,
                definitionTags: tags(row[2]),
                rules: WordClass(yomitanRules: row[3] as? String ?? ""),
                score: (row[4] as? NSNumber)?.intValue ?? 0,
                glossaryJSON: glossaryJSON,
                sequence: row.count > 6 ? (row[6] as? NSNumber)?.intValue : nil,
                termTags: row.count > 7 ? tags(row[7]) : []
            )
            return (entry, ReverseSearch.indexText(fromGlossary: glossary))
        }
    }

    public static func termMetaBank(from data: Data, file: String = "term_meta_bank") throws -> [TermMetaEntry] {
        let rows = try array(data, file: file)
        return try rows.enumerated().compactMap { i, raw in
            guard let row = raw as? [Any], row.count >= 3,
                  let expression = row[0] as? String,
                  let kindRaw = row[1] as? String else {
                throw YomitanFormatError.badRow(file: file, row: i)
            }
            guard let kind = TermMetaKind(rawValue: kindRaw) else { return nil } // unknown kinds are skipped
            let payload = row[2]
            let json = try JSONSerialization.data(withJSONObject: [payload])
            return TermMetaEntry(expression: expression, kind: kind, dataJSON: json)
        }
    }

    /// Format 3 rows are [character, onyomi, kunyomi, tags, [meanings], {stats}];
    /// format 1 lists the meanings one after the other instead.
    public static func kanjiBank(from data: Data, file: String = "kanji_bank") throws -> [KanjiEntry] {
        let rows = try array(data, file: file)
        return try rows.enumerated().map { i, raw in
            guard let row = raw as? [Any], row.count >= 4, let character = row[0] as? String, !character.isEmpty else {
                throw YomitanFormatError.badRow(file: file, row: i)
            }
            var meanings: [String] = []
            var stats: [String: String] = [:]
            if row.count > 4, let list = row[4] as? [Any] {
                meanings = list.compactMap { $0 as? String }
                if row.count > 5, let facts = row[5] as? [String: Any] {
                    for (key, value) in facts { stats[key] = (value as? String) ?? "\(value)" }
                }
            } else {
                meanings = row.dropFirst(4).compactMap { $0 as? String }
            }
            return KanjiEntry(character: character, onyomi: tags(row[1]), kunyomi: tags(row[2]), tags: tags(row[3]),
                              meanings: meanings, stats: stats)
        }
    }

    private static func array(_ data: Data, file: String) throws -> [Any] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw YomitanFormatError.notAnArray(file: file)
        }
        return rows
    }

    private static func tags(_ value: Any) -> [String] {
        (value as? String)?.split(separator: " ").map(String.init) ?? []
    }
}
