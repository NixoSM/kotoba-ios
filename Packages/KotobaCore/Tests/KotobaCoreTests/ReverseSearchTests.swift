import XCTest
@testable import KotobaCore

final class ReverseSearchTests: XCTestCase {
    func testRomaji() {
        XCTAssertEqual(Romaji.toHiragana("taberu"), "たべる")
        XCTAssertEqual(Romaji.toHiragana("konnichiwa"), "こんにちわ")
        XCTAssertEqual(Romaji.toHiragana("konnnichiwa"), "こんにちわ")
        XCTAssertEqual(Romaji.toHiragana("kitte"), "きって")
        XCTAssertEqual(Romaji.toHiragana("shinbun"), "しんぶん")
        XCTAssertEqual(Romaji.toHiragana("kyou"), "きょう")
        XCTAssertEqual(Romaji.toHiragana("matcha"), "まっちゃ")
        XCTAssertEqual(Romaji.toHiragana("hon'ya"), "ほんや")
        XCTAssertNil(Romaji.toHiragana("ciao"))
        XCTAssertNil(Romaji.toHiragana("attack"))
    }

    func testNormalize() {
        XCTAssertEqual(ReverseSearch.normalize("1 (攻めること)Assalto [-chi]"), "assalto")
        XCTAssertEqual(ReverseSearch.normalize("attaccare qlcu."), "attaccare")
        XCTAssertEqual(ReverseSearch.normalize("Città"), "citta")
    }

    func testScoringPrefersExactMeaning() {
        let exact = ReverseSearch.score(query: "attack", indexText: "attack\nassault\nraid")
        let inPhrase = ReverseSearch.score(query: "attack", indexText: "heart attack")
        let notAMatch = ReverseSearch.score(query: "attack", indexText: "attacker")
        XCTAssertEqual(exact, 100)
        XCTAssertGreaterThan(exact, inPhrase)
        XCTAssertGreaterThan(inPhrase, 0)
        XCTAssertEqual(notAMatch, 0)
        XCTAssertEqual(ReverseSearch.score(query: "eat", indexText: "to eat"), 100)
    }

    func testIndexTextSkipsLongExamples() {
        let json = Data(#"["assalto, attacco; offensiva", "Il nemico ci ha attaccato di notte mentre dormivamo tutti quanti nella caserma vicino al fiume"]"#.utf8)
        let text = ReverseSearch.indexText(fromGlossaryJSON: json)
        XCTAssertTrue(text.contains("attacco"))
        XCTAssertFalse(text.contains("caserma"))
    }

    func testFTSQuery() {
        XCTAssertEqual(ReverseSearch.ftsQuery(for: "Ciao"), "\"ciao\"*")
        XCTAssertEqual(ReverseSearch.ftsQuery(for: "to eat"), "\"to\" \"eat\"*")
        XCTAssertNil(ReverseSearch.ftsQuery(for: "!!"))
    }

    func testFrequencyValue() {
        XCTAssertEqual(ReverseSearch.frequencyValue(NSNumber(value: 12)), 12)
        XCTAssertEqual(ReverseSearch.frequencyValue(["value": 7, "displayValue": "7"] as [String: Any]), 7)
        XCTAssertEqual(ReverseSearch.frequencyValue(["reading": "x", "frequency": ["value": 3]] as [String: Any]), 3)
    }
}
