#if canImport(SQLite3) || canImport(CSQLite3)
import Foundation
import XCTest
import ZIPFoundation
@testable import KotobaCore

/// Times the dictionary engine on a made-up dictionary the size of a small
/// JMdict: import, look-ups while reading, and reverse (meaning) search.
/// Prints `BENCH` lines for the CI log; the asserts only catch a broken engine.
/// Numbers come from a GitHub macOS runner, not an iPhone: compare them with
/// each other, not with what the phone does.
final class SpeedBenchTests: XCTestCase {
    private func say(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static let kanji = Array("日本語学校先生時間食飲行来見聞読書話言思知出入上下大小中長高新古多少早遅近遠明暗強弱重軽")
    private static let kana = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわん")

    /// 0 → "qa", 1 → "qb"…: a made-up word unique to one entry.
    static func letters(_ n: Int) -> String {
        var n = n, out = "q"
        repeat { out.append(Character(UnicodeScalar(97 + n % 26)!)); n /= 26 } while n > 0
        return out
    }

    /// A deterministic generator, so every run builds the same dictionary.
    private struct Rand {
        var state: UInt64
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
    }

    /// Term banks of `count` entries: a third are ichidan verbs, the rest
    /// nouns, with structured-content glossaries like JMdict's.
    private func makeDictionary(count: Int) throws -> (url: URL, words: [String]) {
        var r = Rand(state: 42)
        var words: [String] = []
        var banks: [String: String] = [:]
        var rows: [String] = []
        for i in 0..<count {
            let verb = i % 3 == 0
            var expression = ""
            for _ in 0..<(1 + r.next(3)) { expression.append(Self.kanji[r.next(Self.kanji.count)]) }
            var reading = ""
            for _ in 0..<(2 + r.next(4)) { reading.append(Self.kana[r.next(Self.kana.count)]) }
            if verb { expression += "べる"; reading += "べる" }
            words.append(expression)
            let gloss = #"[{"type":"structured-content","content":[{"tag":"ul","data":{"content":"glossary"},"content":[{"tag":"li","content":"meaning \#(Self.letters(i)) word"},{"tag":"li","content":"sense \#(r.next(1000)) thing"}]}]}]"#
            rows.append(#"["\#(expression)","\#(reading)","\#(verb ? "v1" : "n")","\#(verb ? "v1" : "")",\#(r.next(100)),\#(gloss),\#(i),""]"#)
            if rows.count == 10_000 || i == count - 1 {
                banks["term_bank_\(banks.count + 1).json"] = "[" + rows.joined(separator: ",") + "]"
                rows = []
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        banks["index.json"] = #"{"title":"Bench","revision":"1","format":3}"#
        for (path, text) in banks {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return (url, words)
    }

    private func time(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    func testEngineSpeed() throws {
        let terms = 60_000
        let (zip, words) = try makeDictionary(count: terms)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: zip) }
        let path = folder.appendingPathComponent("bench.sqlite").path

        var store = try DictionaryStore(path: path)
        var installed: InstalledDictionary?
        let importMs = try time { installed = try YomitanImporter.importDictionary(at: zip, into: store) }
        XCTAssertEqual(installed?.termCount, terms)
        say(String(format: "BENCH engine import %d terms: %.0f ms (%.1f µs/term)", terms, importMs, importMs * 1000 / Double(terms)))

        // Reopen, as the app does at launch.
        store = try DictionaryStore(path: path)
        try store.buildMissingKanaIndexes()
        var openMs = 0.0
        openMs = try time { store = try DictionaryStore(path: path) }
        say(String(format: "BENCH engine open database: %.1f ms", openMs))

        // Sentences like the ones you tap while reading: inflected verbs between nouns.
        var r = Rand(state: 7)
        var sentences: [String] = []
        for _ in 0..<300 {
            var s = words[r.next(words.count)] + "を"
            let verb = words[3 * r.next(words.count / 3)]
            s += String(verb.dropLast()) + ["なかった", "ました", "て", "させられる", "たい"][r.next(5)]
            s += words[r.next(words.count)]
            sentences.append(s)
        }
        let scanner = TextScanner()
        var found = 0
        let scanMs = time { for s in sentences { found += scanner.scan(s, in: store).isEmpty ? 0 : 1 } }
        XCTAssertEqual(found, sentences.count)
        say(String(format: "BENCH engine scan (tap-to-look-up): %.2f ms per sentence", scanMs / Double(sentences.count)))

        let longestMs = time { for s in sentences { _ = scanner.longestMatch(s, in: store) } }
        say(String(format: "BENCH engine longest match (camera lens): %.2f ms per line", longestMs / Double(sentences.count)))

        var hits = 0
        let reverseMs = time { for i in 0..<100 { hits += store.reverseSearch(Self.letters(i * 37)).count } }
        XCTAssertGreaterThanOrEqual(hits, 100)
        say(String(format: "BENCH engine reverse search, rare word: %.2f ms per query", reverseMs / 100))
        let commonMs = time { for _ in 0..<10 { _ = store.reverseSearch("meaning") } }
        say(String(format: "BENCH engine reverse search, word in every definition (worst case): %.1f ms per query", commonMs / 10))

        // With a dictionary switched off, each candidate is checked against its dictionary first.
        let extra = try store.install(index: DictionaryIndex(title: "Off", revision: "1", format: 3)) { _ in }
        try store.setEnabled(false, dictionary: extra.id)
        let filteredMs = time { for _ in 0..<10 { _ = store.reverseSearch("meaning") } }
        say(String(format: "BENCH engine reverse search, worst case with one dictionary switched off: %.1f ms per query", filteredMs / 10))

        let size = ["", "-wal"].reduce(0) { total, suffix in
            total + ((try? FileManager.default.attributesOfItem(atPath: path + suffix)[.size] as? Int) ?? 0)
        }
        say(String(format: "BENCH engine database size: %.1f MB for %d terms", Double(size) / 1_048_576, terms))
    }
}
#endif
