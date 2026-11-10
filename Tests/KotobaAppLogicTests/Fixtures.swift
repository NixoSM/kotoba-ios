import Foundation
import XCTest
import KotobaCore
import ZIPFoundation
@testable import KotobaAppLogic

/// A small library to search: an Italian dictionary, an English one and a frequency list.
enum Fixtures {
    static let italian = """
    [["食べる","たべる","v1","v1",100,["mangiare","vivere di (uno stipendio)"],1,"P"],
     ["食べ物","たべもの","n","",90,["cibo"],2,""],
     ["食べ放題","たべほうだい","n","",10,["a volontà"],3,""],
     ["新聞","しんぶん","n","",80,["giornale","quotidiano"],4,""],
     ["新聞紙","しんぶんし","n","",20,["carta di giornale"],5,""],
     ["芯","しん","n","",30,["anima, nucleo"],6,""],
     ["東京","とうきょう","n","",70,["Tokyo"],7,""],
     ["書く","かく","v5k","v5",60,["scrivere"],8,""],
     ["猫","ねこ","n","",50,["gatto"],9,""],
     ["コーヒー","コーヒー","n","",40,["caffè"],10,""]]
    """

    static let english = """
    [["食べる","たべる","v1","v1",100,["to eat","to live on (e.g. a salary)"],1,"P"],
     ["猫","ねこ","n","",50,["cat"],2,""],
     ["食べ物","たべもの","n","",90,[{"type":"structured-content","content":{"tag":"span","data":{"x onclick=alert(1) y":"1"},"content":"food <script>alert(1)</script>"}}],3,""]]
    """

    static let frequencies = """
    [["食べる","freq",{"value":400,"displayValue":"400"}],["食べ物","freq",900],["食べ放題","freq",9000],
     ["新聞","freq",1200],["新聞紙","freq",15000],["猫","freq",1500],["東京","freq",300],
     ["食べる","pitch",{"reading":"たべる","pitches":[{"position":2}]}],["猫","pitch",{"reading":"ねこ","pitches":[{"position":1}]}]]
    """

    /// A kanji dictionary in Yomitan's format 3: character, on, kun, tags, meanings, stats.
    static let kanji = """
    [["食","ショク ジキ","く.う た.べる は.む","jouyou",["mangiare","cibo"],{"strokes":"9","grade":"2","jlpt":"N4","freq":"328","heisig":"1472"}],
     ["物","ブツ モツ","もの","jouyou",["cosa","oggetto"],{"strokes":"8","grade":"3","jlpt":"N4"}],
     ["猫","ビョウ","ねこ","jouyou",["gatto"],{"strokes":"11","grade":"8"}]]
    """

    static func store() throws -> DictionaryStore {
        let store = try DictionaryStore(path: ":memory:")
        try install("Dizionario italiano", terms: italian, into: store)
        try install("JMdict (English)", terms: english, into: store)
        try install("Frequenze", meta: frequencies, into: store)
        try store.buildMissingKanaIndexes()
        return store
    }

    @discardableResult
    static func install(_ title: String, terms: String? = nil, meta: String? = nil, kanji: String? = nil, styles: String = "",
                        into store: DictionaryStore) throws -> InstalledDictionary {
        let index = try YomitanParser.index(from: Data(#"{"title":"\#(title)","revision":"1","format":3}"#.utf8))
        return try store.install(index: index, styles: styles) { session in
            if let terms { try session.add(YomitanParser.termBank(from: Data(terms.utf8))) }
            if let meta { try session.add(YomitanParser.termMetaBank(from: Data(meta.utf8))) }
            if let kanji { try session.add(YomitanParser.kanjiBank(from: Data(kanji.utf8), file: "kanji_bank_1.json")) }
        }
    }

    /// A dictionary file as Yomitan distributes them, in a scratch folder.
    static func dictionaryFile(_ title: String, terms: String? = nil, banks: Int = 1, extra: [String: String] = [:]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(title).zip")
        let archive = try Archive(url: url, accessMode: .create)
        var files = extra
        if extra["index.json"] == nil { files["index.json"] = #"{"title":"\#(title)","revision":"1","format":3}"# }
        for n in 1...max(1, banks) where terms != nil { files["term_bank_\(n).json"] = n == 1 ? terms : "[]" }
        for (name, text) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(text.utf8)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    static func search(_ text: String, in store: DictionaryStore, suggest: Bool = false) -> SearchResults {
        SearchEngine.run(SearchEngine.Request(text: text, suggest: suggest), store: store, scanner: TextScanner())
    }
}
