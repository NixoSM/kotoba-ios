import Foundation

/// The parts of a Yomitan settings backup that Kotoba can apply.
public struct YomitanSettings: Sendable {
    public struct DictionarySetting: Hashable, Sendable {
        public var name: String
        public var enabled: Bool
    }

    public var profileName: String
    /// In Yomitan's order, which is the result order.
    public var dictionaries: [DictionarySetting]
    public var sortFrequencyDictionary: String?
    public var ankiTermFormat: AnkiNoteFormat?

    public enum ParseError: Error { case notYomitanSettings }

    public static func parse(_ data: Data) throws -> YomitanSettings {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notYomitanSettings }
        // A backup wraps the options; a raw options object works too.
        let options = (root["options"] as? [String: Any]) ?? root
        guard let profiles = options["profiles"] as? [[String: Any]], !profiles.isEmpty else { throw ParseError.notYomitanSettings }
        let current = min((options["profileCurrent"] as? Int) ?? 0, profiles.count - 1)
        let profile = profiles[current]
        let o = profile["options"] as? [String: Any] ?? [:]
        let raw = String(decoding: data, as: UTF8.self)

        let dictionaries: [DictionarySetting]
        if let list = o["dictionaries"] as? [[String: Any]] {
            dictionaries = list.compactMap { d in
                (d["name"] as? String).map { DictionarySetting(name: $0, enabled: d["enabled"] as? Bool ?? true) }
            }
        } else if let map = o["dictionaries"] as? [String: [String: Any]] {
            // Older versions: {title: {priority, enabled}}; higher priority first.
            dictionaries = map.sorted { ($0.value["priority"] as? Int ?? 0) > ($1.value["priority"] as? Int ?? 0) }
                .map { DictionarySetting(name: $0.key, enabled: $0.value["enabled"] as? Bool ?? true) }
        } else {
            dictionaries = []
        }

        let general = o["general"] as? [String: Any] ?? [:]
        let anki = o["anki"] as? [String: Any] ?? [:]
        let tags = (anki["tags"] as? [String]) ?? []

        var format: AnkiNoteFormat?
        if let formats = anki["cardFormats"] as? [[String: Any]],
           let term = formats.first(where: { ($0["type"] as? String ?? "term") == "term" && !(($0["model"] as? String) ?? "").isEmpty }) {
            format = noteFormat(term, tags: tags, raw: raw)
        } else if let term = anki["terms"] as? [String: Any], !((term["model"] as? String) ?? "").isEmpty {
            format = noteFormat(term, tags: tags, raw: raw)
        }

        let sortDictionary = general["sortFrequencyDictionary"] as? String
        return YomitanSettings(profileName: profile["name"] as? String ?? "Default",
                               dictionaries: dictionaries,
                               sortFrequencyDictionary: (sortDictionary?.isEmpty ?? true) ? nil : sortDictionary,
                               ankiTermFormat: format)
    }

    private static func noteFormat(_ o: [String: Any], tags: [String], raw: String) -> AnkiNoteFormat {
        let fieldsObject = o["fields"] as? [String: Any] ?? [:]
        var fields = fieldsObject.compactMap { name, value -> AnkiNoteFormat.Field? in
            if let s = value as? String { return .init(name: name, template: s) }
            if let v = (value as? [String: Any])?["value"] as? String { return .init(name: name, template: v) }
            return nil
        }
        // JSON objects lose their order when parsed; recover it from the file text.
        fields.sort {
            (raw.range(of: "\"\($0.name)\":")?.lowerBound ?? raw.endIndex) < (raw.range(of: "\"\($1.name)\":")?.lowerBound ?? raw.endIndex)
        }
        return AnkiNoteFormat(deck: o["deck"] as? String ?? "Default", model: o["model"] as? String ?? "",
                              fields: fields, tags: tags.isEmpty ? ["kotoba"] : tags)
    }
}

#if canImport(SQLite3)
extension DictionaryStore {
    /// Applies Yomitan's dictionary order and on/off switches to the installed
    /// dictionaries. Dictionaries Yomitan doesn't mention keep their place after.
    @discardableResult
    public func apply(_ settings: [YomitanSettings.DictionarySetting]) throws -> (applied: Int, notInstalled: [String]) {
        let installed = try dictionaries()
        let byTitle = Dictionary(installed.map { ($0.title, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [Int64] = []
        var notInstalled: [String] = []
        for s in settings {
            guard let d = byTitle[s.name] else { notInstalled.append(s.name); continue }
            order.append(d.id)
            if d.enabled != s.enabled { try setEnabled(s.enabled, dictionary: d.id) }
        }
        let rest = installed.map(\.id).filter { !order.contains($0) }
        try reorder(order + rest)
        return (order.count, notInstalled)
    }
}
#endif
