import XCTest
import KotobaCore
@testable import KotobaAppLogic

/// The model the screens share: importing, deleting, the Anki round trip.
/// These run with stand-ins for the phone (see App/LogicSupport).
@MainActor
final class AppModelTests: XCTestCase {
    private func italianSettings() -> AppSettings {
        var settings = AppSettings()
        settings.language = .it
        return settings
    }

    private func model(onDisk: Bool = false, settings: AppSettings? = nil) throws -> AppModel {
        var path = ":memory:"
        if onDisk {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-model-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            path = folder.appendingPathComponent("dictionaries.sqlite").path
        }
        return AppModel(store: try DictionaryStore(path: path), settings: settings ?? italianSettings())
    }

    private func wait(for what: String, timeout: TimeInterval = 20, until done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() {
            guard Date() < deadline else { return XCTFail("still waiting for: \(what)") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private var titles: (AppModel) -> [String] { { $0.dictionaries.map(\.title) } }

    // MARK: Import

    func testSeveralFilesAreImportedOneAfterTheOther() async throws {
        let model = try model()
        let files = try ["Uno", "Due", "Tre"].map { try Fixtures.dictionaryFile($0, terms: Fixtures.italian) }
        let before = LongWork.begun
        model.importDictionaries(from: files)
        XCTAssertEqual(model.importStatus, .running(title: "Uno", fraction: 0, position: 1, total: 3))
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(LongWork.running, 1, "the screen is kept on while importing")
        try await wait(for: "the three imports") { !model.isImporting }
        XCTAssertEqual(titles(model), ["Uno", "Due", "Tre"])
        XCTAssertEqual(model.importStatus, .finished(summary: "3 dizionari importati"))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(LongWork.running, 0)
        XCTAssertEqual(LongWork.begun, before + 1, "one request for the whole queue")
        model.clearImportSummary()
        XCTAssertNil(model.importStatus)
    }

    func testOneFileSaysHowManyEntriesItHad() async throws {
        let model = try model()
        model.importDictionary(from: try Fixtures.dictionaryFile("Uno", terms: Fixtures.italian))
        try await wait(for: "the import") { !model.isImporting }
        XCTAssertEqual(model.importStatus, .finished(summary: "Uno: 10 voci importate"))
    }

    func testAKanjiDictionarySaysHowManyKanji() async throws {
        let model = try model()
        model.importDictionary(from: try Fixtures.dictionaryFile("Kanji", extra: ["kanji_bank_1.json": Fixtures.kanji]))
        try await wait(for: "the import") { !model.isImporting }
        XCTAssertEqual(model.importStatus, .finished(summary: "Kanji: 3 kanji importati"))
        XCTAssertEqual(model.dictionaries.first?.kanjiCount, 3)
    }

    /// A frequency list holds no words: "0 voci importate" read like a failure.
    func testAFrequencyDictionarySaysWhatItBrought() async throws {
        let model = try model()
        model.importDictionary(from: try Fixtures.dictionaryFile("Frequenze", extra: ["term_meta_bank_1.json": Fixtures.frequencies]))
        try await wait(for: "the import") { !model.isImporting }
        XCTAssertEqual(model.importStatus, .finished(summary: "Frequenze: 9 frequenze e accenti importati"))
        XCTAssertNil(model.errorMessage)
    }

    /// A download that did not finish, or a file that is not a .zip at all,
    /// used to answer "the operation couldn't be completed".
    func testAFileThatIsNotAZipSaysSo() async throws {
        let model = try model()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let half = folder.appendingPathComponent("Mezzo.zip")
        let whole = try Data(contentsOf: try Fixtures.dictionaryFile("Mezzo", terms: Fixtures.italian))
        try whole.prefix(whole.count / 2).write(to: half)
        let bad = try Fixtures.dictionaryFile("Storto", extra: ["term_bank_1.json": #"{"not":"a list"}"#])
        model.importDictionaries(from: [half, bad])
        try await wait(for: "the imports") { !model.isImporting }
        XCTAssertEqual(titles(model), [])
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains("Mezzo: Non riesco a leggere questo file .zip"), message)
        XCTAssertTrue(message.contains("Storto: Il file term_bank_1.json del dizionario non è nel formato di Yomitan."), message)
        XCTAssertFalse(message.contains("Import fallito"), message)
    }

    /// The first-run screen suggests the Yomitan backup right after the
    /// dictionaries. Done while they were still importing, it froze the app
    /// for five seconds and then blamed the backup.
    func testYomitanSettingsWaitForTheImportToEnd() async throws {
        let model = try model(onDisk: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backup = folder.appendingPathComponent("yomitan-settings.json")
        try Data(#"{"options":{"profileCurrent":0,"profiles":[{"name":"Default","options":{"general":{"fontSize":22},"dictionaries":[{"name":"Grande","enabled":false}]}}]}}"#.utf8).write(to: backup)

        model.importDictionary(from: try Fixtures.dictionaryFile("Grande", terms: Fixtures.italian, banks: 40))
        let started = Date()
        model.importYomitanSettings(from: backup)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "it answers at once instead of waiting for the database")
        XCTAssertTrue(try XCTUnwrap(model.errorMessage).hasPrefix("Le impostazioni di Yomitan si applicano ai dizionari già importati"))
        XCTAssertNotEqual(model.settings.appearance.fontSize, 22, "nothing was applied by halves")
        model.errorMessage = nil
        // Deleting or switching a dictionary meanwhile says why nothing happens.
        try await wait(for: "the import") { !model.isImporting }
        let grande = try XCTUnwrap(model.dictionaries.first)
        model.importDictionary(from: try Fixtures.dictionaryFile("Altro", terms: Fixtures.italian, banks: 40))
        model.delete(grande)
        XCTAssertEqual(model.toast, "Aspetta che Kotoba finisca di scrivere i dizionari")
        XCTAssertNil(model.deleting)
        try await wait(for: "the second import") { !model.isImporting }

        // Afterwards the same backup applies.
        model.importYomitanSettings(from: backup)
        XCTAssertEqual(model.settings.appearance.fontSize, 22)
        XCTAssertEqual(model.dictionaries.first { $0.title == "Grande" }?.enabled, false)
        // Not a backup at all.
        model.errorMessage = nil
        try Data(#"{"ciao":1}"#.utf8).write(to: backup)
        model.importYomitanSettings(from: backup)
        XCTAssertEqual(model.errorMessage, "Non riesco a leggere questo backup di Yomitan: il file non contiene impostazioni di Yomitan")
    }

    /// Before, one import at a time and the second pick replaced the first's progress.
    func testABadFileDoesNotStopTheOthers() async throws {
        let model = try model()
        let good = try Fixtures.dictionaryFile("Uno", terms: Fixtures.italian)
        let notADictionary = try Fixtures.dictionaryFile("Foto", extra: ["index.json": "", "readme.txt": "ciao"])
        let again = try Fixtures.dictionaryFile("Uno", terms: Fixtures.italian)
        let last = try Fixtures.dictionaryFile("Tre", terms: Fixtures.italian)
        model.importDictionaries(from: [good, notADictionary, again, last])
        try await wait(for: "the imports") { !model.isImporting }
        XCTAssertEqual(titles(model), ["Uno", "Tre"])
        XCTAssertEqual(model.importStatus, .finished(summary: "2 dizionari importati"))
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains("Foto: "), message)
        XCTAssertTrue(message.contains("Uno: 「Uno」 è già installato."), message)
        XCTAssertEqual(LongWork.running, 0)
    }

    func testFilesPickedWhileImportingJoinTheQueue() async throws {
        let model = try model()
        model.importDictionaries(from: [try Fixtures.dictionaryFile("Uno", terms: Fixtures.italian)])
        model.importDictionaries(from: [try Fixtures.dictionaryFile("Due", terms: Fixtures.italian)])
        guard case .running(_, _, 1, 2) = model.importStatus else { return XCTFail("\(String(describing: model.importStatus))") }
        try await wait(for: "both imports") { !model.isImporting }
        XCTAssertEqual(titles(model), ["Uno", "Due"])
        XCTAssertEqual(LongWork.running, 0)
    }

    func testCancelDropsTheFilesStillWaiting() async throws {
        let model = try model()
        let big = try Fixtures.dictionaryFile("Grande", terms: Fixtures.italian, banks: 40)
        model.importDictionaries(from: [big, try Fixtures.dictionaryFile("Dopo", terms: Fixtures.italian)])
        model.cancelImport()
        try await wait(for: "the import to stop") { !model.isImporting }
        XCTAssertFalse(titles(model).contains("Dopo"))
        XCTAssertNil(model.errorMessage, "stopping it yourself is not a problem to report")
        XCTAssertEqual(LongWork.running, 0)
        // A dictionary is either all there or not at all.
        if let kept = model.dictionaries.first { XCTAssertEqual(kept.termCount, 10) }
        // And the next import starts clean.
        model.importDictionary(from: try Fixtures.dictionaryFile("Dopo", terms: Fixtures.italian))
        try await wait(for: "the next import") { !model.isImporting }
        XCTAssertTrue(titles(model).contains("Dopo"))
    }

    /// iOS closes an app that is suspended in the middle of writing its
    /// database. When the time it grants in the background runs out, the
    /// import stops by itself and says why.
    func testLeavingTheAppForTooLongStopsTheImportAndSaysWhy() async throws {
        let model = try model()
        let big = try Fixtures.dictionaryFile("Grande", terms: Fixtures.italian, banks: 40)
        model.importDictionaries(from: [big, try Fixtures.dictionaryFile("Dopo", terms: Fixtures.italian)])
        LongWork.simulateExpiry()
        try await wait(for: "the import to stop") { !model.isImporting }
        XCTAssertFalse(titles(model).contains("Dopo"))
        XCTAssertTrue(try XCTUnwrap(model.errorMessage).contains("secondo piano"))
        XCTAssertEqual(LongWork.running, 0)
    }

    /// A database that cannot be read used to look like "nothing found".
    func testASearchThatCannotReadTheDatabaseSaysSoOnce() async throws {
        struct Unreadable: Error, CustomStringConvertible { var description: String { "disk image is malformed" } }
        Diagnostics.shared.clear()
        let model = try model(settings: italianSettings())
        let listener = try XCTUnwrap(model.store?.onReadError)
        // The same failure at every keystroke, as the engine reports it from its own thread.
        for _ in 1...5 { listener("search", Unreadable()) }
        try await wait(for: "the alert") { model.errorMessage != nil }
        XCTAssertTrue(model.errorMessage?.hasPrefix("La ricerca non riesce a leggere i dizionari") ?? false, model.errorMessage ?? "")
        XCTAssertEqual(Diagnostics.shared.entries.filter { $0.contains("Database not read (search): disk image is malformed") }.count, 1)
        // Dismissed: it does not come back for a second kind of failure, which the diary still records.
        model.errorMessage = nil
        listener("kanji", Unreadable())
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(Diagnostics.shared.entries.filter { $0.contains("Database not read") }.count, 2)
        Diagnostics.shared.clear()
    }

    // MARK: Dictionaries

    func testDeleteHappensAwayFromTheScreenAndTidiesTheSettings() async throws {
        for onDisk in [false, true] {
            var settings = italianSettings()
            settings.collapsedDictionaries = ["Uno", "Due"]
            settings.sortFrequencyDictionary = "Uno"
            let model = try model(onDisk: onDisk, settings: settings)
            let store = try XCTUnwrap(model.store)
            try Fixtures.install("Uno", terms: Fixtures.italian, into: store)
            try Fixtures.install("Due", terms: Fixtures.english, into: store)
            model.refresh()
            let (uno, due) = (model.dictionaries[0], model.dictionaries[1])

            model.delete(uno)
            XCTAssertEqual(model.deleting, "Uno")
            XCTAssertTrue(model.isBusy)
            // While one is being removed nothing else is changed.
            model.delete(due)
            model.setEnabled(false, for: due)
            try await wait(for: "the delete") { !model.isBusy }
            XCTAssertEqual(titles(model), ["Due"])
            XCTAssertTrue(model.dictionaries[0].enabled)
            XCTAssertEqual(model.settings.collapsedDictionaries, ["Due"])
            XCTAssertNil(model.settings.sortFrequencyDictionary)
            XCTAssertEqual(model.toast, "«Uno» eliminato")
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(LongWork.running, 0)
            XCTAssertTrue(store.entries(matching: "新聞").isEmpty)
            XCTAssertFalse(store.entries(matching: "猫").isEmpty)
        }
    }

    func testMovingRowsFollowsTheList() throws {
        let model = try model()
        let store = try XCTUnwrap(model.store)
        for title in ["A", "B", "C", "D"] { try Fixtures.install(title, terms: "[]", into: store) }
        model.refresh()
        // The list gives the rows that move and the gap they are dropped in.
        model.move(from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(titles(model), ["B", "C", "D", "A"])
        model.move(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(titles(model), ["A", "B", "C", "D"])
        model.move(from: IndexSet([0, 2]), to: 2)
        XCTAssertEqual(titles(model), ["B", "A", "C", "D"])
        model.move(from: IndexSet(integer: 1), to: 1)
        XCTAssertEqual(titles(model), ["B", "A", "C", "D"])
        XCTAssertNil(model.errorMessage)
    }

    // MARK: Anki

    /// The tick used to appear the moment AnkiMobile was opened, even if the
    /// note was then abandoned there.
    func testTheTickAppearsOnlyWhenAnkiSaysTheNoteWasSaved() async throws {
        var settings = italianSettings()
        settings.ankiFormat = AnkiNoteFormat(deck: "Mining", model: "Basic", fields: [.init(name: "Front", template: "{expression}")])
        let model = try model(settings: settings)
        let store = try XCTUnwrap(model.store)
        try Fixtures.install("Dizionario", terms: Fixtures.italian, into: store)
        model.refresh()
        let found = await model.search("食べる")
        let group = try XCTUnwrap(found.direct.first)

        URLOpener.opened = []
        model.mine(group, sentence: "ご飯を食べる")
        let link = try XCTUnwrap(URLOpener.opened.last?.absoluteString)
        XCTAssertTrue(link.hasPrefix("anki://x-callback-url/addnote?"), link)
        XCTAssertTrue(model.settings.mined.isEmpty, "opening Anki is not yet a note")

        // AnkiMobile comes back to the address it was given.
        let success = try XCTUnwrap(URLComponents(string: link)?.queryItems?.first { $0.name == "x-success" }?.value)
        model.handle(url: try XCTUnwrap(URL(string: success)))
        XCTAssertEqual(model.settings.mined, ["食べる|たべる"])
        XCTAssertNotNil(model.settings.minedDates["食べる|たべる"])
        XCTAssertEqual(model.toast, "Aggiunta ad Anki")
    }

    func testWithoutAnkiTheButtonExplains() throws {
        let model = try model()
        let store = try XCTUnwrap(model.store)
        try Fixtures.install("Dizionario", terms: Fixtures.italian, into: store)
        let group = try XCTUnwrap(Fixtures.search("猫", in: store).direct.first)
        model.mine(group, sentence: "猫")
        XCTAssertTrue(try XCTUnwrap(model.errorMessage).contains("Impostazioni"))

        model.errorMessage = nil
        model.settings.ankiFormat = AnkiNoteFormat(deck: "D", model: "M", fields: [])
        URLOpener.succeeds = false
        defer { URLOpener.succeeds = true }
        model.mine(group, sentence: "猫")
        XCTAssertEqual(model.errorMessage, "AnkiMobile non risulta installato.")
    }

    func testASearchLinkOpensTheSearchTab() throws {
        let model = try model()
        model.selectedTab = 3
        model.handle(url: try XCTUnwrap(URL(string: "kotoba://search?q=%E7%8C%AB")))
        XCTAssertEqual(model.pendingQuery, "猫")
        XCTAssertEqual(model.selectedTab, 0)
        model.handle(url: try XCTUnwrap(URL(string: "https://example.com/mined?k=x")))
        XCTAssertTrue(model.settings.mined.isEmpty)
    }

    // MARK: Diagnostics

    func testTheReportSaysWhatIsInstalledAndWhatHappened() async throws {
        Diagnostics.shared.clear()
        let model = try model()
        model.importDictionaries(from: [try Fixtures.dictionaryFile("Uno", terms: Fixtures.italian),
                                        try Fixtures.dictionaryFile("Rotto", extra: ["index.json": "{"])])
        try await wait(for: "the imports") { !model.isImporting }
        let text = model.diagnosticsReport(device: [("Device", "iPhone15,4")]).text
        XCTAssertTrue(text.contains("Device: iPhone15,4"), text)
        XCTAssertTrue(text.contains("Dictionaries: 1 (1 on), 10 terms"), text)
        XCTAssertTrue(text.contains("✓ Uno: rev. 1, 10 terms"), text)
        XCTAssertTrue(text.contains("schema \(DictionaryStore.schemaVersion)"), text)
        XCTAssertTrue(text.contains("[app] Imported Uno: 10 terms"), text)
        XCTAssertTrue(text.contains("[app] Import failed: Rotto"), text)
    }
}

final class DiagnosticsTests: XCTestCase {
    func testTheDiaryKeepsTheLastLinesAndSurvivesARestart() {
        let diary = Diagnostics.shared
        diary.clear()
        XCTAssertEqual(diary.entries, [])
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        diary.log("two\nlines", at: when)
        XCTAssertEqual(diary.entries.count, 1)
        XCTAssertTrue(diary.entries[0].hasSuffix("[app] two ⏎ lines"), diary.entries[0])
        for n in 1...(Diagnostics.limit + 20) { diary.log("event \(n)") }
        XCTAssertEqual(diary.entries.count, Diagnostics.limit)
        XCTAssertTrue(diary.entries.last?.hasSuffix("event \(Diagnostics.limit + 20)") ?? false)
        // What a new launch reads from the file.
        XCTAssertEqual(Diagnostics().entries.count, Diagnostics.limit)
        XCTAssertTrue(Diagnostics().entries.first?.hasSuffix("event 21") ?? false)
        diary.clear()
        XCTAssertEqual(Diagnostics().entries, [])
        XCTAssertEqual(DiagnosticsReport(facts: [("Version", "1")], log: []).text, "Kotoba\nVersion: 1\n\n(log empty)\n")
    }

    /// The app and the share panel are two programs writing one diary. Each
    /// used to write the file from its own memory, so the app's next line
    /// erased whatever the panel had written since the app started.
    func testTwoProgramsWriteTheSameDiaryWithoutErasingEachOther() {
        let app = Diagnostics.shared
        app.clear()
        app.log("app one")
        let panel = Diagnostics()
        panel.source = "share"
        panel.log("panel one")
        app.log("app two")
        panel.log("panel two")
        let lines = app.entries.map { String($0.drop { $0 != "[" }) }
        XCTAssertEqual(lines, ["[app] app one", "[share] panel one", "[app] app two", "[share] panel two"])
        XCTAssertEqual(panel.entries, app.entries)
        app.clear()
        XCTAssertEqual(panel.entries, [])
    }
}

final class SigningInfoTests: XCTestCase {
    /// A provisioning profile is a property list inside a signed envelope.
    private func profile(expiring date: String) -> Data {
        var data = Data([0x30, 0x82, 0x1F, 0x00, 0xFF, 0xFE])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning Profile</string>
        <key>ExpirationDate</key><date>\(date)</date>
        </dict></plist>
        """.utf8))
        data.append(Data([0x00, 0xA0, 0x82, 0xFF]))
        return data
    }

    func testTheExpiryDateIsReadFromTheProfile() throws {
        let expiry = try XCTUnwrap(SigningInfo.expiry(inProfile: profile(expiring: "2026-11-17T09:30:00Z")))
        XCTAssertEqual(expiry, ISO8601DateFormatter().date(from: "2026-11-17T09:30:00Z"))
        XCTAssertNil(SigningInfo.expiry(inProfile: Data("not a profile".utf8)))
        XCTAssertNil(SigningInfo.expiry(inProfile: Data()))
    }

    func testTheWarningComesTwoDaysBefore() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        func notice(hoursBefore h: Double) -> SigningInfo.Notice {
            SigningInfo.notice(expiry: expiry, now: expiry.addingTimeInterval(-h * 3600))
        }
        XCTAssertEqual(notice(hoursBefore: 7 * 24), .none)
        XCTAssertEqual(notice(hoursBefore: 73), .none)
        XCTAssertEqual(notice(hoursBefore: 71), .soon(days: 2))
        XCTAssertEqual(notice(hoursBefore: 30), .soon(days: 1))
        XCTAssertEqual(notice(hoursBefore: 5), .soon(days: 0))
        XCTAssertEqual(notice(hoursBefore: 0), .expired)
        XCTAssertEqual(notice(hoursBefore: -48), .expired)
        XCTAssertEqual(SigningInfo.notice(expiry: nil), .none)
    }
}

final class WordIndexTests: XCTestCase {
    func testWordsAreFiledByKanaRow() {
        XCTAssertEqual(WordIndex.row(of: "ねこ"), "な")
        XCTAssertEqual(WordIndex.row(of: "がっこう"), "か")
        XCTAssertEqual(WordIndex.row(of: "パン"), "は")
        XCTAssertEqual(WordIndex.row(of: "ヴァイオリン"), "あ")
        XCTAssertEqual(WordIndex.row(of: "ん"), "わ")
        XCTAssertEqual(WordIndex.row(of: "ABC"), WordIndex.other)
        XCTAssertEqual(WordIndex.row(of: ""), WordIndex.other)
    }

    func testTheListIsInDictionaryOrder() {
        let mined: Set<String> = ["猫|ねこ", "食べる|たべる", "東京|とうきょう", "コーヒー|コーヒー", "NHK|", "新聞|しんぶん", "|x", ""]
        let words = WordIndex.words(mined: mined)
        XCTAssertEqual(words.count, 6, "keys without a word are left out")
        let sections = WordIndex.sections(words)
        XCTAssertEqual(sections.map(\.row), ["か", "さ", "た", "な", WordIndex.other])
        XCTAssertEqual(sections[2].words.map(\.expression), ["食べる", "東京"])
        XCTAssertEqual(sections[4].words.map(\.expression), ["NHK"])
    }

    func testNewestFirstPutsUndatedWordsLast() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let words = WordIndex.words(mined: ["猫|ねこ", "犬|いぬ", "鳥|とり", "魚|さかな"],
                                    dates: ["猫|ねこ": day, "鳥|とり": day.addingTimeInterval(60)])
        XCTAssertEqual(WordIndex.newestFirst(words).map(\.expression), ["鳥", "猫", "犬", "魚"])
    }

    func testSettingsRememberWhenAWordWasSent() throws {
        var settings = AppSettings()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        settings.markMined("猫|ねこ", at: first)
        settings.markMined("猫|ねこ", at: first.addingTimeInterval(500))
        settings.markMined("")
        XCTAssertEqual(settings.mined, ["猫|ねこ"])
        XCTAssertEqual(settings.minedDates["猫|ねこ"], first, "the first time counts")
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved, settings)
        settings.markMined("犬|いぬ")
        settings.forgetMined("猫|ねこ")
        XCTAssertEqual(settings.mined, ["犬|いぬ"])
        XCTAssertNil(settings.minedDates["猫|ねこ"])
        settings.forgetAllMined()
        XCTAssertTrue(settings.mined.isEmpty && settings.minedDates.isEmpty)
    }
}

final class KanjiResultsTests: XCTestCase {
    private func store() throws -> DictionaryStore {
        let store = try Fixtures.store()
        try Fixtures.install("Kanji", kanji: Fixtures.kanji, into: store)
        return store
    }

    func testTheKanjiOfTheFirstWordAreShown() throws {
        let store = try store()
        let results = Fixtures.search("食べ物を", in: store)
        XCTAssertEqual(results.kanjiSource, "食べ物")
        XCTAssertEqual(results.kanji.map(\.character), ["食", "物"])
        XCTAssertEqual(results.kanji[0].kunyomi, ["く.う", "た.べる", "は.む"])
        // Kana only: nothing to show.
        XCTAssertTrue(Fixtures.search("コーヒー", in: store).kanji.isEmpty)
        // Found by meaning: the kanji of the word found.
        XCTAssertEqual(Fixtures.search("gatto", in: store).kanji.map(\.character), ["猫"])
    }

    func testAKanjiThatIsNoWordStillAnswers() throws {
        let store = try store()
        let results = Fixtures.search("物", in: store)
        XCTAssertTrue(results.direct.isEmpty)
        XCTAssertEqual(results.kanji.map(\.character), ["物"])
        XCTAssertFalse(results.isEmpty)
        // Without a kanji dictionary the search is as empty as before.
        XCTAssertTrue(Fixtures.search("物", in: try Fixtures.store()).isEmpty)
    }

    func testOnlyTheFirstFourDifferentKanjiCount() {
        XCTAssertEqual(SearchEngine.kanjiCharacters(in: "一生懸命に生きる日々"), ["一", "生", "懸", "命"])
        XCTAssertEqual(SearchEngine.kanjiCharacters(in: "時々"), ["時"])
        XCTAssertEqual(SearchEngine.kanjiCharacters(in: "𠮟る"), ["𠮟"])
        XCTAssertEqual(SearchEngine.kanjiCharacters(in: "たべる taberu ＡＢ"), [])
    }

    func testThePageShowsReadingsMeaningsAndFacts() throws {
        L10n.apply(.it)
        let store = try store()
        let html = ResultsPage.html(outcome: Fixtures.search("食べ物", in: store), query: "食べ物", options: .init())
        XCTAssertTrue(html.contains("I kanji di «食べ物»"), "the heading")
        XCTAssertTrue(html.contains(#"<a class="kanji-glyph" lang="ja" href="kotoba://search?q=%E9%A3%9F">食</a>"#))
        XCTAssertTrue(html.contains(#"<span>た<span class="oku">べる</span></span>"#), "okurigana set apart")
        XCTAssertTrue(html.contains("<dt>音</dt><dd><span>ショク</span><i></i><span>ジキ</span></dd>"))
        XCTAssertTrue(html.contains(#"<p class="kanji-meanings">mangiare; cibo</p>"#))
        XCTAssertTrue(html.contains(#"<span class="tag">9 tratti</span><span class="tag">classe 2</span><span class="tag">JLPT N4</span><span class="tag">frequenza 328</span><span class="tag">jouyou</span>"#))
        XCTAssertFalse(html.contains("1472"), "index numbers of printed books are left out")
        XCTAssertFalse(html.contains(#"<div class="dict-name">Kanji</div>"#), "one kanji dictionary needs no label")
    }

    func testTwoKanjiDictionariesAreToldApart() throws {
        let store = try store()
        try Fixtures.install("Altro <b>", kanji: #"[["食","ショク","た.べる","",["eat <script>"],{}]]"#, into: store)
        let html = ResultsPage.html(outcome: Fixtures.search("食べ物", in: store), query: "食べ物", options: .init())
        XCTAssertTrue(html.contains(#"<div class="dict-name">Kanji</div>"#))
        XCTAssertTrue(html.contains(#"<div class="dict-name">Altro &lt;b&gt;</div>"#))
        XCTAssertTrue(html.contains("eat &lt;script&gt;"))
        XCTAssertEqual(html.components(separatedBy: #"class="kanji-glyph" lang="ja""#).count - 1, 2, "one square per character")
        XCTAssertTrue(html.contains(#"<section class="kanji more"><span class="kanji-glyph blank"></span>"#))
    }
}
