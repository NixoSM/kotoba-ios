import Foundation
import Observation
import KotobaCore

/// Owns the dictionary store and everything the screens share.
///
/// Nothing in this file needs a screen or an iPhone, so it is compiled and
/// tested on Linux too (see Package.swift at the root). What does need the
/// phone (clipboard, screenshots, staying awake) is in AppModel+Device.swift
/// and LongWork.swift.
@MainActor
@Observable
final class AppModel {
    private(set) var dictionaries: [InstalledDictionary] = []
    private(set) var importStatus: ImportStatus?
    /// Title of the dictionary being deleted, while its rows are removed.
    private(set) var deleting: String?
    var errorMessage: String?
    /// Short confirmation shown at the bottom of the screen.
    var toast: String?
    var settings: AppSettings {
        didSet {
            settings.save()
            if settings.appearance.theme != oldValue.appearance.theme { ThemeStore.shared.apply(settings.appearance.theme) }
            if settings.language != oldValue.language { L10n.apply(settings.language) }
        }
    }
    /// Set from outside (kotoba://search?q=…, camera) to run a search.
    var pendingQuery: String?
    /// The tab on screen: 0 search, 1 camera, 4 from PC, 5 words, 3 settings.
    var selectedTab = 0
    /// What the camera tab should open with.
    enum CameraRequest: Equatable { case lens, screenshot(String) }
    var cameraRequest: CameraRequest?

    let store: DictionaryStore?
    let scanner = TextScanner()

    var isImporting: Bool { if case .running = importStatus { true } else { false } }
    /// The database is being written: other changes to the dictionaries wait.
    var isBusy: Bool { isImporting || deleting != nil }

    enum ImportStatus: Equatable {
        /// `position` of `total` files, counted from 1.
        case running(title: String, fraction: Double, position: Int, total: Int)
        case finished(summary: String)
    }

    /// Opens the dictionaries where the app keeps them.
    convenience init() {
        var failure: String?
        var opened: DictionaryStore?
        do {
            #if KOTOBA_EXTENSION
            let folder = SharedStorage.folder
            #else
            let folder = SharedStorage.migrateToSharedFolder()
            #endif
            opened = try DictionaryStore(path: folder.appendingPathComponent(SharedStorage.databaseName).path)
        } catch {
            failure = tr("Impossibile aprire il database: {0}", error)
            Diagnostics.shared.log("Database did not open: \(error)")
        }
        self.init(store: opened, settings: AppSettings.load())
        errorMessage = failure
        #if !KOTOBA_EXTENSION
        buildMissingReverseIndexes()
        #endif
    }

    init(store: DictionaryStore?, settings: AppSettings) {
        self.store = store
        self.settings = settings
        MediaLink.store = store
        ThemeStore.shared.apply(settings.appearance.theme)
        L10n.apply(settings.language)
        refresh()
    }

    private(set) var stylesheets: [String: String] = [:] {
        didSet { if stylesheets != oldValue { dictionaryCSS = ResultsPage.scopedCSS(stylesheets) } }
    }
    /// `stylesheets` rewritten for the results page, done once instead of on every redraw.
    private(set) var dictionaryCSS = ""

    func refresh() {
        guard let store else { return }
        do {
            dictionaries = try store.dictionaries()
        } catch {
            report(tr("Non riesco a leggere l'elenco dei dizionari: {0}", error.localizedDescription), log: "List of dictionaries failed: \(error)")
        }
        stylesheets = store.stylesheets()
    }

    /// Shows a problem and writes it in the diary.
    private func report(_ message: String, log: String) {
        errorMessage = message
        Diagnostics.shared.log(log)
    }

    /// Older name of `SearchResults`, kept for the screens that use it.
    typealias SearchOutcome = SearchResults

    // MARK: Anki

    /// Opens AnkiMobile's "Add" screen filled with this word.
    func mine(_ group: HeadwordGroup, sentence: String) {
        guard let format = settings.ankiFormat else {
            errorMessage = tr("Prima configura la nota Anki in Impostazioni (puoi importarla dal backup di Yomitan).")
            return
        }
        // AnkiMobile opens this address once the note is saved: that, and not
        // the tap here, is what marks the word as added.
        guard let url = AnkiMobileLink.url(format: format, context: group.miningContext(sentence: sentence),
                                           returnURL: MinedLink.returnURL(for: group.minedKey)) else {
            errorMessage = tr("Non riesco a creare il collegamento per AnkiMobile.")
            return
        }
        URLOpener.open(url) { [weak self] opened in
            if !opened { self?.errorMessage = tr("AnkiMobile non risulta installato.") }
        }
    }

