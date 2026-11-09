import Foundation
import Observation
import UIKit
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

    let store: DictionaryStore?
    let scanner = TextScanner()

    enum ImportStatus: Equatable {
        case running(title: String, fraction: Double)
        case finished(title: String, terms: Int)
    }

    init() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            store = try DictionaryStore(path: folder.appendingPathComponent("dictionaries.sqlite").path)
        } catch {
            store = nil
            errorMessage = tr("Impossibile aprire il database: {0}", error)
        }
        MediaSchemeHandler.store = store
        Palette.apply(settings.appearance.theme)
        L10n.apply(settings.language)
        refresh()
        buildMissingReverseIndexes()
    }

    private(set) var stylesheets: [String: String] = [:]

    func refresh() {
        dictionaries = (try? store?.dictionaries()) ?? []
        stylesheets = store?.stylesheets() ?? [:]
    }

    /// What a search returns, split by how each headword was found.
    struct SearchOutcome {
        var direct: [HeadwordGroup] = []
        /// Set when Latin input was also valid romaji (taberu → たべる).
        var romajiReading: String?
        var byMeaning: [HeadwordGroup] = []
        /// The text the words were found in, used as the Anki sentence.
        var sentence = ""
        /// Latin input is usually a meaning ("run"), so the romaji reading
        /// (るん) only goes first when it is a common word.
        var romajiFirst = true
        /// How long the search took, shown at the bottom of the results.
        var milliseconds: Int?

        func group(section: String, index: Int) -> HeadwordGroup? {
            let list = section == "meaning" ? byMeaning : direct
            return list.indices.contains(index) ? list[index] : nil
        }
    }

    // MARK: Anki

    /// Opens AnkiMobile's "Add" screen filled with this word.
    func mine(_ group: HeadwordGroup, sentence: String) {
        guard let format = settings.ankiFormat else {
            errorMessage = tr("Prima configura la nota Anki in Impostazioni (puoi importarla dal backup di Yomitan).")
            return
        }
        guard let url = AnkiMobileLink.url(format: format, context: group.miningContext(sentence: sentence)) else {
            errorMessage = tr("Non riesco a creare il collegamento per AnkiMobile.")
            return
        }
        UIApplication.shared.open(url) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.settings.mined.insert(group.minedKey)
            } else {
                self.errorMessage = tr("AnkiMobile non risulta installato.")
            }
        }
    }

    func handle(url: URL) {
        guard url.scheme == "kotoba" else { return }
        switch url.host {
        case "mined":
            toast = tr("Aggiunta ad Anki")
        case "search":
            pendingQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
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

    func search(_ text: String) async -> SearchOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !text.isEmpty else { return SearchOutcome() }
        let scanner = scanner
        let sortDictionary = settings.sortFrequencyDictionary
        // Your dictionary order, so definitions under a word follow it.
        let priority = Dictionary(dictionaries.map { ($0.title, $0.priority) }, uniquingKeysWith: { a, _ in a })
        return await Task.detached(priority: .userInitiated) { () -> SearchOutcome in
            let started = Date()
            var outcome = SearchOutcome(sentence: text)
            if Kana.containsJapanese(text) {
                outcome.direct = HeadwordGroup.group(scanner.scan(text, in: store).map(\.groupInput), priority: priority)
                HeadwordGroup.attachMeta(&outcome.direct, from: store, sortDictionary: sortDictionary)
                outcome.direct = HeadwordGroup.sortedForScan(outcome.direct)
            } else {
                // Romaji is one word: "to run" is English, not とるん.
                if !text.contains(" "), let kana = Romaji.toHiragana(text) {
                    // Only whole-word matches: "sake" should give 酒, not さ + rest.
                    let exact = scanner.scan(kana, in: store).filter { $0.matchedLength == kana.count }
                    if !exact.isEmpty {
                        outcome.romajiReading = kana
                        outcome.direct = HeadwordGroup.group(exact.map(\.groupInput), priority: priority)
                        HeadwordGroup.attachMeta(&outcome.direct, from: store, sortDictionary: sortDictionary)
                        outcome.direct = HeadwordGroup.sortedForScan(outcome.direct)
                    }
                }
                // A match inside a compound (仕立て → ◎仕立屋 "sarto") shows the compound itself.
                var meaningInputs: [(entry: TermEntry, matchedText: String, reasons: [Reason])] = []
                for hit in store.reverseSearch(text, limit: 30) {
                    if let sub = ReverseSearch.subentry(matching: text, glossaryJSON: hit.entry.glossaryJSON),
                       sub != hit.entry.expression {
                        let found = store.entries(matching: sub)
                        if !found.isEmpty {
                            meaningInputs += found.map { ($0, text, []) }
                            continue
                        }
                    }
                    meaningInputs.append((hit.entry, text, []))
                }
                outcome.byMeaning = HeadwordGroup.group(meaningInputs, priority: priority)
                HeadwordGroup.attachMeta(&outcome.byMeaning, from: store, sortDictionary: sortDictionary)
                let romajiRank = outcome.direct.compactMap(\.sortRank).min()
                let meaningRank = outcome.byMeaning.prefix(3).compactMap(\.sortRank).min()
                if !outcome.byMeaning.isEmpty {
                    switch (romajiRank, meaningRank) {
                    case let (r?, m?): outcome.romajiFirst = r <= m
                    case (_?, nil): outcome.romajiFirst = true
                    default: outcome.romajiFirst = false
                    }
                }
            }
            outcome.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
            return outcome
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
}
