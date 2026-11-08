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
        didSet { settings.save() }
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
            errorMessage = "Impossibile aprire il database: \(error)"
        }
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

        func group(section: String, index: Int) -> HeadwordGroup? {
            let list = section == "meaning" ? byMeaning : direct
            return list.indices.contains(index) ? list[index] : nil
        }
    }

    // MARK: Anki

    /// Opens AnkiMobile's "Add" screen filled with this word.
    func mine(_ group: HeadwordGroup, sentence: String) {
        guard let format = settings.ankiFormat else {
            errorMessage = "Prima configura la nota Anki in Impostazioni (puoi importarla dal backup di Yomitan)."
            return
        }
        guard let url = AnkiMobileLink.url(format: format, context: group.miningContext(sentence: sentence)) else {
            errorMessage = "Non riesco a creare il collegamento per AnkiMobile."
            return
        }
        UIApplication.shared.open(url) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.settings.mined.insert(group.minedKey)
            } else {
                self.errorMessage = "AnkiMobile non risulta installato."
            }
        }
    }

    func handle(url: URL) {
        guard url.scheme == "kotoba" else { return }
        switch url.host {
        case "mined":
            toast = "Aggiunta ad Anki"
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
                report.append("Ordine e attivazione applicati a \(result.applied) dizionari.")
                if !result.notInstalled.isEmpty {
                    report.append("Non ancora importati: \(result.notInstalled.joined(separator: ", ")).")
                }
            }
            if let sort = parsed.sortFrequencyDictionary {
                settings.sortFrequencyDictionary = sort
                report.append("Ordinamento per frequenza: \(sort).")
            }
            if let format = parsed.ankiTermFormat {
                settings.ankiFormat = format
                report.append("Nota Anki: \(format.model) → \(format.deck).")
                let unsupported = AnkiFieldRenderer.unsupportedMarkers(in: format)
                if !unsupported.isEmpty {
                    report.append("Questi campi per ora restano vuoti: \(unsupported.map { "{\($0)}" }.joined(separator: ", ")).")
                }
            }
            refresh()
            errorMessage = report.joined(separator: "\n\n")
        } catch {
            errorMessage = "Non riesco a leggere questo backup di Yomitan: \(error.localizedDescription)"
        }
    }

    func search(_ text: String) async -> SearchOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !text.isEmpty else { return SearchOutcome() }
        let scanner = scanner
        let sortDictionary = settings.sortFrequencyDictionary
        return await Task.detached(priority: .userInitiated) { () -> SearchOutcome in
            var outcome = SearchOutcome(sentence: text)
            if Kana.containsJapanese(text) {
                outcome.direct = HeadwordGroup.group(scanner.scan(text, in: store).map(\.groupInput))
            } else {
                if let kana = Romaji.toHiragana(text) {
                    // Only whole-word matches: "sake" should give 酒, not さ + rest.
                    let exact = scanner.scan(kana, in: store).filter { $0.matchedLength == kana.count }
                    if !exact.isEmpty {
                        outcome.romajiReading = kana
                        outcome.direct = HeadwordGroup.group(exact.map(\.groupInput))
                    }
                }
                outcome.byMeaning = HeadwordGroup.group(store.reverseSearch(text).map { ($0.entry, text, []) })
                HeadwordGroup.attachMeta(&outcome.byMeaning, from: store, sortDictionary: sortDictionary)
            }
            HeadwordGroup.attachMeta(&outcome.direct, from: store, sortDictionary: sortDictionary)
            outcome.direct = HeadwordGroup.sortedForScan(outcome.direct)
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
                Task { @MainActor in self?.reverseIndexStatus = "Preparo la ricerca per significato in \(p.dictionaryTitle): \(pct)%" }
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
        case DictionaryStoreError.alreadyInstalled(let title): "「\(title)」 è già installato."
        case YomitanImportError.missingIndex: "Questo file non sembra un dizionario Yomitan (manca index.json)."
        case YomitanImportError.unsupportedFormat(let v): "Formato di dizionario \(v) non supportato."
        default: "Import fallito: \(error.localizedDescription)"
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