    func handle(url: URL) {
        guard url.scheme == "kotoba" else { return }
        switch url.host {
        case "mined":
            if let key = MinedLink.minedKey(from: url) { settings.markMined(key) }
            toast = tr("Aggiunta ad Anki")
        case "search":
            pendingQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            selectedTab = 0
        default:
            break
        }
    }

    // MARK: Yomitan settings

    /// Applies a Yomitan backup: dictionary order and switches, sort dictionary, Anki note.
    func importYomitanSettings(from url: URL) {
        let opened = PickedFile.open(url)
        defer { PickedFile.close(url, opened: opened) }
        do {
            let parsed = try YomitanSettings.parse(Data(contentsOf: url))
            var report: [String] = []
            if let store {
                let result = try store.apply(parsed.dictionaries)
                report.append(tr("Ordine e attivazione applicati a {0} dizionari.", result.applied))
                if !result.notInstalled.isEmpty {
                    report.append(tr("Non ancora importati: {0}.", result.notInstalled.joined(separator: ", ")))
                }
            }
            if let sort = parsed.sortFrequencyDictionary {
                settings.sortFrequencyDictionary = sort
                report.append(tr("Ordinamento per frequenza: {0}.", sort))
            }
            settings.appearance.apply(parsed.appearance)
            report.append(tr("Aspetto: carattere {0}, {1} pt, layout {2}.", FontCatalog.choice(settings.appearance.bodyFont).name, Int(settings.appearance.fontSize), settings.appearance.layout.label.lowercased()))
            if let format = parsed.ankiTermFormat {
                settings.ankiFormat = format
                report.append(tr("Nota Anki: {0} → {1}.", format.model, format.deck))
                let unsupported = AnkiFieldRenderer.unsupportedMarkers(in: format)
                if !unsupported.isEmpty {
                    report.append(tr("Questi campi per ora restano vuoti: {0}.", unsupported.map { "{\($0)}" }.joined(separator: ", ")))
                }
            }
            refresh()
            Diagnostics.shared.log("Yomitan settings applied")
            errorMessage = report.joined(separator: "\n\n")
        } catch {
            self.report(tr("Non riesco a leggere questo backup di Yomitan: {0}", error.localizedDescription), log: "Yomitan settings failed: \(error)")
        }
    }

    // MARK: Search

    /// - Parameter suggestions: also list words that start with the text (the search box).
    func search(_ text: String, suggestions: Bool = false) async -> SearchResults {
        guard let store else { return SearchResults() }
        let scanner = scanner
        let request = SearchEngine.Request(
            text: text, sortDictionary: settings.sortFrequencyDictionary,
            // Your dictionary order, so definitions under a word follow it.
            priority: Dictionary(dictionaries.map { ($0.title, $0.priority) }, uniquingKeysWith: { a, _ in a }),
            suggest: suggestions)
        return await Task.detached(priority: .userInitiated) {
            SearchEngine.run(request, store: store, scanner: scanner)
        }.value
    }

    private(set) var reverseIndexStatus: String?

    private func indexStatus(_ text: String?) { reverseIndexStatus = text }

    /// Dictionaries imported with version 0.2 have no reverse index yet: build it once.
    func buildMissingReverseIndexes() {
        guard let store else { return }
        Task.detached(priority: .utility) { [weak self] in
            do {
                try store.buildMissingReverseIndexes { p in
                    let pct = p.total > 0 ? min(100, p.done * 100 / p.total) : 0
                    Task { @MainActor [weak self] in self?.indexStatus(tr("Preparo la ricerca per significato in {0}: {1}%", p.dictionaryTitle, pct)) }
                }
                await self?.indexStatus(tr("Preparo la ricerca in kana…"))
                try store.buildMissingKanaIndexes { p in
                    let pct = p.total > 0 ? min(100, p.done * 100 / p.total) : 0
                    Task { @MainActor [weak self] in self?.indexStatus(tr("Preparo la ricerca in kana (イタリアご = いたりあご) in {0}: {1}%", p.dictionaryTitle, pct)) }
                }
            } catch {
                Diagnostics.shared.log("Search indexes not built: \(error)")
            }
            // After the last progress message, which travels the same way.
            Task { @MainActor [weak self] in self?.indexStatus(nil) }
        }
    }

    // MARK: Import

    private struct QueuedFile: Sendable {
        let url: URL
        let opened: Bool
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    private var importQueue: [QueuedFile] = []
    private var importTotal = 0
    private var importDone = 0
    private var imported: [InstalledDictionary] = []
    private var importFailures: [String] = []
    private var importInterrupted = false
    private let importCancel = CancelFlag()

