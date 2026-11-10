import Foundation
import Observation
import UIKit
#if !KOTOBA_EXTENSION
import Photos
#endif
import KotobaCore

/// Owns the dictionary store and everything the screens share.
@MainActor
@Observable
final class AppModel {
    private(set) var dictionaries: [InstalledDictionary] = []
    private(set) var importStatus: ImportStatus?
    var errorMessage: String?
    /// Short confirmation shown at the bottom of the screen.
    var toast: String?
    var settings = AppSettings.load() {
        didSet {
            settings.save()
            if settings.appearance.theme != oldValue.appearance.theme { Palette.apply(settings.appearance.theme) }
            if settings.language != oldValue.language { L10n.apply(settings.language) }
        }
    }
    /// Set from outside (kotoba://search?q=…, camera) to run a search.
    var pendingQuery: String?
    /// The tab on screen: 0 search, 1 camera, 4 from PC, 2 dictionaries, 3 settings.
    var selectedTab = 0
    /// What the camera tab should open with.
    enum CameraRequest: Equatable { case lens, screenshot(String) }
    var cameraRequest: CameraRequest?

    let store: DictionaryStore?
    let scanner = TextScanner()

    var isImporting: Bool { if case .running = importStatus { true } else { false } }

    enum ImportStatus: Equatable {
        case running(title: String, fraction: Double)
        case finished(title: String, terms: Int)
    }

    init() {
        do {
            #if KOTOBA_EXTENSION
            let folder = SharedStorage.folder
            #else
            let folder = SharedStorage.migrateToSharedFolder()
            #endif
            store = try DictionaryStore(path: folder.appendingPathComponent(SharedStorage.databaseName).path)
        } catch {
            store = nil
            errorMessage = tr("Impossibile aprire il database: {0}", error)
        }
        MediaSchemeHandler.store = store
        Palette.apply(settings.appearance.theme)
        L10n.apply(settings.language)
        refresh()
        #if !KOTOBA_EXTENSION
        buildMissingReverseIndexes()
        #endif
    }

    private(set) var stylesheets: [String: String] = [:] {
        didSet { if stylesheets != oldValue { dictionaryCSS = ResultsPage.scopedCSS(stylesheets) } }
    }
    /// `stylesheets` rewritten for the results page, done once instead of on every redraw.
    private(set) var dictionaryCSS = ""

