import XCTest
@testable import KotobaCore

final class WordAimTests: XCTestCase {
    private let source: MemoryTermSource = {
        let bank = """
        [
          ["彼女", "かのじょ", "n", "", 100, ["she"], 1, ""],
          ["天気", "てんき", "n", "", 100, ["weather"], 2, ""],
          ["人格", "じんかく", "n", "", 100, ["personality"], 3, ""],
          ["は", "は", "prt", "", 100, ["topic"], 4, ""],
          ["が", "が", "prt", "", 100, ["subject"], 5, ""],
          ["に", "に", "prt", "", 100, ["to"], 6, ""],
          ["たち", "たち", "suf", "", 100, ["plural"], 7, ""],
          ["によって", "によって", "exp", "", 100, ["by"], 8, ""],
          ["入れ替わる", "いれかわる", "v5", "v5", 100, ["to switch"], 9, ""],
          ["人", "ひと", "n", "", 100, ["person"], 10, ""],
          ["格", "かく", "n", "", 100, ["status"], 11, ""],
          ["できる", "できる", "v1", "v1", 100, ["can"], 12, ""],
          ["ことができる", "ことができる", "exp", "v1", 100, ["can"], 13, ""]
        ]
        """.data(using: .utf8)!
        return MemoryTermSource(try! YomitanParser.termBank(from: bank))
    }()

    private func pick(_ text: String, at position: Double, favoring: String? = nil) -> String? {
        let scanner = TextScanner()
        return WordAim.pick(in: Array(text), at: position, favoring: favoring) {
            scanner.longestMatch(String($0), in: self.source)
        }?.word
    }

    func testLongestMatchNeedsNoGlossary() {
        let scanner = TextScanner()
        XCTAssertEqual(scanner.longestMatch("人格が", in: source), 2)
        XCTAssertEqual(scanner.longestMatch("入れ替わった", in: source), 6)
        XCTAssertEqual(scanner.longestMatch("、", in: source), 0)
    }

    func testAnyCharacterOfAWordFindsTheWord() {
        let text = "彼女たちは天気によって人格が入れ替わった"
        XCTAssertEqual(pick(text, at: 0.5), "彼女")
        XCTAssertEqual(pick(text, at: 1.5), "彼女")
        XCTAssertEqual(pick(text, at: 11.5), "人格")
        XCTAssertEqual(pick(text, at: 12.5), "人格")
        XCTAssertEqual(pick(text, at: 15.5), "入れ替わった")
    }

    func testAParticleIsStillReachable() {
        let text = "彼女たちは天気によって"
        XCTAssertEqual(pick(text, at: 4.4), "は")
        // The last bit of a lone particle snaps to the word after it.
        XCTAssertEqual(pick(text, at: 4.85), "天気")
    }

    func testTheWordOnScreenResistsATremor() {
        let text = "彼女たちは天気によって"
        XCTAssertEqual(pick(text, at: 4.75, favoring: "天気"), "天気")
        XCTAssertEqual(pick(text, at: 4.9, favoring: "は"), "は")
        XCTAssertEqual(pick(text, at: 5.3, favoring: "は"), "天気")
    }

    func testPrefersTheWordStartingNearerTheAim() {
        XCTAssertEqual(pick("ことができる", at: 3.5), "できる")
        XCTAssertEqual(pick("ことができる", at: 0.5), "ことができる")
    }

    func testSkipsPunctuation() {
        XCTAssertEqual(pick("、天気", at: 0.3), "天気")
    }

    func testSentenceAcrossBrackets() {
        let text = Array("と言った。「人格が入れ替わった。」彼女は")
        XCTAssertEqual(WordAim.sentence(in: text, around: 7), "「人格が入れ替わった。」")
        XCTAssertEqual(WordAim.sentence(in: text, around: 18), "彼女は")
    }

    func testStabilizerNeedsAgreement() {
        let text = Array("彼女たちは天気")
        let she = WordAim.Pick(text: text, start: 0, length: 2)
        let weather = WordAim.Pick(text: text, start: 5, length: 2)
        let particle = WordAim.Pick(text: text, start: 4, length: 1)
        var s = PickStabilizer()
        XCTAssertNil(s.feed(weather, at: 0.0))
        XCTAssertEqual(s.feed(weather, at: 0.2)?.word, "天気")
        // One frame on the particle doesn't move it, nor do frames with nothing.
        XCTAssertNil(s.feed(particle, at: 0.4))
        XCTAssertNil(s.feed(nil, at: 0.6))
        XCTAssertNil(s.feed(weather, at: 0.8))
        XCTAssertEqual(s.shown?.word, "天気")
        // A new word wins once it clearly has more frames.
        XCTAssertNil(s.feed(she, at: 1.0))
        XCTAssertNil(s.feed(she, at: 1.2))
        XCTAssertEqual(s.feed(she, at: 1.4)?.word, "彼女")
    }

    func testStabilizerForgetsOldFrames() {
        let text = Array("彼女たちは天気")
        let she = WordAim.Pick(text: text, start: 0, length: 2)
        let weather = WordAim.Pick(text: text, start: 5, length: 2)
        var s = PickStabilizer()
        _ = s.feed(weather, at: 0)
        _ = s.feed(weather, at: 0.2)
        // Two seconds later (the phone was moving): two frames are enough again.
        XCTAssertNil(s.feed(she, at: 2.5))
        XCTAssertEqual(s.feed(she, at: 2.7)?.word, "彼女")
    }
}
