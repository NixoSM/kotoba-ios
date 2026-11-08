#if canImport(SQLite3)
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

    func testStructuredContentFlattening() {
        let json = #"[{"type":"structured-content","content":[{"tag":"ul","content":[{"tag":"li","content":"to eat"},{"tag":"li","content":["to ",{"tag":"ruby","content":["生",{"tag":"rt","content":"せい"}]},"live on"]}]}]}]"#
        XCTAssertEqual(GlossaryText.items(fromJSON: Data(json.utf8)), ["to eat\nto 生live on"])
    }
}
#endif
