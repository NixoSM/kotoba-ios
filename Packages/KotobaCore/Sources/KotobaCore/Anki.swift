import Foundation

/// Which Anki note to create and how to fill each field. Field values are
/// Yomitan-style templates such as "{expression}" or "{furigana-plain}".
public struct AnkiNoteFormat: Codable, Hashable, Sendable {
    public var deck: String
    public var model: String
    public var fields: [Field]
    public var tags: [String]

    public struct Field: Codable, Hashable, Sendable {
        public var name: String
        public var template: String
        public init(name: String, template: String) { self.name = name; self.template = template }
    }

    public init(deck: String, model: String, fields: [Field], tags: [String] = ["kotoba"]) {
        self.deck = deck
        self.model = model
        self.fields = fields
        self.tags = tags
    }

    /// Fields of the popular "Lapis"/"Animecards" style, as a starting point.
    public static let example = AnkiNoteFormat(deck: "Default", model: "Animecards", fields: [
        Field(name: "Word", template: "{expression}"),
        Field(name: "Reading", template: "{furigana-plain}"),
        Field(name: "Glossary", template: "{glossary}"),
        Field(name: "Sentence", template: "{cloze-prefix}<b>{cloze-body}</b>{cloze-suffix}"),
        Field(name: "Graph", template: "{pitch-accents}"),
    ])
}

/// One dictionary entry for the word (in JMdict, one sense), with its tags.
public struct MiningSense: Sendable, Hashable {
    public var dictionary: String
    public var tags: [String]
    public var html: [String]
    public init(dictionary: String, tags: [String], html: [String]) {
        self.dictionary = dictionary
        self.tags = tags
        self.html = html
    }
}

/// What we know about the word being mined.
public struct MiningContext: Sendable {
    public var expression: String
    public var reading: String
    /// The text the word was found in (search query or OCR line), and where.
    public var sentence: String
    public var matchedText: String
    public var reasons: [Reason]
    public var definitions: [(dictionary: String, html: [String])]
    public var frequencies: [FrequencyInfo]
    public var pitches: [PitchInfo]
    public var partsOfSpeech: [String]
    /// Entry by entry, as Yomitan builds {glossary}. Falls back to `definitions`.
    public var senses: [MiningSense]

    public init(expression: String, reading: String, sentence: String, matchedText: String, reasons: [Reason],
                definitions: [(dictionary: String, html: [String])], frequencies: [FrequencyInfo],
                pitches: [PitchInfo], partsOfSpeech: [String], senses: [MiningSense] = []) {
        self.senses = senses.isEmpty ? definitions.map { MiningSense(dictionary: $0.dictionary, tags: [], html: $0.html) } : senses
        self.expression = expression
        self.reading = reading
        self.sentence = sentence
        self.matchedText = matchedText
        self.reasons = reasons
        self.definitions = definitions
        self.frequencies = frequencies
        self.pitches = pitches
        self.partsOfSpeech = partsOfSpeech
    }
}

public enum AnkiFieldRenderer {
    /// Markers Kotoba cannot fill yet (audio, screenshots...): they render empty.
    public static func unsupportedMarkers(in format: AnkiNoteFormat) -> [String] {
        let known: Set<String> = Set(markers.keys)
        var out: [String] = []
        for f in format.fields {
            for marker in markerNames(in: f.template) where !known.contains(marker) && !marker.hasPrefix("single-glossary-") {
                if !out.contains(marker) { out.append(marker) }
            }
        }
        return out
    }

