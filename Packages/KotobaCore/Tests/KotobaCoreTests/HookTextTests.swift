import XCTest
@testable import KotobaCore

final class HookTextTests: XCTestCase {
    func testMessageIsPlainTextOrJSONSentence() {
        XCTAssertEqual(HookText.message("「おはよう」"), "「おはよう」")
        XCTAssertEqual(HookText.message(#"{"sentence":"天気がいい","id":3}"#), "天気がいい")
        // JSON without a sentence is shown as it came.
        XCTAssertEqual(HookText.message(#"{"text":"x"}"#), #"{"text":"x"}"#)
        XCTAssertEqual(HookText.message("{壊れた"), "{壊れた")
    }

    func testMessageWithHistoryPosition() {
        let m = HookText.parse(#"{"sentence":"三行目","id":3,"session":"00ab"}"#)
        XCTAssertEqual(m.text, "三行目")
        XCTAssertEqual(m.id, 3)
        XCTAssertEqual(m.session, "00ab")
        XCTAssertNil(HookText.parse("ただの行").id)
    }

    func testJoinsLinesOfOneTextBox() {
        var rules = HookText.Rules()
        XCTAssertEqual(HookText.clean("今日は\r\n 天気が\nいい ", rules: rules), "今日は天気がいい")
        rules.joinLines = false
        XCTAssertEqual(HookText.clean("今日は\n天気", rules: rules), "今日は\n天気")
    }

    func testRepeatedCharacters() {
        XCTAssertEqual(HookText.collapseRepeatedCharacters("ここんんににちちはは"), "こんにちは")
        XCTAssertEqual(HookText.collapseRepeatedCharacters("こここんんんににに"), "こんに")
        // Ordinary lines with a doubled letter stay.
        XCTAssertEqual(HookText.collapseRepeatedCharacters("ああ、そうか"), "ああ、そうか")
        XCTAssertEqual(HookText.collapseRepeatedCharacters("ーーーー"), "ーーーー")
        XCTAssertEqual(HookText.collapseRepeatedCharacters("ええっ"), "ええっ")
    }

    func testRepeatedLine() {
        XCTAssertEqual(HookText.collapseRepeatedLine("今日はいい天気だ。今日はいい天気だ。"), "今日はいい天気だ。")
        XCTAssertEqual(HookText.collapseRepeatedLine("はいはい"), "はいはい")
        XCTAssertEqual(HookText.collapseRepeatedLine("ちょっとちょっと"), "ちょっとちょっと")
    }

    func testBracketReadings() {
        XCTAssertEqual(HookText.dropBracketReadings("漢字《かんじ》を書く"), "漢字を書く")
        XCTAssertEqual(HookText.dropBracketReadings("青空｜文庫《ぶんこ》だ"), "青空文庫だ")
        XCTAssertEqual(HookText.dropBracketReadings("今日(きょう)は晴（は）れ"), "今日は晴れ")
        // Not readings: after kana, or not kana inside.
        XCTAssertEqual(HookText.dropBracketReadings("そうだね(笑)"), "そうだね(笑)")
        XCTAssertEqual(HookText.dropBracketReadings("(はい)と言った"), "(はい)と言った")
        XCTAssertEqual(HookText.dropBracketReadings("田中(28)"), "田中(28)")
        // An older ｜ is not touched by a later reading.
        XCTAssertEqual(HookText.dropBracketReadings("A｜B 漢字《かんじ》"), "A｜B 漢字")
    }

    func testInlineFurigana() {
        let dictionary: [String: [String]] = [
            "天気": ["てんき"], "今日": ["きょう", "こんにち"], "日": ["ひ", "にち"],
            "日にち": ["ひにち"], "間": ["ま", "あいだ"], "日本": ["にほん", "ニッポン"],
        ]
        func clean(_ s: String) -> String { HookText.dropInlineFurigana(s) { dictionary[$0] ?? [] } }
        XCTAssertEqual(clean("今日きょうは天気てんきがいい"), "今日は天気がいい")
        XCTAssertEqual(clean("日本にっぽん"), "日本")
        // Real words and one-kana readings stay.
        XCTAssertEqual(clean("日にちを決める"), "日にちを決める")
        XCTAssertEqual(clean("この間まで"), "この間まで")
        XCTAssertEqual(clean("天気がいい"), "天気がいい")
    }

    func testCustomReplacementsAndBadRegex() {
        var rules = HookText.Rules()
        rules.replacements = [.init(find: "^【[^】]*】"), .init(find: "(", replace: "x"), .init(find: "だ", replace: "です", enabled: false)]
        XCTAssertEqual(HookText.clean("【美咲】そうだ", rules: rules), "そうだ")
    }

    func testOldSettingsKeepDefaults() throws {
        let rules = try JSONDecoder().decode(HookText.Rules.self, from: Data(#"{"joinLines":false}"#.utf8))
        XCTAssertFalse(rules.joinLines)
        XCTAssertTrue(rules.dropBracketReadings)
    }

    func testMiniHTTP() {
        let body = "天気"
        let raw = "POST /text HTTP/1.1\r\nHost: x\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        XCTAssertEqual(MiniHTTP.parse(data.prefix(10)), .needMore)
        XCTAssertEqual(MiniHTTP.parse(data.dropLast(2)), .needMore)
        guard case .done(let request) = MiniHTTP.parse(data) else { return XCTFail() }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/text")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "天気")
        XCTAssertEqual(MiniHTTP.parse(Data("GET / HTTP/1.1\r\n\r\n".utf8)), .done(.init(method: "GET", path: "/", body: Data())))
        XCTAssertEqual(MiniHTTP.parse(Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)), .bad)
    }
}
