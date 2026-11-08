#if canImport(SQLite3)
import Foundation

/// A dictionary installed in the app.
public struct InstalledDictionary: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var title: String
    public var revision: String
    /// Lower comes first in results.
    public var priority: Int
    public var enabled: Bool
    public var termCount: Int
    public var metaCount: Int
}

public enum DictionaryStoreError: Error, Equatable {
    case alreadyInstalled(title: String)
}

/// All installed dictionaries, in one SQLite file.
///
/// Every public method is safe to call from any thread.
public final class DictionaryStore: TermSource, @unchecked Sendable {
    private let db: SQLiteDatabase
    private let lock = NSLock()

    public static let schemaVersion = 4

    /// Pass `":memory:"` for a throwaway store (tests).
    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try db.execute("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA foreign_keys = ON;
        PRAGMA mmap_size = 268435456;
        PRAGMA cache_size = -16000;
        CREATE TABLE IF NOT EXISTS dictionaries (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL UNIQUE,
            revision TEXT NOT NULL,
            index_json BLOB NOT NULL,
            priority INTEGER NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            term_count INTEGER NOT NULL DEFAULT 0,
            meta_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS terms (
            id INTEGER PRIMARY KEY,
            dict_id INTEGER NOT NULL REFERENCES dictionaries(id) ON DELETE CASCADE,
            expression TEXT NOT NULL,
            reading TEXT NOT NULL,
            rules INTEGER NOT NULL,
            score INTEGER NOT NULL,
            definition_tags TEXT NOT NULL,
            term_tags TEXT NOT NULL,
            sequence INTEGER,
            glossary BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS terms_expression ON terms(expression);
        CREATE INDEX IF NOT EXISTS terms_reading ON terms(reading);
        CREATE INDEX IF NOT EXISTS terms_dict ON terms(dict_id);
        CREATE TABLE IF NOT EXISTS term_meta (
            id INTEGER PRIMARY KEY,
            dict_id INTEGER NOT NULL REFERENCES dictionaries(id) ON DELETE CASCADE,
            expression TEXT NOT NULL,
            kind TEXT NOT NULL,
            data BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS term_meta_expression ON term_meta(expression);
        CREATE INDEX IF NOT EXISTS term_meta_dict ON term_meta(dict_id);
        """)
        try migrate()
    }

    private func migrate() throws {
        var version = 0
        try db.prepare("PRAGMA user_version").rows { version = $0.int(0) }
        if version < 2 {
            // v2: full-text index of definitions for IT/EN → JP search.
            // Dictionaries imported before this get indexed later by buildMissingReverseIndexes.
            try db.execute("""
            ALTER TABLE dictionaries ADD COLUMN reverse_indexed INTEGER NOT NULL DEFAULT 0;
            CREATE VIRTUAL TABLE IF NOT EXISTS gloss_fts USING fts5(text, tokenize = 'unicode61 remove_diacritics 2');
            """)
        }
        if version < 3 {
            // v3: dictionary stylesheets (styles.css inside the zip).
            try db.execute("ALTER TABLE dictionaries ADD COLUMN styles TEXT NOT NULL DEFAULT ''")
        }
        if version < 4 {
            // v4: images and other files bundled in dictionaries.
            try db.execute("""
            CREATE TABLE IF NOT EXISTS media (
                dict_id INTEGER NOT NULL REFERENCES dictionaries(id) ON DELETE CASCADE,
                path TEXT NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (dict_id, path)
            ) WITHOUT ROWID;
            """)
        }
        try db.execute("PRAGMA user_version = \(Self.schemaVersion)")
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Prepared once, reused: a lookup runs the same query hundreds of times.
    /// Call only while holding the lock.
    private var statementCache: [String: SQLiteStatement] = [:]

    private func cached(_ sql: String) throws -> SQLiteStatement {
        if let stmt = statementCache[sql] { return stmt }
        let stmt = try db.prepare(sql)
        statementCache[sql] = stmt
        return stmt
    }

    /// Recomputed after any change to the dictionary list.
    private var frequencyDictionaryCache: [String]?

    // MARK: Dictionaries

    public func dictionaries() throws -> [InstalledDictionary] {
        try locked {
            var out: [InstalledDictionary] = []
            try db.prepare("SELECT id, title, revision, priority, enabled, term_count, meta_count FROM dictionaries ORDER BY priority")
                .rows { r in
                    out.append(InstalledDictionary(id: r.int64(0), title: r.string(1), revision: r.string(2),
                                                   priority: r.int(3), enabled: r.int(4) != 0,
                                                   termCount: r.int(5), metaCount: r.int(6)))
                }
            return out
        }
    }

    /// Each dictionary's styles.css, by title (only those that have one).
    public func stylesheets() -> [String: String] {
        locked {
            var out: [String: String] = [:]
            try? db.prepare("SELECT title, styles FROM dictionaries WHERE styles != ''").rows { out[$0.string(0)] = $0.string(1) }
            return out
        }
    }

    public func setEnabled(_ enabled: Bool, dictionary id: Int64) throws {
        try locked {
            frequencyDictionaryCache = nil
            try db.prepare("UPDATE dictionaries SET enabled = ?1 WHERE id = ?2").bind(enabled, id).run()
        }
    }

    /// Saves a new order: the first id gets the highest priority.
    public func reorder(_ ids: [Int64]) throws {
        try locked {
            frequencyDictionaryCache = nil
            try db.transaction {
                let stmt = try db.prepare("UPDATE dictionaries SET priority = ?1 WHERE id = ?2")
                for (i, id) in ids.enumerated() { try stmt.bind(i, id).run() }
            }
        }
    }

    public func delete(dictionary id: Int64) throws {
        try locked {
            frequencyDictionaryCache = nil
            try db.transaction {
                try db.prepare("DELETE FROM gloss_fts WHERE rowid IN (SELECT id FROM terms WHERE dict_id = ?1)").bind(id).run()
                try db.prepare("DELETE FROM dictionaries WHERE id = ?1").bind(id).run()
            }
        }
    }

    // MARK: Import

    /// Receives the parsed banks one at a time, so a large dictionary never
    /// has to fit in memory all at once.
    public final class ImportSession {
        fileprivate let db: SQLiteDatabase
        fileprivate let dictID: Int64
        private let insertTerm: SQLiteStatement
        private let insertMeta: SQLiteStatement
        private let insertFTS: SQLiteStatement
        private let insertMedia: SQLiteStatement
        public private(set) var termCount = 0
        public private(set) var metaCount = 0

        fileprivate init(db: SQLiteDatabase, dictID: Int64) throws {
            self.db = db
            self.dictID = dictID
            insertTerm = try db.prepare("""
            INSERT INTO terms (dict_id, expression, reading, rules, score, definition_tags, term_tags, sequence, glossary)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            """)
            insertMeta = try db.prepare("INSERT INTO term_meta (dict_id, expression, kind, data) VALUES (?1, ?2, ?3, ?4)")
            insertFTS = try db.prepare("INSERT INTO gloss_fts (rowid, text) VALUES (?1, ?2)")
            insertMedia = try db.prepare("INSERT OR REPLACE INTO media (dict_id, path, data) VALUES (?1, ?2, ?3)")
        }

        public func add(_ terms: [TermEntry]) throws {
            for t in terms {
                try insertTerm.bind(dictID, t.expression, t.reading, Int(t.rules.rawValue), t.score,
                                    t.definitionTags.joined(separator: " "), t.termTags.joined(separator: " "),
                                    t.sequence, t.glossaryJSON).run()
                let text = ReverseSearch.indexText(fromGlossaryJSON: t.glossaryJSON)
                if !text.isEmpty { try insertFTS.bind(db.lastInsertRowID, text).run() }
            }
            termCount += terms.count
        }

        public func addMedia(path: String, data: Data) throws {
            try insertMedia.bind(dictID, path, data).run()
        }

        public func add(_ meta: [TermMetaEntry]) throws {
            for m in meta {
                try insertMeta.bind(dictID, m.expression, m.kind.rawValue, m.dataJSON).run()
            }
            metaCount += meta.count
        }
    }

    /// Installs a dictionary in a single transaction: if `body` throws,
    /// nothing is left behind.
    public func install(index: DictionaryIndex, styles: String = "", _ body: (ImportSession) throws -> Void) throws -> InstalledDictionary {
        try locked {
            frequencyDictionaryCache = nil
            return try db.transaction {
                var exists = false
                try db.prepare("SELECT 1 FROM dictionaries WHERE title = ?1").bind(index.title).rows { _ in exists = true }
                if exists { throw DictionaryStoreError.alreadyInstalled(title: index.title) }

                var priority = 0
                try db.prepare("SELECT COALESCE(MAX(priority) + 1, 0) FROM dictionaries").rows { priority = $0.int(0) }
                let indexJSON = try JSONEncoder().encode(index)
                try db.prepare("INSERT INTO dictionaries (title, revision, index_json, priority, styles) VALUES (?1, ?2, ?3, ?4, ?5)")
                    .bind(index.title, index.revision, indexJSON, priority, styles).run()
                let id = db.lastInsertRowID

                let session = try ImportSession(db: db, dictID: id)
                try body(session)
                try db.prepare("UPDATE dictionaries SET term_count = ?1, meta_count = ?2, reverse_indexed = 1 WHERE id = ?3")
                    .bind(session.termCount, session.metaCount, id).run()
                return InstalledDictionary(id: id, title: index.title, revision: index.revision, priority: priority,
                                           enabled: true, termCount: session.termCount, metaCount: session.metaCount)
            }
        }
    }

    // MARK: Reverse search (IT/EN → JP)

    public struct ReverseIndexProgress: Sendable {
        public var dictionaryTitle: String
        public var done: Int
        public var total: Int
    }

    /// Indexes definitions of dictionaries imported before reverse search
    /// existed. Works in small batches so lookups stay responsive meanwhile.
    public func buildMissingReverseIndexes(progress: (ReverseIndexProgress) -> Void = { _ in }) throws {
        let pending: [(id: Int64, title: String, total: Int)] = try locked {
            var out: [(id: Int64, title: String, total: Int)] = []
            try db.prepare("SELECT id, title, term_count FROM dictionaries WHERE reverse_indexed = 0").rows {
                out.append((id: $0.int64(0), title: $0.string(1), total: $0.int(2)))
            }
            return out
        }
        for dict in pending {
            var lastID: Int64 = 0
            var done = 0
            while true {
                let batch: Int = try locked {
                    try db.transaction {
                        var rows: [(Int64, Data)] = []
                        try db.prepare("SELECT id, glossary FROM terms WHERE dict_id = ?1 AND id > ?2 ORDER BY id LIMIT 4000")
                            .bind(dict.id, lastID).rows { rows.append(($0.int64(0), $0.data(1))) }
                        let insert = try db.prepare("INSERT OR REPLACE INTO gloss_fts (rowid, text) VALUES (?1, ?2)")
                        for (id, glossary) in rows {
                            let text = ReverseSearch.indexText(fromGlossaryJSON: glossary)
                            if !text.isEmpty { try insert.bind(id, text).run() }
                        }
                        if let last = rows.last { lastID = last.0 }
                        if rows.isEmpty {
                            try db.prepare("UPDATE dictionaries SET reverse_indexed = 1 WHERE id = ?1").bind(dict.id).run()
                        }
                        return rows.count
                    }
                }
                if batch == 0 { break }
                done += batch
                progress(ReverseIndexProgress(dictionaryTitle: dict.title, done: done, total: dict.total))
            }
        }
    }

    /// A headword found through its definitions, with how well it matched.
    public struct ReverseHit: Sendable {
        public var entry: TermEntry
        public var score: Int
        /// Lower is more common; nil when no frequency dictionary knows the word.
        public var frequencyRank: Double?
    }

    public func reverseSearch(_ text: String, limit: Int = 60) -> [ReverseHit] {
        guard let match = ReverseSearch.ftsQuery(for: text) else { return [] }
        // 1. Score the matching definitions using the index text alone.
        let scored: [(id: Int64, score: Int)] = locked {
            var out: [(id: Int64, score: Int)] = []
            try? cached("SELECT rowid, text FROM gloss_fts WHERE gloss_fts MATCH ?1 ORDER BY bm25(gloss_fts) LIMIT 2000")
                .bind(match).rows { r in
                    let score = ReverseSearch.score(query: text, indexText: r.string(1))
                    if score > 0 { out.append((r.int64(0), score)) }
                }
            return out
        }
        let best = scored.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(300).map(\.element)
        guard !best.isEmpty else { return [] }
        var scores: [Int64: Int] = [:]
        for b in best { scores[b.id] = max(scores[b.id] ?? 0, b.score) }

        // 2. Headwords for those definitions, from enabled dictionaries only.
        var hits: [ReverseHit] = locked {
            var out: [ReverseHit] = []
            let ids = scores.keys.map(String.init).joined(separator: ",")
            try? db.prepare("""
            SELECT \(Self.headerColumns(glossary: false))
            FROM terms t JOIN dictionaries d ON d.id = t.dict_id
            WHERE d.enabled = 1 AND t.id IN (\(ids))
            """).rows { r in
                let entry = Self.entry(r)
                out.append(ReverseHit(entry: entry, score: scores[entry.rowID ?? 0] ?? 0, frequencyRank: nil))
            }
            return out
        }
        let ranks = frequencyRanks(for: Array(Set(hits.map(\.entry.expression))))
        for i in hits.indices { hits[i].frequencyRank = ranks[hits[i].entry.expression] }
        hits.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            switch ($0.frequencyRank, $1.frequencyRank) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.entry.score > $1.entry.score
            }
        }
        let top = Array(hits.prefix(limit))
        let full = loadGlossaries(top.map(\.entry))
        return zip(top, full).map { hit, entry in
            var hit = hit
            hit.entry = entry
            return hit
        }
    }

    /// Frequency rank of each word, from the highest-priority enabled
    /// frequency dictionary that knows it. Lower = more common.
    public func frequencyRanks(for expressions: [String]) -> [String: Double] {
        guard !expressions.isEmpty else { return [:] }
        return locked {
            var occurrenceBased: [Int64: Bool] = [:]
            var out: [String: Double] = [:]
            let placeholders = Array(repeating: "?", count: expressions.count).joined(separator: ",")
            do {
                let stmt = try db.prepare("""
                SELECT m.expression, m.data, d.id, d.index_json
                FROM term_meta m JOIN dictionaries d ON d.id = m.dict_id
                WHERE d.enabled = 1 AND m.kind = 'freq' AND m.expression IN (\(placeholders))
                ORDER BY d.priority
                """)
                stmt.bindArray(expressions)
                try stmt.rows { r in
                    let expression = r.string(0)
                    guard out[expression] == nil else { return }
                    let dictID = r.int64(2)
                    if occurrenceBased[dictID] == nil {
                        let index = try? JSONDecoder().decode(DictionaryIndex.self, from: r.data(3))
                        occurrenceBased[dictID] = index?.frequencyMode == "occurrence-based"
                    }
                    guard let wrapped = (try? JSONSerialization.jsonObject(with: r.data(1))) as? [Any],
                          let first = wrapped.first,
                          let value = ReverseSearch.frequencyValue(first) else { return }
                    out[expression] = occurrenceBased[dictID]! ? -value : value
                }
            } catch {
                return [:]
            }
            return out
        }
    }

    /// Frequencies and pitch accents for a set of words, from enabled
    /// dictionaries, in dictionary priority order.
    public struct MetaBundle: Sendable {
        public var frequencies: [String: [FrequencyInfo]] = [:]
        public var pitches: [String: [PitchInfo]] = [:]
    }

    public func termMeta(for expressions: [String]) -> MetaBundle {
        guard !expressions.isEmpty else { return MetaBundle() }
        return locked {
            var bundle = MetaBundle()
            let placeholders = Array(repeating: "?", count: expressions.count).joined(separator: ",")
            do {
                let stmt = try db.prepare("""
                SELECT m.expression, m.kind, m.data, d.title
                FROM term_meta m JOIN dictionaries d ON d.id = m.dict_id
                WHERE d.enabled = 1 AND m.kind IN ('freq', 'pitch') AND m.expression IN (\(placeholders))
                ORDER BY d.priority, m.id
                """)
                stmt.bindArray(expressions)
                try stmt.rows { r in
                    guard let wrapped = (try? JSONSerialization.jsonObject(with: r.data(2))) as? [Any],
                          let json = wrapped.first else { return }
                    let expression = r.string(0), title = r.string(3)
                    if r.string(1) == "freq" {
                        if let f = TermMetaParser.frequency(json, dictionary: title) { bundle.frequencies[expression, default: []].append(f) }
                    } else if let p = TermMetaParser.pitch(json, dictionary: title) {
                        bundle.pitches[expression, default: []].append(p)
                    }
                }
            } catch {
                return MetaBundle()
            }
            return bundle
        }
    }

    /// Titles of enabled dictionaries that contain frequency data, in priority order.
    public func frequencyDictionaries() -> [String] {
        locked {
            if let cachedList = frequencyDictionaryCache { return cachedList }
            var out: [String] = []
            try? db.prepare("""
            SELECT d.title FROM dictionaries d
            WHERE d.enabled = 1 AND EXISTS (SELECT 1 FROM term_meta m WHERE m.dict_id = d.id AND m.kind = 'freq')
            ORDER BY d.priority
            """).rows { out.append($0.string(0)) }
            frequencyDictionaryCache = out
            return out
        }
    }

    /// A file bundled with a dictionary (usually an image used in definitions).
    public func media(dictionary: String, path: String) -> Data? {
        locked {
            var out: Data?
            try? db.prepare("""
            SELECT m.data FROM media m JOIN dictionaries d ON d.id = m.dict_id WHERE d.title = ?1 AND m.path = ?2
            """).bind(dictionary, path).rows { out = $0.data(0) }
            return out
        }
    }

    // MARK: Lookup

    public func entries(matching term: String) -> [TermEntry] { lookup(term, glossary: true) }

    public func entryHeaders(matching term: String) -> [TermEntry] { lookup(term, glossary: false) }

    public func loadGlossaries(_ entries: [TermEntry]) -> [TermEntry] {
        let ids = entries.compactMap { $0.glossaryJSON.isEmpty ? $0.rowID : nil }
        guard !ids.isEmpty else { return entries }
        var glossaries: [Int64: Data] = [:]
        _ = locked {
            try? db.prepare("SELECT id, glossary FROM terms WHERE id IN (\(ids.map(String.init).joined(separator: ",")))")
                .rows { glossaries[$0.int64(0)] = $0.data(1) }
        }
        return entries.map { entry in
            guard let id = entry.rowID, let glossary = glossaries[id] else { return entry }
            var filled = entry
            filled.glossaryJSON = glossary
            return filled
        }
    }

    private func lookup(_ term: String, glossary: Bool) -> [TermEntry] {
        locked {
            var out: [TermEntry] = []
            do {
                try cached("""
                SELECT \(Self.headerColumns(glossary: glossary))
                FROM terms t JOIN dictionaries d ON d.id = t.dict_id
                WHERE d.enabled = 1 AND (t.expression = ?1 OR t.reading = ?1)
                ORDER BY d.priority, t.score DESC
                """).bind(term).rows { out.append(Self.entry($0)) }
            } catch {
                return []
            }
            return out
        }
    }

    /// Columns read by `entry(_:)`, in order.
    private static func headerColumns(glossary: Bool) -> String {
        "t.expression, t.reading, t.rules, t.score, t.definition_tags, t.term_tags, t.sequence, "
            + (glossary ? "t.glossary" : "NULL") + ", d.title, t.id"
    }

    private static func entry(_ r: SQLiteRow) -> TermEntry {
        TermEntry(
            expression: r.string(0), reading: r.string(1),
            definitionTags: Self.split(r.string(4)),
            rules: WordClass(rawValue: UInt16(truncatingIfNeeded: r.int(2))),
            score: r.int(3), glossaryJSON: r.data(7),
            sequence: r.isNull(6) ? nil : r.int(6),
            termTags: Self.split(r.string(5)),
            dictionary: r.string(8),
            rowID: r.int64(9))
    }

    private static func split(_ s: String) -> [String] {
        s.split(separator: " ").map(String.init)
    }
}
#endif
