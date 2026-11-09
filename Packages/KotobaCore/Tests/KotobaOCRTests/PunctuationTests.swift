import XCTest
@testable import KotobaOCR

/// Vertical punctuation the recognizer gets wrong, fixed from context.
final class PunctuationTests: XCTestCase {
    private func tidy(_ text: String) -> String {
        String(VerticalOCR.tidy(text.enumerated().map { ($0.offset, $0.element) }).map(\.char))
    }

    func testBracketsReadAsDashes() {
        XCTAssertEqual(tidy("微笑んだ。→また来たの？」"), "微笑んだ。「また来たの？」")
        XCTAssertEqual(tidy("微笑んだ．－また来たの？ー"), "微笑んだ。「また来たの？」")
        XCTAssertEqual(tidy("-ねえ、この本"), "「ねえ、この本")
        // The quote began in the column before.
        XCTAssertEqual(tidy("1645ーという謎の"), "1645」という謎の")
    }

    func testWrongBracket() {
        XCTAssertEqual(tidy("「ねえ、読んだ？「彼女は"), "「ねえ、読んだ？」彼女は")
        XCTAssertEqual(tidy("」ねえ、読んだ？」彼女は"), "「ねえ、読んだ？」彼女は")
        XCTAssertEqual(tidy("微笑んだ。」また来たの？」"), "微笑んだ。「また来たの？」")
    }

    func testPeriods() {
        XCTAssertEqual(String(VerticalOCR.tidy([(0, "た"), (1, "."), (1, "."), (2, "宝")]).map(\.char)), "た。宝")
        XCTAssertEqual(tidy("数値は1.5です"), "数値は1.5です")
    }

    func testRealTextIsLeftAlone() {
        for text in ["コーヒーを飲んだ――そして", "ーを飲む。", "た」と彼は言った。", "た」「え」", "すごーい", "頷いた。外では雨が"] {
            XCTAssertEqual(tidy(text), text)
        }
    }
}