    public static func render(_ template: String, _ c: MiningContext) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            out += value(of: name, c)
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    static func markerNames(in template: String) -> [String] {
        var names: [String] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            names.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    private static func value(of name: String, _ c: MiningContext) -> String {
        if name.hasPrefix("single-glossary-") {
            let wanted = name.dropFirst("single-glossary-".count).lowercased()
            let senses = c.senses.filter { slug($0.dictionary) == wanted || $0.dictionary.lowercased() == wanted }
            return yomitanGlossary(senses, dictionaryTag: false)
        }
        return markers[name]?(c) ?? ""
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static let markers: [String: (MiningContext) -> String] = [
        "expression": { $0.expression },
        "reading": { $0.reading },
        "furigana": { Furigana.html(expression: $0.expression, reading: $0.reading) },
        "furigana-plain": { Furigana.ankiPlain(expression: $0.expression, reading: $0.reading) },
        "glossary": { yomitanGlossary($0.senses) },
        "glossary-no-dictionary": { yomitanGlossary($0.senses, dictionaryTag: false) },
        "glossary-first": { yomitanGlossary(firstDictionary($0.senses)) },
        "glossary-brief": { yomitanGlossary($0.senses, brief: true) },
        "glossary-first-brief": { yomitanGlossary(firstDictionary($0.senses), brief: true) },
        "sentence": { GlossaryHTML.escape($0.sentence) },
        "cloze-prefix": { cloze($0).prefix },
        "cloze-body": { cloze($0).body },
        "cloze-suffix": { cloze($0).suffix },
        "search-query": { GlossaryHTML.escape($0.matchedText) },
        "dictionary": { GlossaryHTML.escape($0.definitions.first?.dictionary ?? "") },
        "part-of-speech": { GlossaryHTML.escape($0.partsOfSpeech.joined(separator: ", ")) },
        "conjugation": { $0.reasons.map(\.rawValue).joined(separator: " « ") },
        "frequencies": { c in
            "<ul>" + c.frequencies.map { "<li>\(GlossaryHTML.escape($0.dictionary)): \(GlossaryHTML.escape($0.display))</li>" }.joined() + "</ul>"
        },
        "frequency-harmonic-rank": { c in harmonic(c.frequencies) },
        "frequency-average-rank": { c in
            guard !c.frequencies.isEmpty else { return "" }
            return String(Int((c.frequencies.map(\.value).reduce(0, +) / Double(c.frequencies.count)).rounded()))
        },
        "pitch-accents": { c in PitchHTML.list(c.pitches, reading: c.reading) },
        "pitch-accent-graphs": { c in PitchHTML.list(c.pitches, reading: c.reading) },
        "pitch-accent-positions": { c in
            Array(Set(c.pitches.filter { $0.reading == c.reading }.flatMap(\.positions))).sorted().map(String.init).joined(separator: ", ")
        },
        "tags": { _ in "" },
    ]

    /// Same idea as Yomitan's: a harmonic mean, so one very rare listing pulls the rank up.
    static func harmonic(_ frequencies: [FrequencyInfo]) -> String {
        let values = frequencies.map(\.value).filter { $0 > 0 }
        guard !values.isEmpty else { return "9999999" }
        let mean = Double(values.count) / values.reduce(0) { $0 + 1 / $1 }
        return String(Int(mean.rounded()))
    }

    private static func firstDictionary(_ senses: [MiningSense]) -> [MiningSense] {
        guard let first = senses.first?.dictionary else { return [] }
        return senses.filter { $0.dictionary == first }
    }

    /// The same HTML Yomitan's default {glossary} produces (compact tags on), so
    /// note types written for Yomitan (Animecards, Lapis…) style it as usual:
    /// <div style="text-align: left;" class="yomitan-glossary"><ol><li data-dictionary="…"><i>(n, uk, JMdict)</i> <ul><li>…</li></ul></li>…</ol></div>
    public static func yomitanGlossary(_ senses: [MiningSense], dictionaryTag: Bool = true, brief: Bool = false) -> String {
        guard !senses.isEmpty else { return "" }
        var previousDictionary: String?
        var previousTags: [String]?
        var items: [(dictionary: String, html: String)] = []
        for sense in senses {
            var labels: [String] = []
            if !brief {
                if sense.tags != previousTags || sense.dictionary != previousDictionary { labels += sense.tags }
                if dictionaryTag && sense.dictionary != previousDictionary { labels.append(sense.dictionary) }
            }
            var html = labels.isEmpty ? "" : "<i>(" + labels.map(GlossaryHTML.escape).joined(separator: ", ") + ")</i> "
            if sense.html.count <= 1 {
                html += sense.html.first ?? ""
            } else {
                html += "<ul>" + sense.html.map { "<li>\($0)</li>" }.joined() + "</ul>"
            }
            items.append((sense.dictionary, html))
            previousDictionary = sense.dictionary
            previousTags = sense.tags
        }
        let body = items.count == 1
            ? items[0].html
            : "<ol>" + items.map { "<li data-dictionary=\"\(GlossaryHTML.escape($0.dictionary))\">\($0.html)</li>" }.joined() + "</ol>"
        return "<div style=\"text-align: left;\" class=\"yomitan-glossary\">\(body)</div>"
    }

    static func glossary(_ defs: [(dictionary: String, html: [String])], withNames: Bool) -> String {
        defs.map { d in
            let items = d.html.count == 1 ? d.html[0] : "<ol>" + d.html.map { "<li>\($0)</li>" }.joined() + "</ol>"
            return withNames ? "<div><i>(\(GlossaryHTML.escape(d.dictionary)))</i> \(items)</div>" : "<div>\(items)</div>"
        }.joined()
    }

    static func cloze(_ c: MiningContext) -> (prefix: String, body: String, suffix: String) {
        guard let range = c.sentence.range(of: c.matchedText) else {
            return ("", GlossaryHTML.escape(c.sentence.isEmpty ? c.matchedText : c.sentence), "")
        }
        return (GlossaryHTML.escape(String(c.sentence[..<range.lowerBound])),
                GlossaryHTML.escape(c.matchedText),
                GlossaryHTML.escape(String(c.sentence[range.upperBound...])))
    }
}

/// Pitch accent drawn with HTML: a line over high morae and a tick at the drop.
public enum PitchHTML {
    public static func list(_ pitches: [PitchInfo], reading: String) -> String {
        var seen: Set<Int> = []
        let positions = pitches.filter { Kana.toHiragana($0.reading) == Kana.toHiragana(reading) }
            .flatMap(\.positions).filter { seen.insert($0).inserted }
        guard !positions.isEmpty else { return "" }
        let items = positions.map { word(reading, downstep: $0) }
        return items.count == 1 ? items[0] : "<ol>" + items.map { "<li>\($0)</li>" }.joined() + "</ol>"
    }

    public static func word(_ reading: String, downstep: Int) -> String {
        let morae = Mora.split(reading)
        let highs = Mora.pattern(morae: morae.count, downstep: downstep)
        var html = "<span class=\"pitch\">"
        for (i, mora) in morae.enumerated() {
            let high = highs[i]
            let drop = high && (i + 1 < highs.count) && !highs[i + 1]
            let style = (high ? "border-top:1px solid currentColor;" : "") + (drop ? "border-right:1px solid currentColor;" : "")
            html += style.isEmpty ? GlossaryHTML.escape(mora) : "<span style=\"\(style)\">\(GlossaryHTML.escape(mora))</span>"
        }
        return html + "</span> [\(downstep)]"
    }
}

/// Builds the AnkiMobile link that opens the "Add" screen already filled in.
/// AnkiMobile documents this scheme; it cannot check duplicates or attach media.
public enum AnkiMobileLink {
    public static func url(format: AnkiNoteFormat, context: MiningContext, returnURL: String? = "kotoba://mined") -> URL? {
        var items = [
            URLQueryItem(name: "type", value: format.model),
            URLQueryItem(name: "deck", value: format.deck),
            URLQueryItem(name: "dupes", value: "1"),
        ]
        if !format.tags.isEmpty { items.append(URLQueryItem(name: "tags", value: format.tags.joined(separator: " "))) }
        for field in format.fields {
            let value = AnkiFieldRenderer.render(field.template, context)
            if !value.isEmpty { items.append(URLQueryItem(name: "fld" + field.name, value: value)) }
        }
        if let returnURL { items.append(URLQueryItem(name: "x-success", value: returnURL)) }
        var components = URLComponents()
        components.scheme = "anki"
        components.host = "x-callback-url"
        components.path = "/addnote"
        components.queryItems = items
        // URLComponents leaves "+" and "&"-like characters that AnkiMobile would misread: encode strictly.
        components.percentEncodedQuery = items.map { item in
            "\(item.name)=\((item.value ?? "").addingPercentEncoding(withAllowedCharacters: strict) ?? "")"
        }.joined(separator: "&")
        return components.url
    }

    private static let strict = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
