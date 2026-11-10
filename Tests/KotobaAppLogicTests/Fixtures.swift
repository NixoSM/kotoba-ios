import Foundation
import XCTest
import KotobaCore
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

    static func store() throws -> DictionaryStore {
        let store = try DictionaryStore(path: ":memory:")
        try install("Dizionario italiano", terms: italian, into: store)
        try install("JMdict (English)", terms: english, into: store)
        try install("Frequenze", meta: frequencies, into: store)
        try store.buildMissingKanaIndexes()
        return store
    }

    @discardableResult
    static func install(_ title: String, terms: String? = nil, meta: String? = nil, styles: String = "",
                        into store: DictionaryStore) throws -> InstalledDictionary {
        let index = try YomitanParser.index(from: Data(#"{"title":"\#(title)","revision":"1","format":3}"#.utf8))
        return try store.install(index: index, styles: styles) { session in
            if let terms { try session.add(YomitanParser.termBank(from: Data(terms.utf8))) }
            if let meta { try session.add(YomitanParser.termMetaBank(from: Data(meta.utf8))) }
        }
    }

    static func search(_ text: String, in store: DictionaryStore, suggest: Bool = false) -> SearchResults {
        SearchEngine.run(SearchEngine.Request(text: text, suggest: suggest), store: store, scanner: TextScanner())
    }
}