    func importDictionary(from url: URL) { importDictionaries(from: [url]) }

    /// Imports the files one after the other. More can be added while it runs.
    func importDictionaries(from urls: [URL]) {
        guard store != nil, !urls.isEmpty else { return }
        // Permission to read a picked file is asked for now, while the choice is fresh.
        let files = urls.map { QueuedFile(url: $0, opened: PickedFile.open($0)) }
        importQueue += files
        if isImporting {
            importTotal += files.count
            if case .running(let title, let fraction, let position, _) = importStatus {
                importStatus = .running(title: title, fraction: fraction, position: position, total: importTotal)
            }
            return
        }
        importTotal = files.count
        importDone = 0
        imported = []
        importFailures = []
        importInterrupted = false
        importCancel.reset()
        // The screen stays on; if the app is sent to the background anyway and
        // iOS is about to stop it, the import is stopped cleanly first.
        LongWork.begin { [weak self] in
            self?.importInterrupted = true
            self?.importCancel.set()
        }
        runNextImport()
    }

    /// Stops after the file being read; nothing of it is kept.
    func cancelImport() {
        guard isImporting else { return }
        importCancel.set()
    }

    private func runNextImport() {
        guard let store, !importQueue.isEmpty, !importCancel.isSet else { return finishImports() }
        let file = importQueue.removeFirst()
        let position = importDone + 1, total = importTotal
        importStatus = .running(title: file.name, fraction: 0, position: position, total: total)
        Diagnostics.shared.log("Import started: \(file.name)")
        let cancel = importCancel
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<InstalledDictionary, Error>
            do {
                result = .success(try YomitanImporter.importDictionary(at: file.url, into: store, progress: { p in
                    Task { @MainActor [weak self] in self?.importProgressed(title: p.dictionaryTitle, fraction: p.fraction, position: position) }
                }, isCancelled: { cancel.isSet }))
            } catch {
                result = .failure(error)
            }
            PickedFile.close(file.url, opened: file.opened)
            await self?.importEnded(file.name, result)
        }
    }

    private func importProgressed(title: String, fraction: Double, position: Int) {
        // A report that arrives after its file has ended must not move the next file's bar.
        guard case .running = importStatus, position == importDone + 1 else { return }
        importStatus = .running(title: title, fraction: fraction, position: position, total: importTotal)
    }

    private func importEnded(_ name: String, _ result: Result<InstalledDictionary, Error>) {
        importDone += 1
        switch result {
        case .success(let dictionary):
            imported.append(dictionary)
            Diagnostics.shared.log("Imported \(dictionary.title): \(dictionary.termCount) terms, \(dictionary.metaCount) meta, \(dictionary.kanjiCount) kanji")
        case .failure(YomitanImportError.cancelled):
            Diagnostics.shared.log("Import stopped: \(name)")
        case .failure(let error):
            importFailures.append("\(name): \(Self.describe(error))")
            Diagnostics.shared.log("Import failed: \(name): \(error)")
        }
        refresh()
        runNextImport()
    }

    private func finishImports() {
        // Files that were waiting when the import was stopped.
        for file in importQueue { PickedFile.close(file.url, opened: file.opened) }
        importQueue = []
        LongWork.end()
        if imported.count == 1, let one = imported.first {
            importStatus = .finished(summary: one.termCount == 0 && one.kanjiCount > 0
                ? tr("{0}: {1} kanji importati", one.title, one.kanjiCount)
                : tr("{0}: {1} voci importate", one.title, one.termCount))
        } else if imported.count > 1 {
            importStatus = .finished(summary: tr("{0} dizionari importati", imported.count))
        } else {
            importStatus = nil
        }
        var problems = importFailures
        if importInterrupted {
            problems.insert(tr("L'importazione è stata interrotta perché Kotoba è passato in secondo piano. Riprovala tenendo l'app aperta: lo schermo resta acceso da solo."), at: 0)
        }
        if !problems.isEmpty { errorMessage = problems.joined(separator: "\n\n") }
        importTotal = 0
        importDone = 0
        importInterrupted = false
        importCancel.reset()
    }

    func clearImportSummary() {
        if case .finished = importStatus { importStatus = nil }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        switch error {
        case DictionaryStoreError.alreadyInstalled(let title): tr("「{0}」 è già installato.", title)
        case YomitanImportError.missingIndex: tr("Questo file non sembra un dizionario Yomitan (manca index.json).")
        case YomitanImportError.unsupportedFormat(let v): tr("Formato di dizionario {0} non supportato.", v)
        default: tr("Import fallito: {0}", error.localizedDescription)
        }
    }

