import Foundation

/// Text that arrives from a texthooker (Textractor and friends) on the PC.
public enum HookText {
    /// The line inside one WebSocket message. Like texthooker-ui: a JSON object
    /// with a "sentence" field (TextractorSender, some LunaTranslator setups),
    /// otherwise the message is the line itself (kuroahna's textractor_websocket).
    public static func message(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sentence = object["sentence"] as? String {
            return sentence
        }
        return raw
    }

    /// A find → replace the person adds themselves (a regular expression).
    public struct Replacement: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id = UUID()
        public var find: String
        public var replace: String
        public var enabled = true

        public init(find: String, replace: String = "", enabled: Bool = true) {
            self.find = find
            self.replace = replace
            self.enabled = enabled
        }
    }

    /// Clean-up applied to every new line, in this order.
    public struct Rules: Codable, Equatable, Sendable {
        /// Line breaks inside one text box become nothing (Japanese has no spaces between words).
        public var joinLines = true
        /// 漢字《かんじ》, ｜漢字《かんじ》 and 漢字(かんじ): the reading in brackets goes.
        public var dropBracketReadings = true
        /// 今日きょうは → 今日は: a kanji word followed by its own reading. Needs the dictionary.
        public var dropInlineFurigana = false
        /// ここんんににちちはは → こんにちは (each character hooked twice or three times).
        public var collapseRepeatedCharacters = true
        /// こんにちはこんにちは → こんにちは (the whole line hooked twice).
        public var collapseRepeatedLine = true
        /// Your own find → replace rules, applied last.
        public var replacements: [Replacement] = []

        public init() {}

        public init(from decoder: Decoder) throws {
            // Settings saved by an older version lack newer keys: keep the defaults.
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Rules()
            joinLines = (try? c.decodeIfPresent(Bool.self, forKey: .joinLines)) ?? d.joinLines
            dropBracketReadings = (try? c.decodeIfPresent(Bool.self, forKey: .dropBracketReadings)) ?? d.dropBracketReadings
            dropInlineFurigana = (try? c.decodeIfPresent(Bool.self, forKey: .dropInlineFurigana)) ?? d.dropInlineFurigana
            collapseRepeatedCharacters = (try? c.decodeIfPresent(Bool.self, forKey: .collapseRepeatedCharacters)) ?? d.collapseRepeatedCharacters
            collapseRepeatedLine = (try? c.decodeIfPresent(Bool.self, forKey: .collapseRepeatedLine)) ?? d.collapseRepeatedLine
            replacements = (try? c.decodeIfPresent([Replacement].self, forKey: .replacements)) ?? []
        }
    }

    /// - Parameter readings: the hiragana readings of a dictionary word, empty when it isn't one.
    ///   Only used by `dropInlineFurigana`.
    public static func clean(_ text: String, rules: Rules, readings: (String) -> [String] = { _ in [] }) -> String {
        var t = text.replacingOccurrences(of: "\r\n", with: "\n")
        if rules.joinLines {
            t = t.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined()
        }
        if rules.collapseRepeatedCharacters { t = collapseRepeatedCharacters(t) }
        if rules.collapseRepeatedLine { t = collapseRepeatedLine(t) }
        if rules.dropBracketReadings { t = dropBracketReadings(t) }
        if rules.dropInlineFurigana { t = dropInlineFurigana(t, readings: readings) }
        for r in rules.replacements where r.enabled && !r.find.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: r.find) else { continue }
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: r.replace)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Each character exactly 2, 3 or 4 times in a row, all through the line.
    /// Strict on purpose: ああ or っっ in a normal line must survive.
    public static func collapseRepeatedCharacters(_ text: String) -> String {
        let chars = Array(text)
        guard chars.count >= 4 else { return text }
        for k in 2...4 where chars.count % k == 0 {
            var ok = true
            var out: [Character] = []
            out.reserveCapacity(chars.count / k)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                for j in 1..<k where chars[i + j] != c { ok = false; break }
                if !ok { break }
                out.append(c)
                i += k
            }
            // A line of one repeated character (ーーーー) is not a doubled line.
            if ok, Set(out).count > 1 { return String(out) }
        }
        return text
    }

    /// The whole line repeated: ABCABC → ABC. Only for lines of 6 characters
    /// or more, so はいはい and ちょっとちょっと stay as written.
    public static func collapseRepeatedLine(_ text: String) -> String {
        let chars = Array(text)
        let n = chars.count
        guard n >= 12 else { return text }
        for period in 6...(n / 2) where n % period == 0 {
            var same = true
            for i in period..<n where chars[i] != chars[i - period] { same = false; break }
            if same { return String(chars[0..<period]) }
        }
        return text
    }

    /// 《かんじ》 always goes (it only ever marks a reading); (かんじ) only after
    /// kanji and only when it holds nothing but kana, so (笑) and (はい) at the start stay.
    public static func dropBracketReadings(_ text: String) -> String {
        let chars = Array(text)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        // Where the text after the last reading removed starts: a ｜ before it belongs to an older word.
        var wordFloor = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let closer: Character? = c == "《" ? "》" : (c == "(" || c == "（") ? (c == "(" ? ")" : "）") : nil
            if let closer, let end = chars[(i + 1)...].firstIndex(of: closer) {
                let inner = chars[(i + 1)..<end]
                let isReading = !inner.isEmpty && inner.allSatisfy(isKana)
                let afterKanji = out.last.map(isKanji) ?? false
                if c == "《" || (isReading && afterKanji) {
                    // Aozora style ｜ marks where the word starts: drop it too.
                    let inWord: (Character) -> Bool = c == "《"
                        ? { !$0.isWhitespace && !$0.isPunctuation }
                        : { HookText.isKanji($0) }
                    if let bar = out[wordFloor...].lastIndex(where: { $0 == "｜" || $0 == "|" }),
                       out[(bar + 1)...].allSatisfy(inWord), out.count - bar <= 21 {
                        out.remove(at: bar)
                    }
                    wordFloor = out.count
                    i = end + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    /// 天気てんきがいい → 天気がいい: after a run of kanji, kana that spell the
    /// run's own reading are a hooked furigana line. Kept when kanji + kana is
    /// itself a word (日にち), so real text survives. One-kana readings are left
    /// alone: この間まで would lose its まで to 間 (ま).
    public static func dropInlineFurigana(_ text: String, readings: (String) -> [String]) -> String {
        let chars = Array(text)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            guard isKanji(chars[i]) else {
                out.append(chars[i])
                i += 1
                continue
            }
            var end = i
            while end < chars.count, isKanji(chars[end]) { end += 1 }
            let kanji = String(chars[i..<end])
            out.append(contentsOf: chars[i..<end])
            i = end
            var kanaEnd = i
            while kanaEnd < chars.count, isKana(chars[kanaEnd]) { kanaEnd += 1 }
            guard kanaEnd > i else { continue }
            let kana = Kana.toHiragana(String(chars[i..<kanaEnd]))
            let candidates = Set(readings(kanji).map(Kana.toHiragana)).filter { $0.count >= 2 && kana.hasPrefix($0) }
            for reading in candidates.sorted(by: { $0.count > $1.count }) {
                // 日にち, 何なに…: a word written that way, not a reading.
                let joined = kanji + String(chars[i..<(i + reading.count)])
                if !readings(joined).isEmpty { continue }
                i += reading.count
                break
            }
        }
        return String(out)
    }

    static func isKana(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x3041...0x3096).contains(v) || (0x30A1...0x30FA).contains(v) || v == 0x30FC
    }

    static func isKanji(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || v == 0x3005
    }
}

/// The smallest HTTP the phone needs to take text from a script or a browser on the PC.
public enum MiniHTTP {
    public struct Request: Equatable, Sendable {
        public var method: String
        public var path: String
        public var body: Data
    }

    public enum Parse: Equatable {
        case needMore
        case done(Request)
        case bad
    }

    /// Parses what has arrived so far; `.needMore` until headers and body are complete.
    public static func parse(_ data: Data, limit: Int = 256 * 1024) -> Parse {
        guard data.count <= limit + 16 * 1024 else { return .bad }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16 * 1024 ? .bad : .needMore
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .bad }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return .bad }
        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                guard let n = Int(parts[1].trimmingCharacters(in: .whitespaces)), n >= 0, n <= limit else { return .bad }
                length = n
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return .needMore }
        return .done(Request(method: String(first[0]).uppercased(), path: String(first[1]),
                             body: Data(data[bodyStart..<(bodyStart + length)])))
    }

    public static func response(status: String, type: String = "text/plain; charset=utf-8", body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
