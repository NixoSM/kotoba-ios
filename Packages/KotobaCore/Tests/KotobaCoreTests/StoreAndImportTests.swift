#if canImport(SQLite3) || canImport(CSQLite3)
import XCTest
import ZIPFoundation
@testable import KotobaCore

final class StoreAndImportTests: XCTestCase {
    private func makeZip(title: String, files: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        var all = files
        all["index.json"] = #"{"title":"\#(title)","revision":"1","format":3}"#
        for (path, text) in all {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    private let jmdict = [
        "term_bank_1.json": #"[["食べる","たべる","v1","v1",100,["to eat"],1,"P"],["猫","ねこ","n","",50,["cat"],2,""]]"#,
        "term_meta_bank_1.json": #"[["食べる","freq",{"value":120,"displayValue":"120"}]]"#,
    ]

    func testImportAndLookup() throws {
        let store = try DictionaryStore(path: ":memory:")
        let installed = try YomitanImporter.importDictionary(at: try makeZip(title: "Test JMdict", files: jmdict), into: store)
        XCTAssertEqual(installed.termCount, 2)
        XCTAssertEqual(installed.metaCount, 1)

        let hits = TextScanner().scan("食べなかった", in: store)
        XCTAssertEqual(hits.first?.entry.expression, "食べる")
        XCTAssertEqual(hits.first?.entry.dictionary, "Test JMdict")
        XCTAssertEqual(GlossaryText.items(fromJSON: hits.first!.entry.glossaryJSON), ["to eat"])
    }

    func testScannerReadsDefinitionsOnlyForKeptHeadwords() throws {
        let store = try DictionaryStore(path: ":memory:")
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Test JMdict", files: jmdict), into: store)
        let header = try XCTUnwrap(store.entryHeaders(matching: "猫").first)
        XCTAssertTrue(header.glossaryJSON.isEmpty)
        XCTAssertNotNil(header.rowID)
        let filled = store.loadGlossaries([header])
        XCTAssertEqual(GlossaryText.items(fromJSON: filled[0].glossaryJSON), ["cat"])

        var scanner = TextScanner()
        scanner.maxHeadwords = 1
        let hits = scanner.scan("猫食べる", in: store)
        XCTAssertEqual(hits.map(\.entry.expression), ["猫"])
        XCTAssertEqual(GlossaryText.items(fromJSON: hits[0].entry.glossaryJSON), ["cat"])
    }

    func testHiraganaFindsKatakanaReadings() throws {
        let store = try DictionaryStore(path: ":memory:")
        let files = ["term_bank_1.json": #"[["イタリア語","イタリアご","n","",0,["Italian"],1,""],["アルバトロス","","n","",0,["albatross"],2,""]]"#]
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "K", files: files), into: store)
        try store.buildMissingKanaIndexes()
        XCTAssertEqual(TextScanner().scan("いたりあご", in: store).first?.entry.expression, "イタリア語")
        XCTAssertEqual(TextScanner().scan("あるばとろす", in: store).first?.entry.expression, "アルバトロス")
    }

    func testSecondImportOfSameTitleIsRejectedAndLeavesNothing() throws {
        let store = try DictionaryStore(path: ":memory:")
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "A", files: jmdict), into: store)
        XCTAssertThrowsError(try YomitanImporter.importDictionary(at: try makeZip(title: "A", files: jmdict), into: store))
        XCTAssertEqual(try store.dictionaries().count, 1)
        XCTAssertEqual(store.entries(matching: "猫").count, 1)
    }

    func testDisableReorderDelete() throws {
        let store = try DictionaryStore(path: ":memory:")
        let a = try YomitanImporter.importDictionary(at: try makeZip(title: "A", files: jmdict), into: store)
        let b = try YomitanImporter.importDictionary(at: try makeZip(title: "B", files: jmdict), into: store)
        XCTAssertEqual(store.entries(matching: "猫").map(\.dictionary), ["A", "B"])

        try store.reorder([b.id, a.id])
        XCTAssertEqual(store.entries(matching: "猫").map(\.dictionary), ["B", "A"])

        try store.setEnabled(false, dictionary: b.id)
        XCTAssertEqual(store.entries(matching: "猫").map(\.dictionary), ["A"])

        try store.delete(dictionary: a.id)
        XCTAssertEqual(store.entries(matching: "猫").count, 0)
        XCTAssertEqual(try store.dictionaries().map(\.title), ["B"])
    }

    func testSearchesKeepWorkingDuringAnImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try DictionaryStore(path: folder.appendingPathComponent("d.sqlite").path)
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "A", files: jmdict), into: store)
        var seenDuringImport: [String] = []
        let index = DictionaryIndex(title: "B", revision: "1", format: 3)
        _ = try store.install(index: index) { session in
            try session.add(YomitanParser.termBank(from: Data(jmdict["term_bank_1.json"]!.utf8)))
            // Before: the import held the store's lock, so this waited for the import (here: forever).
            seenDuringImport = store.entries(matching: "猫").map(\.dictionary)
        }
        XCTAssertEqual(seenDuringImport, ["A"], "searches see the dictionaries as they were until the import commits")
        XCTAssertEqual(store.entries(matching: "猫").map(\.dictionary), ["A", "B"])
    }

    func testStructuredContentFlattening() {
        let json = #"[{"type":"structured-content","content":[{"tag":"ul","content":[{"tag":"li","content":"to eat"},{"tag":"li","content":["to ",{"tag":"ruby","content":["生",{"tag":"rt","content":"せい"}]},"live on"]}]}]}]"#
        XCTAssertEqual(GlossaryText.items(fromJSON: Data(json.utf8)), ["to eat\nto 生live on"])
    }

    func testReverseSearch() throws {
        let store = try DictionaryStore(path: ":memory:")
        let files = [
            "term_bank_1.json": #"[["攻撃","こうげき","n","vs",0,["attack","assault"],1,""],["心臓発作","しんぞうほっさ","n","",0,["heart attack"],2,""],["挨拶","あいさつ","n","",0,["greeting"],3,""]]"#,
        ]
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "EN", files: files), into: store)
        let hits = store.reverseSearch("attack")
        XCTAssertEqual(hits.map(\.entry.expression), ["攻撃", "心臓発作"])

        try store.delete(dictionary: try store.dictionaries()[0].id)
        XCTAssertTrue(store.reverseSearch("attack").isEmpty)
    }

    func testFrequencyBreaksTies() throws {
        let store = try DictionaryStore(path: ":memory:")
        let terms = ["term_bank_1.json": #"[["稀","まれ","n","",0,["rare"],1,""],["珍しい","めずらしい","adj-i","adj-i",0,["rare"],2,""]]"#]
        let freq = ["term_meta_bank_1.json": #"[["珍しい","freq",500],["稀","freq",{"value":30000,"displayValue":"30000"}]]"#]
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Terms", files: terms), into: store)
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Freq", files: freq), into: store)
        XCTAssertEqual(store.reverseSearch("rare").map(\.entry.expression), ["珍しい", "稀"])
    }

    func testMediaImportAndRendering() throws {
        let store = try DictionaryStore(path: ":memory:")
        let files = [
            "term_bank_1.json": #"[["鳥","とり","n","",0,[{"type":"structured-content","content":{"tag":"img","path":"img/bird.png","width":2,"height":2,"sizeUnits":"em","title":"bird"}}],1,""]]"#,
            "img/bird.png": "PNGDATA",
        ]
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Pics", files: files), into: store)
        XCTAssertEqual(store.media(dictionary: "Pics", path: "img/bird.png"), Data("PNGDATA".utf8))
        let entry = try XCTUnwrap(store.entries(matching: "鳥").first)
        let html = GlossaryHTML.items(fromJSON: entry.glossaryJSON) { "m://" + $0 }.first ?? ""
        XCTAssertTrue(html.contains(#"src="m://img/bird.png""#), html)
        XCTAssertTrue(html.contains("width:2em"), html)
    }

    /// Looking each picture up by name restarted from the first file every
    /// time: 8,000 pictures took over two minutes. Found in one pass now.
    func testManyPicturesImportInOnePass() throws {
        let store = try DictionaryStore(path: ":memory:")
        var files = ["term_bank_1.json": #"[["鳥","とり","n","",0,["bird"],1,""]]"#]
        for i in 0..<3000 { files["img/\(i).png"] = "P\(i)" }
        let zip = try makeZip(title: "Pics", files: files)
        var steps: [ImportProgress] = []
        let start = Date()
        _ = try YomitanImporter.importDictionary(at: zip, into: store) { steps.append($0) }
        let seconds = Date().timeIntervalSince(start)
        XCTAssertLessThan(seconds, 20, "3,000 pictures took \(seconds) s")
        XCTAssertEqual(store.media(dictionary: "Pics", path: "img/2999.png"), Data("P2999".utf8))
        // One bank and 3,000 pictures in steps of 200: the bar moves 16 times, not once at the end.
        XCTAssertEqual(steps.first?.banksDone, 0)
        XCTAssertEqual(steps.last?.banksTotal, 16)
        XCTAssertEqual(steps.last?.banksDone, 16)
        XCTAssertEqual(steps.map(\.banksDone), Array(0...16))
    }

    func testBanksAreReadInNumberOrder() throws {
        let store = try DictionaryStore(path: ":memory:")
        var files: [String: String] = [:]
        for i in 1...12 { files["term_bank_\(i).json"] = #"[["語\#(i)","ご","n","",0,["word \#(i)"],\#(i),""]]"# }
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Order", files: files), into: store)
        // Entries get their ids in import order: bank 2 before bank 10.
        let ids = try (1...12).map { try XCTUnwrap(store.entries(matching: "語\($0)").first?.rowID) }
        XCTAssertEqual(ids, ids.sorted())
    }

    func testCancelledImportLeavesNothingBehind() throws {
        let store = try DictionaryStore(path: ":memory:")
        var files = jmdict
        files["term_bank_2.json"] = #"[["犬","いぬ","n","",0,["dog"],3,""]]"#
        var asked = 0
        XCTAssertThrowsError(try YomitanImporter.importDictionary(at: try makeZip(title: "Stop", files: files), into: store,
                                                                  isCancelled: { asked += 1; return asked > 1 })) {
            XCTAssertEqual($0 as? YomitanImportError, .cancelled)
        }
        XCTAssertTrue(try store.dictionaries().isEmpty)
        XCTAssertTrue(store.entries(matching: "猫").isEmpty)
        XCTAssertTrue(store.reverseSearch("cat").isEmpty)
        // The same file can be imported again afterwards.
        XCTAssertEqual(try YomitanImporter.importDictionary(at: try makeZip(title: "Stop", files: files), into: store).termCount, 3)
    }

    func testWordsStartingWith() throws {
        let store = try DictionaryStore(path: ":memory:")
        let files = ["term_bank_1.json": """
        [["食べる","たべる","v1","v1",100,["to eat"],1,""],["食べ物","たべもの","n","",90,["food"],2,""],
         ["食べ放題","たべほうだい","n","",10,["all you can eat"],3,""],["食","しょく","n","",5,["meal"],4,""],
         ["コーヒー","コーヒー","n","",50,["coffee"],5,""],["猫","ねこ","n","",50,["cat"],6,""]]
        """]
        let first = try YomitanImporter.importDictionary(at: try makeZip(title: "A", files: files), into: store)
        try store.buildMissingKanaIndexes()

        // By spelling: shortest first, the word itself left out.
        XCTAssertEqual(store.entriesStarting(with: "食").map(\.expression), ["食べる", "食べ物", "食べ放題"])
        XCTAssertEqual(store.entriesStarting(with: "食べ").map(\.expression), ["食べる", "食べ物", "食べ放題"])
        // By reading, with the definitions read in.
        let byReading = store.entriesStarting(with: "たべ")
        XCTAssertEqual(byReading.map(\.expression), ["食べる", "食べ物", "食べ放題"])
        XCTAssertEqual(GlossaryText.items(fromJSON: byReading[0].glossaryJSON), ["to eat"])
        // Hiragana typed for a katakana word.
        XCTAssertEqual(store.entriesStarting(with: "こー").map(\.expression), ["コーヒー"])
        XCTAssertEqual(store.entriesStarting(with: "食べ", limit: 2).count, 2)
        XCTAssertTrue(store.entriesStarting(with: "犬").isEmpty)
        XCTAssertTrue(store.entriesStarting(with: "").isEmpty)

        try store.setEnabled(false, dictionary: first.id)
        XCTAssertTrue(store.entriesStarting(with: "食").isEmpty)
    }

    func testEndOfPrefix() {
        XCTAssertEqual(DictionaryStore.end(ofPrefix: "ab"), "ac")
        XCTAssertEqual(DictionaryStore.end(ofPrefix: "食"), "飠")
        XCTAssertNil(DictionaryStore.end(ofPrefix: ""))
    }

    /// The 2,000 candidates used to be taken from every dictionary and the
    /// switched-off ones removed afterwards: a big one switched off could take
    /// all 2,000 places, and the search came back empty.
    func testReverseSearchIsNotCrowdedOutBySwitchedOffDictionaries() throws {
        let store = try DictionaryStore(path: ":memory:")
        let rows = (0..<2500).map { #"["語\#($0)","ご","n","",0,["cat"],\#($0),""]"# }.joined(separator: ",")
        let big = try YomitanImporter.importDictionary(at: try makeZip(title: "Big", files: ["term_bank_1.json": "[\(rows)]"]), into: store)
        let small = ["term_bank_1.json": #"[["猫","ねこ","n","",0,["cat (the animal that purrs and sleeps all day long)"],1,""]]"#]
        _ = try YomitanImporter.importDictionary(at: try makeZip(title: "Small", files: small), into: store)

        try store.setEnabled(false, dictionary: big.id)
        XCTAssertEqual(store.reverseSearch("cat").map(\.entry.expression), ["猫"])

        try store.setEnabled(true, dictionary: big.id)
        XCTAssertEqual(store.reverseSearch("cat", limit: 5).count, 5)
    }
}
#endif