    // MARK: Dictionaries

    func setEnabled(_ enabled: Bool, for dictionary: InstalledDictionary) {
        guard let store, !isBusy else { return }
        do {
            try store.setEnabled(enabled, dictionary: dictionary.id)
        } catch {
            report(tr("Non riesco a salvare la modifica a «{0}»: {1}", dictionary.title, error.localizedDescription),
                   log: "setEnabled failed for \(dictionary.title): \(error)")
        }
        refresh()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let store, !isBusy else { return }
        var ids = dictionaries.map(\.id)
        // The same as Array.move(fromOffsets:toOffset:), which only SwiftUI has.
        let moving = source.sorted().filter { ids.indices.contains($0) }.map { ids[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        ids.removeAll { moving.contains($0) }
        ids.insert(contentsOf: moving, at: max(0, min(insertAt, ids.count)))
        do {
            try store.reorder(ids)
        } catch {
            report(tr("Non riesco a salvare il nuovo ordine: {0}", error.localizedDescription), log: "Reorder failed: \(error)")
        }
        refresh()
    }

    /// Removes a dictionary. Large ones take seconds, so the work happens
    /// away from the screen; `deleting` says which one meanwhile.
    func delete(_ dictionary: InstalledDictionary) {
        guard let store, !isBusy else { return }
        deleting = dictionary.title
        LongWork.begin {}
        Diagnostics.shared.log("Delete started: \(dictionary.title)")
        Task.detached(priority: .userInitiated) { [weak self] in
            var failure: Error?
            do {
                try store.delete(dictionary: dictionary.id)
            } catch {
                failure = error
            }
            await self?.deleteEnded(dictionary, failure: failure)
        }
    }

    private func deleteEnded(_ dictionary: InstalledDictionary, failure: Error?) {
        deleting = nil
        LongWork.end()
        refresh()
        if let failure {
            report(tr("Non riesco a eliminare «{0}»: {1}", dictionary.title, failure.localizedDescription),
                   log: "Delete failed: \(dictionary.title): \(failure)")
            return
        }
        Diagnostics.shared.log("Deleted \(dictionary.title)")
        // Settings that named it would otherwise point at nothing.
        if settings.collapsedDictionaries.contains(dictionary.title) { settings.collapsedDictionaries.remove(dictionary.title) }
        if settings.sortFrequencyDictionary == dictionary.title { settings.sortFrequencyDictionary = nil }
        toast = tr("«{0}» eliminato", dictionary.title)
    }

    // MARK: Diagnostics

    /// What Impostazioni › Diagnostica shows and copies. `device` holds what
    /// only the phone knows (model, iOS version).
    func diagnosticsReport(device: [(name: String, value: String)] = []) -> DiagnosticsReport {
        let info = Bundle.main.infoDictionary
        var facts: [(name: String, value: String)] = [
            ("Version", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
        ]
        facts += device
        if let expiry = SigningInfo.current {
            facts.append(("Signature expires", ISO8601DateFormatter().string(from: expiry)))
        } else {
            facts.append(("Signature expires", "unknown (no profile in the app)"))
        }
        facts.append(("Storage", SharedStorage.groupID.map { "shared (\($0))" } ?? "private (no App Group: the Share panel opens the app instead)"))
        let database = SharedStorage.folder.appendingPathComponent(SharedStorage.databaseName).path
        let size = ["", "-wal"].reduce(0) { total, suffix in
            total + ((try? FileManager.default.attributesOfItem(atPath: database + suffix)[.size] as? Int) ?? 0)
        }
        facts.append(("Database", store == nil ? "NOT OPEN" : "\(size / 1_048_576) MB, schema \(DictionaryStore.schemaVersion)"))
        facts.append(("Dictionaries", "\(dictionaries.count) (\(dictionaries.filter(\.enabled).count) on), \(dictionaries.map(\.termCount).reduce(0, +)) terms"))
        for d in dictionaries {
            facts.append(("  \(d.enabled ? "✓" : "–") \(d.title)", "rev. \(d.revision), \(d.termCount) terms, \(d.metaCount) meta, \(d.kanjiCount) kanji"))
        }
        facts.append(("Language", "\(settings.language.rawValue) → \(L10n.current.rawValue)"))
        facts.append(("Theme", settings.appearance.theme))
        facts.append(("Anki note", settings.ankiFormat.map { "\($0.model) → \($0.deck), \($0.fields.count) fields" } ?? "not set"))
        facts.append(("Words in Anki", "\(settings.mined.count)"))
        return DiagnosticsReport(facts: facts, log: Diagnostics.shared.entries)
    }
}
