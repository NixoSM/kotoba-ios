import XCTest
import KotobaCore
@testable import KotobaAppLogic

final class ResultsPageTests: XCTestCase {
    private func page(_ query: String, suggest: Bool = false, options: ResultsPage.Options = ResultsPage.Options()) throws -> String {
        let store = try Fixtures.store()
        return ResultsPage.html(outcome: Fixtures.search(query, in: store, suggest: suggest), query: query, options: options)
    }

    /// The results between the two marks, as the app swaps them in place.
    private func split(_ html: String) throws -> (shell: String, body: String) {
        let open = try XCTUnwrap(html.range(of: ResultsPage.bodyOpen))
        let close = try XCTUnwrap(html.range(of: ResultsPage.bodyClose, options: .backwards))
        return (String(html[..<open.upperBound]) + String(html[close.lowerBound...]), String(html[open.upperBound..<close.lowerBound]))
    }

    func testEntryHasItsParts() throws {
        var options = ResultsPage.Options()
        options.canMine = true
        let html = try page("食べなかった", options: options)
        XCTAssertTrue(html.contains(#"<article class="entry">"#))
        XCTAssertTrue(html.contains("negativo › passato"), "the grammar steps, in Italian by default")
        XCTAssertTrue(html.contains(#"class="btn audio" href="kotoba://audio?e="#))
        XCTAssertTrue(html.contains(#"class="btn mine" href="kotoba://mine?s=direct&i=0""#))
        XCTAssertTrue(html.contains(#"<div class="dict-name">Dizionario italiano</div>"#))
        XCTAssertTrue(html.contains(#"<span class="freq-value">400</span>"#))
    }

    /// Short glosses share a line, and each one moves to the next line whole.
    func testShortGlossesAreUnits() throws {
        let html = try page("食べる")
        XCTAssertTrue(html.contains(#"<div class="gloss inline"><span class="g">mangiare</span> <span class="g">vivere di (uno stipendio)</span></div>"#), html)
    }

    func testTickOnlyForWordsAlreadyInAnki() throws {
        var options = ResultsPage.Options()
        options.canMine = true
        XCTAssertFalse(try page("猫", options: options).contains("btn mine done"))
        options.mined = ["猫|ねこ"]
        XCTAssertTrue(try page("猫", options: options).contains(#"class="btn mine done""#))
        // Without an Anki note set up there is no button at all.
        XCTAssertFalse(try page("猫").contains("btn mine"))
    }

    func testWordsThatStartWithAreLinksToSearches() throws {
        let html = try page("しんぶ", suggest: true)
        XCTAssertTrue(html.contains("Parole che iniziano con «しんぶ»"))
        XCTAssertTrue(html.contains(#"<a class="start" href="kotoba://search?q=%E6%96%B0%E8%81%9E"><span class="start-word" lang="ja">新聞</span><span class="start-reading" lang="ja">しんぶん</span><span class="start-gloss">giornale</span></a>"#), html)
        // The list comes before 芯, which only covers しん.
        let list = try XCTUnwrap(html.range(of: "class=\"starts\""))
        let entry = try XCTUnwrap(html.range(of: "class=\"entry\""))
        XCTAssertLessThan(list.lowerBound, entry.lowerBound)
        XCTAssertFalse(try page("しんぶ").contains("class=\"starts\""))
    }

    /// Nothing a dictionary file says can become markup or a script of its own.
    func testDictionaryContentCannotRunAnything() throws {
        let store = try Fixtures.store()
        try Fixtures.install("</style><script>alert(2)</script>", terms: #"[["<img src=x onerror=alert(3)>","\"><b>","n","",1,["<script>alert(4)</script>"],1,""]]"#,
                             styles: ".a{color:red}</style><script>alert(5)</script>", into: store)
        var options = ResultsPage.Options()
        options.stylesheets = store.stylesheets()
        let html = ResultsPage.html(outcome: Fixtures.search("食べ物", in: store), query: "食べ物", options: options)
            + ResultsPage.html(outcome: Fixtures.search("alert", in: store), query: "alert", options: options)
        XCTAssertFalse(html.contains("<script>alert"), "no script from a dictionary")
        XCTAssertFalse(html.contains("onclick=alert"), "no attribute from a data name")
        XCTAssertFalse(html.contains("<img src=x"))
        XCTAssertFalse(html.contains("</style><script>"))
        // The page's own script is the only one, and it carries the launch's mark.
        XCTAssertEqual(html.components(separatedBy: "<script").count - 1, 2)
        XCTAssertEqual(html.components(separatedBy: "<script nonce=\"\(ResultsPage.scriptNonce)\">").count - 1, 2)
    }

    /// Your own CSS stays inside its <style> element whatever it holds.
    func testYourOwnCSSCannotSpillOntoThePage() throws {
        var options = ResultsPage.Options()
        options.appearance.customCSS = #".gloss::after { content: "</style><h1>fuori</h1>"; } .entry { color: red; }"#
        let html = try page("食べる", options: options)
        XCTAssertFalse(html.contains("</style><h1>"))
        XCTAssertTrue(html.contains(#"content: "<\/style><h1>fuori<\/h1>";"#), "the same text to CSS")
        XCTAssertTrue(html.contains(".entry { color: red; }"))
        XCTAssertEqual(ResultsPage.ownCSS("a > b { margin: 0 } @media (width < 600px) { a { top: 0 } }"),
                       "a > b { margin: 0 } @media (width < 600px) { a { top: 0 } }", "ordinary CSS is left as typed")
    }

    func testPageLoadsNothingFromTheNetwork() throws {
        let html = try page("猫")
        let policy = ResultsPage.contentSecurityPolicy
        XCTAssertTrue(html.contains(#"<meta http-equiv="Content-Security-Policy" content="\#(policy)">"#))
        XCTAssertTrue(policy.contains("default-src 'none'"))
        XCTAssertTrue(policy.contains("script-src 'nonce-\(ResultsPage.scriptNonce)'"))
        XCTAssertFalse(policy.contains("http"))
        let scripts = try XCTUnwrap(policy.components(separatedBy: ";").first { $0.contains("script-src") })
        XCTAssertFalse(scripts.contains("unsafe-inline"), "inline scripts are not allowed, only inline styles")
        XCTAssertGreaterThanOrEqual(ResultsPage.scriptNonce.count, 32)
    }

    /// A new search must change only the part between the marks: the app
    /// then swaps the results in place instead of loading the fonts again.
    func testOnlyTheResultsChangeBetweenSearches() throws {
        let cat = try split(try page("猫"))
        let eat = try split(try page("食べる"))
        XCTAssertEqual(cat.shell, eat.shell)
        XCTAssertNotEqual(cat.body, eat.body)
        XCTAssertTrue(cat.body.contains("猫"))
        // A different theme is a different page.
        var options = ResultsPage.Options()
        options.appearance.theme = "yuki"
        XCTAssertNotEqual(try split(try page("猫", options: options)).shell, cat.shell)
    }

    func testButtonsAreLargeEnoughToTap() throws {
        let html = try page("猫")
        XCTAssertTrue(html.contains(".btn { width:44px; height:44px;"))
    }

    func testCompactLayoutAndClosedDictionaries() throws {
        var options = ResultsPage.Options()
        options.appearance.layout = .compact
        options.collapsed = ["JMdict (English)"]
        let html = try page("猫", options: options)
        XCTAssertTrue(html.contains(#"<html lang="it" class="compact">"#))
        XCTAssertTrue(html.contains(#"<ol class="defs">"#))
        XCTAssertTrue(html.contains(#"<details class="dict closed""#))
        XCTAssertTrue(html.contains(#"<summary class="dict-name">JMdict (English)</summary>"#))
    }
}
