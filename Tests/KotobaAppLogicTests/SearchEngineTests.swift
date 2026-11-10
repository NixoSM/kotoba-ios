import XCTest
import KotobaCore
@testable import KotobaAppLogic

final class SearchEngineTests: XCTestCase {
    func testJapaneseTextFindsTheWordUnderIt() throws {
        let store = try Fixtures.store()
        let found = Fixtures.search("食べなかった", in: store)
        XCTAssertEqual(found.direct.first?.expression, "食べる")
        XCTAssertEqual(found.direct.first?.reasons, [.negative, .past])
        // Both dictionaries under one headword, in dictionary order.
        XCTAssertEqual(found.direct.first?.definitions.map(\.dictionary), ["Dizionario italiano", "JMdict (English)"])
        XCTAssertEqual(found.direct.first?.frequencies.first?.display, "400")
        XCTAssertTrue(found.byMeaning.isEmpty)
        XCTAssertNotNil(found.milliseconds)
    }

    func testVerbStemWithAnEndingIsOneWord() throws {
        let store = try Fixtures.store()
        let found = Fixtures.search("食べながら", in: store)
        XCTAssertEqual(found.direct.first?.expression, "食べる")
        XCTAssertEqual(found.direct.first?.matchedText, "食べながら")
        XCTAssertEqual(found.direct.first?.reasons, [.whileDoing])
    }

    func testRomajiAndLongVowels() throws {
        let store = try Fixtures.store()
        let plain = Fixtures.search("taberu", in: store)
        XCTAssertEqual(plain.romajiReading, "たべる")
        XCTAssertEqual(plain.direct.first?.expression, "食べる")
        // ō is おう here; the mark alone does not say so.
        let macron = Fixtures.search("tōkyō", in: store)
        XCTAssertEqual(macron.romajiReading, "とうきょう")
        XCTAssertEqual(macron.direct.first?.expression, "東京")
        XCTAssertEqual(Fixtures.search("shimbun", in: store).direct.first?.expression, "新聞")
        XCTAssertEqual(Fixtures.search("kōhī", in: store).direct.first?.expression, "コーヒー")
    }

    func testMeaningSearch() throws {
        let store = try Fixtures.store()
        let found = Fixtures.search("gatto", in: store)
        XCTAssertEqual(found.byMeaning.first?.expression, "猫")
        XCTAssertTrue(found.direct.isEmpty)
        XCTAssertFalse(found.romajiFirst)
        // Two words: never romaji.
        XCTAssertNil(Fixtures.search("to eat", in: store).romajiReading)
        XCTAssertEqual(Fixtures.search("to eat", in: store).byMeaning.first?.expression, "食べる")
    }

    func testWordsThatStartWithWhatWasTyped() throws {
        let store = try Fixtures.store()
        // Half a word typed: the scan stops at しん (芯), the word wanted is in the list, which goes first.
        let half = Fixtures.search("しんぶ", in: store, suggest: true)
        XCTAssertEqual(half.direct.first?.expression, "芯")
        XCTAssertEqual(half.startingWith.map(\.expression), ["新聞", "新聞紙"])
        XCTAssertEqual(half.startingWith.first?.reading, "しんぶん")
        XCTAssertEqual(half.startingWith.first?.gloss, "giornale")
        XCTAssertEqual(half.startingWithText, "しんぶ")
        XCTAssertTrue(half.suggestionsFirst)

        // A whole word typed: it is shown in full, and is not repeated in the list. Commonest first.
        let whole = Fixtures.search("食べ", in: store, suggest: true)
        XCTAssertEqual(whole.direct.first?.expression, "食べる")
        XCTAssertEqual(whole.startingWith.map(\.expression), ["食べ物", "食べ放題"])
        XCTAssertFalse(whole.suggestionsFirst)

        // Romaji, and hiragana typed for a katakana word.
        XCTAssertEqual(Fixtures.search("shinbu", in: store, suggest: true).startingWith.map(\.expression), ["新聞", "新聞紙"])
        XCTAssertEqual(Fixtures.search("こーひ", in: store, suggest: true).startingWith.map(\.expression), ["コーヒー"])
    }

    func testNoListUnlessAskedAndNotForOneKana() throws {
        let store = try Fixtures.store()
        // A tapped word in a sentence is not a word being typed.
        XCTAssertTrue(Fixtures.search("食べ", in: store).startingWith.isEmpty)
        // One kana starts tens of thousands of words in a real dictionary.
        XCTAssertTrue(Fixtures.search("し", in: store, suggest: true).startingWith.isEmpty)
        // One kanji is enough.
        XCTAssertEqual(Fixtures.search("新", in: store, suggest: true).startingWith.map(\.expression), ["新聞", "新聞紙"])
        XCTAssertTrue(Fixtures.search("gatto", in: store, suggest: true).startingWith.isEmpty)
    }

    func testEmptyAndUnknown() throws {
        let store = try Fixtures.store()
        XCTAssertTrue(Fixtures.search("   ", in: store, suggest: true).isEmpty)
        XCTAssertTrue(Fixtures.search("犬", in: store, suggest: true).isEmpty)
        XCTAssertTrue(Fixtures.search("zzzz", in: store, suggest: true).isEmpty)
    }

    func testSwitchedOffDictionaryIsNotSearched() throws {
        let store = try Fixtures.store()
        let italian = try XCTUnwrap(try store.dictionaries().first { $0.title == "Dizionario italiano" })
        try store.setEnabled(false, dictionary: italian.id)
        XCTAssertTrue(Fixtures.search("gatto", in: store).isEmpty)
        XCTAssertEqual(Fixtures.search("cat", in: store).byMeaning.first?.expression, "猫")
        XCTAssertEqual(Fixtures.search("猫", in: store).direct.first?.definitions.map(\.dictionary), ["JMdict (English)"])
    }

    func testMinedLinkNamesTheWord() throws {
        let key = "食べる|たべる"
        let address = MinedLink.returnURL(for: key)
        XCTAssertTrue(address.hasPrefix("kotoba://mined?c=\(MinedLink.code)&k="), address)
        XCTAssertEqual(MinedLink.minedKey(from: try XCTUnwrap(URL(string: address))), key)
        // An older link without the word, and other addresses.
        XCTAssertNil(MinedLink.minedKey(from: try XCTUnwrap(URL(string: "kotoba://mined"))))
        XCTAssertNil(MinedLink.minedKey(from: try XCTUnwrap(URL(string: "kotoba://search?k=x"))))
        // What a web page or another app could open: no code, or a guessed one.
        XCTAssertNil(MinedLink.minedKey(from: try XCTUnwrap(URL(string: "kotoba://mined?k=x"))))
        XCTAssertNil(MinedLink.minedKey(from: try XCTUnwrap(URL(string: "kotoba://mined?c=guess&k=x"))))
        XCTAssertNil(MinedLink.minedKey(from: try XCTUnwrap(URL(string: "kotoba://mined?c=&k=x"))))
        XCTAssertEqual(MinedLink.code, MinedLink.code, "made once, then kept")
        XCTAssertGreaterThanOrEqual(MinedLink.code.count, 32)
        // Odd characters survive the trip.
        let odd = "a&b=c d|え+"
        XCTAssertEqual(MinedLink.minedKey(from: try XCTUnwrap(URL(string: MinedLink.returnURL(for: odd)))), odd)
    }
}
