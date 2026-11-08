#if canImport(SQLite3)
import Foundation
import ZIPFoundation

public struct ImportProgress: Sendable {
    public var dictionaryTitle: String
    public var banksDone: Int
    public var banksTotal: Int
    public var fraction: Double { banksTotal == 0 ? 0 : Double(banksDone) / Double(banksTotal) }
}

public enum YomitanImportError: Error, Equatable {
    case missingIndex
    case unsupportedFormat(Int)
}

/// Reads a Yomitan dictionary `.zip` and installs it into a `DictionaryStore`.
public enum YomitanImporter {
    public static func importDictionary(
        at url: URL,
        into store: DictionaryStore,
        progress: (ImportProgress) -> Void = { _ in }
    ) throws -> InstalledDictionary {
        let archive = try Archive(url: url, accessMode: .read)

        guard let indexEntry = archive["index.json"] else { throw YomitanImportError.missingIndex }
        let index = try YomitanParser.index(from: read(indexEntry, from: archive))
        guard (1...3).contains(index.formatVersion) else { throw YomitanImportError.unsupportedFormat(index.formatVersion) }

        let banks = archive
            .filter { $0.type == .file }
            .map(\.path)
            .filter { isBank($0, prefix: "term_bank_") || isBank($0, prefix: "term_meta_bank_") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var report = ImportProgress(dictionaryTitle: index.title, banksDone: 0, banksTotal: banks.count)
        progress(report)

        return try store.install(index: index) { session in
            for path in banks {
                guard let entry = archive[path] else { continue }
                let data = try read(entry, from: archive)
                // Parse and insert one bank at a time, then drop it, to keep memory flat.
                try autoreleasepoolIfAvailable {
                    if isBank(path, prefix: "term_bank_") {
                        try session.add(YomitanParser.termBank(from: data, file: path))
                    } else {
                        try session.add(YomitanParser.termMetaBank(from: data, file: path))
                    }
                }
                report.banksDone += 1
                progress(report)
            }
        }
    }

    private static func isBank(_ path: String, prefix: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix(prefix) && name.hasSuffix(".json")
    }

    private static func read(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: false) { chunk in data.append(chunk) }
        return data
    }

    private static func autoreleasepoolIfAvailable(_ body: () throws -> Void) throws {
        #if canImport(ObjectiveC)
        var thrown: Error?
        autoreleasepool {
            do { try body() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        #else
        try body()
        #endif
    }
}
#endif
