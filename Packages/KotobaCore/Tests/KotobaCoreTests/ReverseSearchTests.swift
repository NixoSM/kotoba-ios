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

    func testOlderHepburnSpellings() {
        XCTAssertEqual(Romaji.toHiragana("shimbun"), "しんぶん")
        XCTAssertEqual(Romaji.toHiragana("sampo"), "さんぽ")
        XCTAssertEqual(Romaji.toHiragana("gemmai"), "げんまい")
        XCTAssertEqual(Romaji.toHiragana("tempura"), "てんぷら")
        // m before a vowel is still ま-row.
        XCTAssertEqual(Romaji.toHiragana("mame"), "まめ")
    }

    /// A macron says "long" but not how the kana spell it, so every spelling is offered.
    func testLongVowelsWithMacrons() {
        XCTAssertEqual(Romaji.readings("taberu"), ["たべる"])
        XCTAssertEqual(Romaji.readings("ciao"), [])
        XCTAssertTrue(Romaji.readings("tōkyō").contains("とうきょう"))
        XCTAssertTrue(Romaji.readings("Ōsaka").contains("おおさか"))
        XCTAssertTrue(Romaji.readings("kōhī").contains("こーひー"))
        XCTAssertTrue(Romaji.readings("kyûshû").contains("きゅうしゅう"))
        XCTAssertTrue(Romaji.readings("sensē").contains("せんせい"))
        // The same letters typed as "o" + a combining macron.
        XCTAssertTrue(Romaji.readings("to\u{304}kyo\u{304}").contains("とうきょう"))
        XCTAssertEqual(Romaji.readings("tōkyō").first, "とうきょう")
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

    /// Names from a dictionary file go into the page as attribute and CSS
    /// property names: one with a space or "=" in it would add an attribute
    /// of its own, such as a script to run on tap.
    func testNamesFromTheDictionaryCannotAddAttributes() {
        let json = #"[{"type":"structured-content","content":{"tag":"span","data":{"x onclick=alert(1) y":"1","class":"ok","fooBar":"2"},"style":{"color;background:url(https://example.com/a)":"red","fontSize":"2em","background":"URL( 'https://example.com/b' )","color":"u\\72l(https://example.com/c)"},"content":"hi"}}]"#
        let html = GlossaryHTML.items(fromJSON: Data(json.utf8)).first ?? ""
        XCTAssertEqual(html, #"<span data-sc-class="ok" data-sc-foo-bar="2" style="font-size:2em">hi</span>"#)
    }

    func testStylesheetCannotLeaveItsStyleElementOrCallOut() {
        let scope = "[data-d=\"1\"]"
        // Closing the <style> element to start a script.
        let breakout = GlossaryHTML.scopedCSS(".a { color: red } </style><script>alert(1)</script><style> .b { color: blue }", scope: scope)
        XCTAssertFalse(breakout.contains("<"), breakout)
        XCTAssertTrue(breakout.contains("[data-d=\"1\"] .a{ color: red }"), breakout)
        // Fetching from the network, spelled four ways; the harmless rules stay.
        let remote = """
        @import url(https://example.com/x.css);
        .keep { color: red }
        .a { background: url(https://example.com/a.png) }
        .b { background: URL( "https://example.com/b.png" ) }
        .c { background: u\\72l(https://example.com/c.png) }
        .d { background: -webkit-image-set("https://example.com/d.png" 1x) }
        .icon { background: url("data:image/png;base64,AAAA") }
        .quote::before { content: "\\201C" }
        """
        let css = GlossaryHTML.scopedCSS(remote, scope: scope)
        XCTAssertFalse(css.contains("example.com"), css)
        XCTAssertTrue(css.contains("[data-d=\"1\"] .keep{ color: red }"), css)
        XCTAssertTrue(css.contains("data:image/png;base64,AAAA"), css)
        XCTAssertTrue(css.contains(#"content: "\201C""#), css)
    }

    func testScopedCSS() {
        let css = "/* c */ .a, span[data-sc-x] { color: red } @media (max-width: 10px) { .b { margin: 0 } }"
        XCTAssertEqual(GlossaryHTML.scopedCSS(css, scope: "[data-d=\"1\"]"),
                       "[data-d=\"1\"] .a,[data-d=\"1\"] span[data-sc-x]{ color: red }@media (max-width: 10px){[data-d=\"1\"] .b{ margin: 0 }}")
    }
}
