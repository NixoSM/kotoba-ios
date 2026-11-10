import XCTest
import KotobaCore
@testable import KotobaAppLogic

/// Writes the results page as the app builds it, once per theme, so that
/// tools/render_screenshots.js can photograph it. No iPhone and no Mac needed:
/// the page is HTML, and the same HTML is what the app shows.
///
///   KOTOBA_RENDER_OUT=out swift test --filter RenderTests
///   node tools/render_screenshots.js out
final class RenderTests: XCTestCase {
    func testWritePagesForScreenshots() throws {
        guard let folder = ProcessInfo.processInfo.environment["KOTOBA_RENDER_OUT"], !folder.isEmpty else {
            throw XCTSkip("Set KOTOBA_RENDER_OUT to a folder to write the pages.")
        }
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let store = try Fixtures.store()

        func write(_ name: String, query: String, suggest: Bool = false, _ change: (inout ResultsPage.Options) -> Void = { _ in }) throws {
            var options = ResultsPage.Options()
            options.canMine = true
            options.mined = ["猫|ねこ"]
            options.stylesheets = store.stylesheets()
            change(&options)
            let html = ResultsPage.html(outcome: Fixtures.search(query, in: store, suggest: suggest), query: query, options: options)
            try html.write(to: out.appendingPathComponent(name + ".html"), atomically: true, encoding: .utf8)
        }

        for theme in ThemePalette.all {
            try write("theme-\(theme.id)", query: "食べられなかった") { $0.appearance.theme = theme.id }
        }
        try write("starts-with", query: "しんぶ", suggest: true)
        try write("starts-with-after-word", query: "食べ", suggest: true)
        try write("meaning", query: "gatto")
        try write("in-anki", query: "猫")
        try write("compact", query: "食べる") { $0.appearance.layout = .compact }
        try write("pitch-graph", query: "食べる") { $0.appearance.pitchGraph = true }
        try write("large-type", query: "食べる") { $0.appearance.fontSize = 24 }
        // Last, so the pages above are as they are without a kanji dictionary.
        try Fixtures.install("Kanji", kanji: Fixtures.kanji, into: store)
        try write("kanji", query: "食べ物")
        try write("kanji-dark", query: "猫") { $0.appearance.theme = "sumi" }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasSuffix(".html") }.count, ThemePalette.all.count + 9)
    }
}
