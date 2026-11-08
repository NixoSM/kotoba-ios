import XCTest
@testable import KotobaCore

final class AnkiAndMetaTests: XCTestCase {
    func testFurigana() {
        XCTAssertEqual(Furigana.ankiPlain(expression: "食べ物", reading: "たべもの"), "食[た]べ 物[もの]")
        XCTAssertEqual(Furigana.ankiPlain(expression: "攻撃", reading: "こうげき"), "攻撃[こうげき]")
        XCTAssertEqual(Furigana.ankiPlain(expression: "ねこ", reading: "ねこ"), "ねこ")
        XCTAssertEqual(Furigana.html(expression: "お茶", reading: "おちゃ"), "お<ruby>茶<rt>ちゃ</rt></ruby>")
    }

    func testMoraAndPitch() {
        XCTAssertEqual(Mora.split("きょう"), ["きょ", "う"])
        XCTAssertEqual(Mora.pattern(morae: 3, downstep: 0), [false, true, true, true])
        XCTAssertEqual(Mora.pattern(morae: 3, downstep: 1), [true, false, false, false])
        XCTAssertEqual(Mora.pattern(morae: 3, downstep: 2), [false, true, false, false])
        let p = TermMetaParser.pitch(["reading": "こうげき", "pitches": [["position": 0]]] as [String: Any], dictionary: "A")
        XCTAssertEqual(p?.positions, [0])
        XCTAssertTrue(PitchHTML.list([p!], reading: "こうげき").hasSuffix("[0]"))
    }

    func testFrequencyParsing() {
        let f = TermMetaParser.frequency(["reading": "こうげき", "frequency": ["value": 1500, "displayValue": "1500㋕"]] as [String: Any], dictionary: "JPDB")
        XCTAssertEqual(f?.reading, "こうげき")
        XCTAssertEqual(f?.value, 1500)
        XCTAssertEqual(f?.display, "1500㋕")
        XCTAssertEqual(AnkiFieldRenderer.harmonic([
            FrequencyInfo(dictionary: "a", reading: nil, value: 100, display: ""),
            FrequencyInfo(dictionary: "b", reading: nil, value: 300, display: ""),
        ]), "150")
    }

    private var context: MiningContext {
        MiningContext(expression: "食べる", reading: "たべる", sentence: "昨日は何も食べなかった。", matchedText: "食べなかった",
                      reasons: [.negative, .past], definitions: [("JMdict", ["to eat"])], frequencies: [],
                      pitches: [], partsOfSpeech: ["v1"])
    }

    func testTemplates() {
        XCTAssertEqual(AnkiFieldRenderer.render("{cloze-prefix}<b>{cloze-body}</b>{cloze-suffix}", context),
                       "昨日は何も<b>食べなかった</b>。")
        XCTAssertEqual(AnkiFieldRenderer.render("{glossary}", context), "<div><i>(JMdict)</i> to eat</div>")
        XCTAssertEqual(AnkiFieldRenderer.render("{expression}/{audio}", context), "食べる/")
        let format = AnkiNoteFormat(deck: "D", model: "M", fields: [.init(name: "Audio", template: "{audio}"), .init(name: "W", template: "{expression}")])
        XCTAssertEqual(AnkiFieldRenderer.unsupportedMarkers(in: format), ["audio"])
    }

    func testAnkiMobileURL() throws {
        let format = AnkiNoteFormat(deck: "Studio::Mining", model: "Animecards",
                                    fields: [.init(name: "Word", template: "{expression}"), .init(name: "Glossary", template: "{glossary}")])
        let url = try XCTUnwrap(AnkiMobileLink.url(format: format, context: context))
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("anki://x-callback-url/addnote?type=Animecards&deck=Studio%3A%3AMining&dupes=1"), s)
        XCTAssertTrue(s.contains("fldWord=%E9%A3%9F%E3%81%B9%E3%82%8B"), s)
        XCTAssertTrue(s.contains("x-success=kotoba%3A%2F%2Fmined"), s)
    }

    func testYomitanSettings() throws {
        let json = """
        {"version":1,"options":{"profileCurrent":0,"profiles":[{"name":"Default","options":{
          "general":{"sortFrequencyDictionary":"JPDB"},
          "dictionaries":[{"name":"B","enabled":true},{"name":"A","enabled":false},{"name":"Missing","enabled":true}],
          "anki":{"tags":["yomitan"],"cardFormats":[{"name":"Expression","type":"term","deck":"Mine","model":"Animecards",
            "fields":{"Word":{"value":"{expression}"},"Reading":{"value":"{reading}"},"Glossary":{"value":"{glossary}"}}}]}
        }}]}}
        """
        let settings = try YomitanSettings.parse(Data(json.utf8))
        XCTAssertEqual(settings.dictionaries.map(\.name), ["B", "A", "Missing"])
        XCTAssertEqual(settings.sortFrequencyDictionary, "JPDB")
        XCTAssertEqual(settings.ankiTermFormat?.fields.map(\.name), ["Word", "Reading", "Glossary"])
        XCTAssertEqual(settings.ankiTermFormat?.deck, "Mine")
        XCTAssertEqual(settings.ankiTermFormat?.tags, ["yomitan"])
    }
}
