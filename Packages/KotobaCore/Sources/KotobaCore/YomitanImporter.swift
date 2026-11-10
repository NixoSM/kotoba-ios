#if canImport(SQLite3) || canImport(CSQLite3)
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
    /// Stopped on request: nothing was installed.
    case cancelled
    /// The .zip cannot be read: damaged, or a download that did not finish.
    /// Carries the archive library's own word for it, for the diary.
    case unreadableZip(String)
}

/// Reads a Yomitan dictionary `.zip` and installs it into a `DictionaryStore`.
public enum YomitanImporter {
    /// How many pictures count as one step of the progress bar.
    private static let mediaStep = 200

    /// - Parameter isCancelled: asked between files; answering true stops the
    ///   import and leaves nothing behind.
    public static func importDictionary(
        at url: URL,
        into store: DictionaryStore,
        progress: (ImportProgress) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) throws -> InstalledDictionary {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw YomitanImportError.unreadableZip("\(error)")
        }

        // One pass over the file list. `archive[path]` starts again from the
        // first file every time, so asking it for each of N pictures took N²
        // steps: a dictionary with 8,000 images needed minutes just to find them.
        var indexEntry: Entry?
        var stylesEntry: Entry?
        var banks: [Entry] = []
        var media: [Entry] = []
        for entry in archive where entry.type == .file {
            let path = entry.path
            if path == "index.json" {
                indexEntry = entry
            } else if path == "styles.css" {
                stylesEntry = entry
            } else if isBank(path, prefix: "term_bank_") || isBank(path, prefix: "term_meta_bank_")
                        || isBank(path, prefix: "kanji_bank_") || isBank(path, prefix: "kanji_meta_bank_") {
                banks.append(entry)
            } else if isMedia(path) {
                media.append(entry)
            }
        }
        banks.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard let indexEntry else { throw YomitanImportError.missingIndex }
        let index = try YomitanParser.index(from: read(indexEntry, from: archive))
        guard (1...3).contains(index.formatVersion) else { throw YomitanImportError.unsupportedFormat(index.formatVersion) }

        let mediaSteps = (media.count + mediaStep - 1) / mediaStep
        var report = ImportProgress(dictionaryTitle: index.title, banksDone: 0, banksTotal: banks.count + mediaSteps)
        progress(report)

        var styles = ""
        if let stylesEntry {
            styles = String(decoding: try read(stylesEntry, from: archive), as: UTF8.self)
        }

        return try store.install(index: index, styles: styles) { session in
            for entry in banks {
                if isCancelled() { throw YomitanImportError.cancelled }
                let path = entry.path
                let data = try read(entry, from: archive)
                // Parse and insert one bank at a time, then drop it, to keep memory flat.
                try autoreleasepoolIfAvailable {
                    if isBank(path, prefix: "term_bank_") {
                        try session.add(YomitanParser.termBankWithIndexText(from: data, file: path))
                    } else if isBank(path, prefix: "kanji_bank_") {
                        try session.add(YomitanParser.kanjiBank(from: data, file: path))
                    } else if isBank(path, prefix: "kanji_meta_bank_") {
                        try session.add(YomitanParser.kanjiMetaBank(from: data, file: path))
                    } else {
                        try session.add(YomitanParser.termMetaBank(from: data, file: path))
                    }
                }
                report.banksDone += 1
                progress(report)
            }
            for (i, entry) in media.enumerated() {
                if i % mediaStep == 0, isCancelled() { throw YomitanImportError.cancelled }
                try autoreleasepoolIfAvailable {
                    try session.addMedia(path: entry.path, data: read(entry, from: archive))
                }
                if (i + 1) % mediaStep == 0 || i == media.count - 1 {
                    report.banksDone += 1
                    progress(report)
                }
            }
        }
    }

    private static let mediaExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "tif", "tiff"]

    private static func isMedia(_ path: String) -> Bool {
        mediaExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static func isBank(_ path: String, prefix: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix(prefix) && name.hasSuffix(".json")
    }

    private static func read(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: false) { chunk in data.append(chunk) }
        } catch {
            // A file inside that does not match its checksum, or stops short.
            throw YomitanImportError.unreadableZip("\(entry.path): \(error)")
        }
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
