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

    func testUninflectedWordIsKept() {
        XCTAssertEqual(d.deinflect("猫").first?.term, "猫")
        XCTAssertEqual(d.deinflect("猫").first?.wordClass, [])
    }
}
