import Foundation

/// Anything that can return entries whose headword or reading equals a string.
/// The SQLite store implements it in the app; tests use an in-memory one.
public protocol TermSource: Sendable {
    func entries(matching term: String) -> [TermEntry]
    /// Like `entries(matching:)`, but the glossary may be left empty and
    /// filled in later by `loadGlossaries`, so hits that are thrown away
    /// never cost a definition read.
    func entryHeaders(matching term: String) -> [TermEntry]
    /// Returns the same entries, in the same order, with glossaries filled in.
    func loadGlossaries(_ entries: [TermEntry]) -> [TermEntry]
}

extension TermSource {
    public func entryHeaders(matching term: String) -> [TermEntry] { entries(matching: term) }
    public func loadGlossaries(_ entries: [TermEntry]) -> [TermEntry] { entries }
}

/// A dictionary hit for the text under the user's finger.
public struct LookupResult: Hashable, Sendable {
    /// How many characters of the scanned text this result covers.
    public let matchedLength: Int
    public let matchedText: String
    public let deinflection: Deinflection
    public let entry: TermEntry
}

/// Finds the longest word at the start of a piece of text, Yomitan-style:
/// try the longest prefix first, take it apart, and look up every candidate.
public struct TextScanner: Sendable {
    public var deinflector: Deinflector
    public var maxLength: Int
    /// How many different headwords to return. Short prefixes ("し") match
    /// hundreds of words across many dictionaries; nobody reads that far.
    public var maxHeadwords: Int

    public init(deinflector: Deinflector = Deinflector(), maxLength: Int = 16, maxHeadwords: Int = 16) {
        self.deinflector = deinflector
        self.maxLength = maxLength
        self.maxHeadwords = maxHeadwords
    }

    public func scan(_ text: String, in source: TermSource) -> [LookupResult] {
        let chars = Array(text)
        var results: [LookupResult] = []
        var seen: Set<TermEntry> = []
        var cache: [String: [TermEntry]] = [:]
        for length in stride(from: min(maxLength, chars.count), through: 1, by: -1) {
            let prefix = String(chars[..<length])
            let variants = Set([prefix, Kana.toHiragana(prefix)])
            for variant in variants {
                for candidate in deinflector.deinflect(variant) {
                    let found: [TermEntry]
                    if let cached = cache[candidate.term] {
                        found = cached
                    } else {
                        found = source.entryHeaders(matching: candidate.term)
                        cache[candidate.term] = found
                    }
                    for entry in found where candidate.matches(entryRules: entry.rules) {
                        guard seen.insert(entry).inserted else { continue }
                        results.append(LookupResult(matchedLength: length, matchedText: prefix, deinflection: candidate, entry: entry))
                    }
                }
            }
        }
        // Longest match first, then fewer grammar steps, then the dictionary's own ranking.
        let sorted = results.sorted {
            if $0.matchedLength != $1.matchedLength { return $0.matchedLength > $1.matchedLength }
            if $0.deinflection.reasons.count != $1.deinflection.reasons.count {
                return $0.deinflection.reasons.count < $1.deinflection.reasons.count
            }
            return $0.entry.score > $1.entry.score
        }
        // Keep the best headwords (with every dictionary's entry for them),
        // then read only their definitions.
        var keys: Set<String> = []
        let kept = sorted.filter { r in
            let key = r.entry.expression + "|" + r.entry.reading
            if keys.contains(key) { return true }
            guard keys.count < maxHeadwords else { return false }
            keys.insert(key)
            return true
        }
        let full = source.loadGlossaries(kept.map(\.entry))
        return zip(kept, full).map {
            LookupResult(matchedLength: $0.matchedLength, matchedText: $0.matchedText, deinflection: $0.deinflection, entry: $1)
        }
    }
}

/// Simple in-memory source, used by tests and previews.
public struct MemoryTermSource: TermSource {
    private let byTerm: [String: [TermEntry]]

    public init(_ entries: [TermEntry]) {
        var map: [String: [TermEntry]] = [:]
        for e in entries {
            map[e.expression, default: []].append(e)
            if e.reading != e.expression { map[e.reading, default: []].append(e) }
        }
        byTerm = map
    }

    public func entries(matching term: String) -> [TermEntry] { byTerm[term] ?? [] }
}
