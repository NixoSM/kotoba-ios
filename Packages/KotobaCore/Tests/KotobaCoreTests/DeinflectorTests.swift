import XCTest
@testable import KotobaCore

final class DeinflectorTests: XCTestCase {
    let d = Deinflector()

    private func assertDeinflects(_ text: String, to base: String, as cls: WordClass,
                                  reasons: [Reason]? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let hits = d.deinflect(text).filter { $0.term == base && $0.wordClass.contains(cls) }
        XCTAssertFalse(hits.isEmpty, "\(text) should deinflect to \(base)", file: file, line: line)
        if let reasons {
            XCTAssertTrue(hits.contains { $0.reasons == reasons },
                          "\(text): got \(hits.map(\.reasons)), expected \(reasons)", file: file, line: line)
        }
    }

    func testIchidan() {
        assertDeinflects("食べなかった", to: "食べる", as: .v1, reasons: [.negative, .past])
        assertDeinflects("食べました", to: "食べる", as: .v1, reasons: [.polite, .politePast])
        assertDeinflects("食べている", to: "食べる", as: .v1, reasons: [.te, .progressive])
        assertDeinflects("食べられる", to: "食べる", as: .v1)
        assertDeinflects("食べたかった", to: "食べる", as: .v1, reasons: [.want, .past])
    }

    func testGodan() {
        assertDeinflects("書いた", to: "書く", as: .v5, reasons: [.past])
        assertDeinflects("読んでしまった", to: "読む", as: .v5, reasons: [.te, .completion, .past])
        assertDeinflects("話さない", to: "話す", as: .v5, reasons: [.negative])
        assertDeinflects("行った", to: "行く", as: .v5, reasons: [.past])
        assertDeinflects("待てば", to: "待つ", as: .v5, reasons: [.conditional])
        assertDeinflects("飲みませんでした", to: "飲む", as: .v5, reasons: [.polite, .politeNegativePast])
    }

    func testIrregular() {
        assertDeinflects("勉強しなかった", to: "勉強する", as: .vs, reasons: [.negative, .past])
        assertDeinflects("来なかった", to: "来る", as: .vk, reasons: [.negative, .past])
        assertDeinflects("こられる", to: "くる", as: .vk)
    }

    func testAdjective() {
        assertDeinflects("高くなかった", to: "高い", as: .adjI, reasons: [.negative, .past])
        assertDeinflects("寒ければ", to: "寒い", as: .adjI, reasons: [.conditional])
    }

    /// The stem (連用形) of an ichidan verb is the verb without る. Without a
    /// rule for it 食べながら, 見やすい and たべ found only the first kanji, or nothing.
    func testIchidanStemAndItsEndings() {
        assertDeinflects("食べ", to: "食べる", as: .v1, reasons: [.stem])
        assertDeinflects("たべ", to: "たべる", as: .v1, reasons: [.stem])
        assertDeinflects("見", to: "見る", as: .v1, reasons: [.stem])
        assertDeinflects("食べながら", to: "食べる", as: .v1, reasons: [.whileDoing])
        assertDeinflects("見ながら", to: "見る", as: .v1, reasons: [.whileDoing])
        assertDeinflects("みながら", to: "みる", as: .v1, reasons: [.whileDoing])
        assertDeinflects("起きそう", to: "起きる", as: .v1, reasons: [.seemingness])
        assertDeinflects("出やすい", to: "出る", as: .v1, reasons: [.easyTo])
        assertDeinflects("食べにくかった", to: "食べる", as: .v1, reasons: [.hardTo, .past])
        assertDeinflects("食べ方", to: "食べる", as: .v1, reasons: [.wayOf])
        assertDeinflects("食べなさい", to: "食べる", as: .v1, reasons: [.politeImperative])
        assertDeinflects("食べすぎた", to: "食べる", as: .v1, reasons: [.excess, .past])
        assertDeinflects("食べすぎ", to: "食べる", as: .v1, reasons: [.excess, .stem])
        assertDeinflects("食べたがっている", to: "食べる", as: .v1, reasons: [.showsWant, .te, .progressive])
    }

    func testGodanStemEndings() {
        assertDeinflects("書き", to: "書く", as: .v5, reasons: [.stem])
        assertDeinflects("書きながら", to: "書く", as: .v5, reasons: [.whileDoing])
        assertDeinflects("読みやすい", to: "読む", as: .v5, reasons: [.easyTo])
        assertDeinflects("分かりにくい", to: "分かる", as: .v5, reasons: [.hardTo])
        assertDeinflects("降りそう", to: "降る", as: .v5, reasons: [.seemingness])
        assertDeinflects("降りそう", to: "降りる", as: .v1, reasons: [.seemingness])
        assertDeinflects("書き方", to: "書く", as: .v5, reasons: [.wayOf])
        assertDeinflects("書きなさい", to: "書く", as: .v5, reasons: [.politeImperative])
        assertDeinflects("飲みすぎる", to: "飲む", as: .v5, reasons: [.excess])
        // A stem of a potential: 書けそう is "looks like (one) can write".
        assertDeinflects("書けそう", to: "書く", as: .v5, reasons: [.potential, .seemingness])
        assertDeinflects("しながら", to: "する", as: .vs, reasons: [.whileDoing])
        assertDeinflects("来ながら", to: "来る", as: .vk, reasons: [.whileDoing])
    }

    func testOlderAndSpokenNegatives() {
        assertDeinflects("書かぬ", to: "書く", as: .v5, reasons: [.nu])
        assertDeinflects("知らん", to: "知る", as: .v5, reasons: [.nu])
        assertDeinflects("食べん", to: "食べる", as: .v1, reasons: [.nu])
        assertDeinflects("書かねば", to: "書く", as: .v5, reasons: [.neba])
        assertDeinflects("せねば", to: "する", as: .vs, reasons: [.neba])
        assertDeinflects("行くまい", to: "行く", as: .v5, reasons: [.negativeVolitional])
        assertDeinflects("食べまい", to: "食べる", as: .v1, reasons: [.negativeVolitional])
        assertDeinflects("食べなくちゃ", to: "食べる", as: .v1, reasons: [.negative, .nakereba])
        // 書かされた: made to write. The short form of 書かせられた.
        assertDeinflects("書かされた", to: "書く", as: .v5, reasons: [.causative, .passive, .past])
    }

    /// One kana is not enough to call something a verb stem: に is a particle
    /// and ねん is 年, not 煮る and "does not sleep".
    func testShortKanaIsNotTakenForAStem() {
        XCTAssertFalse(d.deinflect("に").contains { $0.term == "にる" })
        XCTAssertFalse(d.deinflect("ねん").contains { $0.term == "ねる" })
        XCTAssertFalse(d.deinflect("いぬ").contains { $0.term == "いる" && $0.wordClass == .v1 })
        // With the kanji, or after an ending, there is no doubt.
        XCTAssertTrue(d.deinflect("寝ん").contains { $0.term == "寝る" })
        XCTAssertTrue(d.deinflect("煮ながら").contains { $0.term == "煮る" })
        // A stem must end the way stems do: 猫 + る is nothing to look up.
        XCTAssertFalse(d.deinflect("ねこ").contains { $0.term == "ねこる" })
    }

    func testUninflectedWordIsKept() {
        XCTAssertEqual(d.deinflect("猫").first?.term, "猫")
        XCTAssertEqual(d.deinflect("猫").first?.wordClass, [])
    }
}
