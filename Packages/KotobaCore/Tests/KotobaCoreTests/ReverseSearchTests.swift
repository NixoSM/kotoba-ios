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
        XCTAssertEqual(ReverseSearch.ftsQuery(for: "to eat"), "\"eat\"*")
        XCTAssertEqual(ReverseSearch.ftsQuery(for: "il dado è tratto"), "\"dado\" \"tratto\"*")
        XCTAssertEqual(ReverseSearch.ftsQuery(for: "the"), "\"the\"*")
        XCTAssertEqual(ReverseSearch.score(query: "to run", indexText: "to run"), 100)
        XCTAssertNil(ReverseSearch.ftsQuery(for: "!!"))
    }

    func testSubentryInsideBilingualEntry() {
        let glossary = Data(#"["したて【仕立て】\n1 (衣服の)confezione\n◎仕立て代\n仕立て代を払う\npagare il confezionamento di un vestito\n仕立屋\n(人)sarto[-a]; (店)sartoria"]"#.utf8)
        XCTAssertEqual(ReverseSearch.subentry(matching: "sarto", glossaryJSON: glossary), "仕立屋")
        XCTAssertNil(ReverseSearch.subentry(matching: "confezione", glossaryJSON: glossary))
        let costume = Data(#"["いしょう【衣装】\nabiti, vestiti\n◎衣装係［方］\n〔劇・映・テ〕costumista [-i], vestiarista [-i]; (作製と管理)sarto [-a]"]"#.utf8)
        XCTAssertEqual(ReverseSearch.subentry(matching: "costumista", glossaryJSON: costume), "衣装係")
    }

    func testFrequencyValue() {
        XCTAssertEqual(ReverseSearch.frequencyValue(NSNumber(value: 12)), 12)
        XCTAssertEqual(ReverseSearch.frequencyValue(["value": 7, "displayValue": "7"] as [String: Any]), 7)
        XCTAssertEqual(ReverseSearch.frequencyValue(["reading": "x", "frequency": ["value": 3]] as [String: Any]), 3)
    }
}

final class GlossaryHTMLTests: XCTestCase {
    func testRendersStructureSafely() {
        let json = #"[{"type":"structured-content","content":[{"tag":"details","content":[{"tag":"summary","content":"7 examples"},{"tag":"div","data":{"content":"example"},"style":{"fontWeight":"bold"},"content":"<script>x</script>"}]}]}]"#
        let html = GlossaryHTML.items(fromJSON: Data(json.utf8)).first ?? ""
        XCTAssertTrue(html.hasPrefix("<details><summary>7 examples</summary>"))
        XCTAssertTrue(html.contains(#"data-sc-content="example""#))
        XCTAssertTrue(html.contains(#"style="font-weight:bold""#))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testInternalLinksBecomeSearches() {
        let json = #"[{"type":"structured-content","content":{"tag":"a","href":"?query=守備&wildcards=off","content":"守備"}}]"#
        let html = GlossaryHTML.items(fromJSON: Data(json.utf8)).first ?? ""
        XCTAssertTrue(html.contains("kotoba://search?q="), html)
    }

    func testScopedCSS() {
        let css = "/* c */ .a, span[data-sc-x] { color: red } @media (max-width: 10px) { .b { margin: 0 } }"
        XCTAssertEqual(GlossaryHTML.scopedCSS(css, scope: "[data-d=\"1\"]"),
                       "[data-d=\"1\"] .a,[data-d=\"1\"] span[data-sc-x]{ color: red }@media (max-width: 10px){[data-d=\"1\"] .b{ margin: 0 }}")
    }
}