    func refresh() {
        dictionaries = (try? store?.dictionaries()) ?? []
        stylesheets = store?.stylesheets() ?? [:]
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
            if let key = MinedLink.minedKey(from: url) { settings.mined.insert(key) }
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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
            errorMessage = report.joined(separator: "\n\n")
        } catch {
            errorMessage = tr("Non riesco a leggere questo backup di Yomitan: {0}", error.localizedDescription)
        }
    }

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

    /// Dictionaries imported with version 0.2 have no reverse index yet: build it once.
    func buildMissingReverseIndexes() {
        guard let store else { return }
        Task.detached(priority: .utility) { [weak self] in
            try? store.buildMissingReverseIndexes { p in
                let pct = p.total > 0 ? min(100, p.done * 100 / p.total) : 0
                Task { @MainActor in self?.reverseIndexStatus = tr("Preparo la ricerca per significato in {0}: {1}%", p.dictionaryTitle, pct) }
            }
            await MainActor.run { self?.reverseIndexStatus = tr("Preparo la ricerca in kana…") }
            try? store.buildMissingKanaIndexes { p in
                let pct = p.total > 0 ? min(100, p.done * 100 / p.total) : 0
                Task { @MainActor in self?.reverseIndexStatus = tr("Preparo la ricerca in kana (イタリアご = いたりあご) in {0}: {1}%", p.dictionaryTitle, pct) }
            }
            await MainActor.run { self?.reverseIndexStatus = nil }
        }
    }

    func importDictionary(from url: URL) {
        guard let store else { return }
        importStatus = .running(title: url.deletingPathExtension().lastPathComponent, fraction: 0)
        Task.detached(priority: .userInitiated) { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let installed = try YomitanImporter.importDictionary(at: url, into: store) { p in
                    Task { @MainActor in self?.importStatus = .running(title: p.dictionaryTitle, fraction: p.fraction) }
                }
                await MainActor.run {
                    self?.importStatus = .finished(title: installed.title, terms: installed.termCount)
                    self?.refresh()
                }
            } catch {
                await MainActor.run {
                    self?.importStatus = nil
                    self?.errorMessage = Self.describe(error)
                }
            }
        }
    }

    nonisolated private static func describe(_ error: Error) -> String {
        switch error {
        case DictionaryStoreError.alreadyInstalled(let title): tr("「{0}」 è già installato.", title)
        case YomitanImportError.missingIndex: tr("Questo file non sembra un dizionario Yomitan (manca index.json).")
        case YomitanImportError.unsupportedFormat(let v): tr("Formato di dizionario {0} non supportato.", v)
        default: tr("Import fallito: {0}", error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool, for dictionary: InstalledDictionary) {
        try? store?.setEnabled(enabled, dictionary: dictionary.id)
        refresh()
    }

    func move(from source: IndexSet, to destination: Int) {
        var ids = dictionaries.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try? store?.reorder(ids)
        refresh()
    }

    func delete(_ dictionary: InstalledDictionary) {
        try? store?.delete(dictionary: dictionary.id)
        refresh()
    }

    // MARK: Quick lookup (app only)

    #if !KOTOBA_EXTENSION
    /// Called every time Kotoba comes to the front.
    func becameActive() {
        // The share panel may have changed settings (words sent to Anki).
        let saved = AppSettings.load()
        if saved != settings { settings = saved }
        if let action = QuickAction.takePending() {
            perform(action)
            return
        }
        if settings.clipboardLookup, searchClipboard(force: false) { return }
        if settings.screenshotLookup { openRecentScreenshot() }
    }

    func perform(_ action: QuickAction) {
        switch action {
        case .clipboard:
            searchClipboard(force: true)
        case .lens:
            cameraRequest = .lens
            selectedTab = 1
        }
    }

    private static let clipboardKey = "lastClipboardChange"

    /// Searches the clipboard if it holds Japanese text copied since last time
    /// (or always, when asked by a shortcut). Returns whether it searched.
    @discardableResult
    func searchClipboard(force: Bool) -> Bool {
        let board = UIPasteboard.general
        let defaults = UserDefaults.standard
        // changeCount can be read without the paste permission prompt.
        guard force || board.changeCount != defaults.integer(forKey: Self.clipboardKey) else { return false }
        defaults.set(board.changeCount, forKey: Self.clipboardKey)
        guard board.hasStrings else {
            if force { toast = tr("Negli appunti non c'è testo") }
            return false
        }
        let text = (board.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= (force ? 300 : 80), force || Kana.containsJapanese(text) else {
            if force { toast = tr("Negli appunti non c'è testo") }
            return false
        }
        pendingQuery = text
        selectedTab = 0
        toast = tr("Dagli appunti")
        return true
    }

    private static let screenshotKey = "lastScreenshotSeen"

    /// Opens a screenshot taken in the last two minutes that you haven't seen in Kotoba yet.
    func openRecentScreenshot() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited, let asset = Self.latestScreenshot(),
              let date = asset.creationDate, Date().timeIntervalSince(date) < 120,
              UserDefaults.standard.string(forKey: Self.screenshotKey) != asset.localIdentifier else { return }
        UserDefaults.standard.set(asset.localIdentifier, forKey: Self.screenshotKey)
        cameraRequest = .screenshot(asset.localIdentifier)
        selectedTab = 1
    }

    nonisolated static func latestScreenshot() -> PHAsset? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: options).firstObject
    }
    #endif
}
