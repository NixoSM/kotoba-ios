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
    }

    func refresh() {
        dictionaries = (try? store?.dictionaries()) ?? []
    }

    func search(_ text: String) async -> [LookupResult] {
        guard let store, !text.isEmpty else { return [] }
        let scanner = scanner
        return await Task.detached(priority: .userInitiated) {
            scanner.scan(text, in: store)
        }.value
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
