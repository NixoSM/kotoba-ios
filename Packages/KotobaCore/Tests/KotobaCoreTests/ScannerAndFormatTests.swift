import XCTest
@testable import KotobaCore

final class ScannerAndFormatTests: XCTestCase {
    private let bank = """
    [
      ["食べる", "たべる", "v1", "v1", 100, ["to eat"], 1, "P"],
      ["食べ物", "たべもの", "n", "", 90, [{"type": "structured-content", "content": "food"}], 2, ""],
      ["猫", "ねこ", "n", "", 50, "cat", 3, ""]
    ]
    """.data(using: .utf8)!

    func testParsesTermBank() throws {
        let entries = try YomitanParser.termBank(from: bank)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].rules, .v1)
        XCTAssertEqual(entries[0].termTags, ["P"])
        // A bare string glossary is normalised into an array.
        let glossary = try JSONSerialization.jsonObject(with: entries[2].glossaryJSON) as? [String]
        XCTAssertEqual(glossary, ["cat"])
    }

    func testParsesIndex() throws {
        let json = #"{"title":"JMdict","revision":"2025-01","format":3,"sequenced":true}"#.data(using: .utf8)!
        let index = try YomitanParser.index(from: json)
        XCTAssertEqual(index.title, "JMdict")
        XCTAssertEqual(index.formatVersion, 3)
    }

    func testScannerPrefersLongestMatch() throws {
        let source = MemoryTermSource(try YomitanParser.termBank(from: bank))
        let scanner = TextScanner()
        XCTAssertEqual(scanner.scan("食べ物が好き", in: source).first?.entry.expression, "食べ物")
        let eaten = scanner.scan("食べなかったよ", in: source)
        XCTAssertEqual(eaten.first?.entry.expression, "食べる")
        XCTAssertEqual(eaten.first?.matchedText, "食べなかった")
    }

    func testScannerRejectsWrongPartOfSpeech() throws {
        // 猫 is a noun, so "猫た" must not be read as a past tense of it.
        let source = MemoryTermSource(try YomitanParser.termBank(from: bank))
        let hits = TextScanner().scan("猫た", in: source)
        XCTAssertEqual(hits.first?.matchedText, "猫")
    }

    func testKatakanaInputFindsHiraganaReading() throws {
        let source = MemoryTermSource(try YomitanParser.termBank(from: bank))
        XCTAssertEqual(TextScanner().scan("ネコ", in: source).first?.entry.expression, "猫")
    }
}
