import Foundation
import Observation
import KotobaCore

/// Owns the dictionary store and everything the screens share.
@MainActor
@Observable
final class AppModel {
    private(set) var dictionaries: [InstalledDictionary] = []
    private(set) var importStatus: ImportStatus?
    var errorMessage: String?

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

    func refresh() {
        dictionaries = (try? store?.dictionaries()) ?? []
    }

    /// What a search returns, split by how each headword was found.
    struct SearchOutcome {
        var direct: [HeadwordGroup] = []
        /// Set when Latin input was also valid romaji (taberu → たべる).
        var romajiReading: String?
        var byMeaning: [HeadwordGroup] = []
    }

    func search(_ text: String) async -> SearchOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !text.isEmpty else { return SearchOutcome() }
        let scanner = scanner
        return await Task.detached(priority: .userInitiated) { () -> SearchOutcome in
            if Kana.containsJapanese(text) {
                return SearchOutcome(direct: HeadwordGroup.group(scanner.scan(text, in: store).map(\.groupInput)))
            }
            var outcome = SearchOutcome()
            if let kana = Romaji.toHiragana(text) {
                // Only whole-word matches: "sake" should give 酒, not さ + rest.
                let exact = scanner.scan(kana, in: store).filter { $0.matchedLength == kana.count }
                if !exact.isEmpty {
                    outcome.romajiReading = kana
                    outcome.direct = HeadwordGroup.group(exact.map(\.groupInput))
                }
            }
            outcome.byMeaning = HeadwordGroup.group(store.reverseSearch(text).map { ($0.entry, text, []) })
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
