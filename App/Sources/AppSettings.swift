import Foundation
import KotobaCore

/// Preferences that survive restarts, saved as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var ankiFormat: AnkiNoteFormat?
    var sortFrequencyDictionary: String?
    /// expression|reading of words already sent to Anki (AnkiMobile can't tell us about duplicates).
    var mined: Set<String> = []
    /// When each was sent, for the "newest first" order of the Parole tab.
    /// Words sent before version 0.16 have no date.
    var minedDates: [String: Date] = [:]
    /// Dictionaries shown closed in results (tap the name to open), e.g. Pixiv.
    var collapsedDictionaries: Set<String> = []
    var appearance = Appearance()
    /// Recent searches, newest first.
    var history: [String] = []
    /// Language of the app's own words.
    var language = AppLanguage.system
    /// Coming back to Kotoba with Japanese text copied searches it.
    var clipboardLookup = true
    /// Coming back to Kotoba right after a screenshot opens it, ready to tap.
    var screenshotLookup = false

    init() {}

    // Written by hand so that settings saved by another version still load.
    // Each part is read on its own: one that is missing, or written in a shape
    // this version cannot read, takes its default instead of taking the list
    // of words sent to Anki down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let unread = decoder.userInfo[Self.unreadParts] as? UnreadParts
        func part<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            do {
                return try c.decodeIfPresent(T.self, forKey: key) ?? fallback
            } catch {
                unread?.names.append(key.stringValue)
                return fallback
            }
        }
        ankiFormat = part(.ankiFormat, nil)
        sortFrequencyDictionary = part(.sortFrequencyDictionary, nil)
        mined = part(.mined, [])
        minedDates = part(.minedDates, [:])
        collapsedDictionaries = part(.collapsedDictionaries, [])
        appearance = part(.appearance, Appearance())
        history = part(.history, [])
        language = part(.language, .system)
        clipboardLookup = part(.clipboardLookup, true)
        screenshotLookup = part(.screenshotLookup, false)
    }

    /// Collects the names of the parts that could not be read.
    final class UnreadParts {
        var names: [String] = []
    }

    private static let unreadParts = CodingUserInfoKey(rawValue: "kotoba.unreadParts")!
    private static let key = "settings.v1"
    /// The saved settings as they were the last time they could not be read in full.
    static let unreadableKey = "settings.v1.unreadable"

    /// The settings in `data`, and the names of the parts that were not
    /// understood ("all" when nothing was).
    static func read(_ data: Data) -> (settings: AppSettings?, unread: [String]) {
        let decoder = JSONDecoder()
        let unread = UnreadParts()
        decoder.userInfo[unreadParts] = unread
        guard let settings = try? decoder.decode(AppSettings.self, from: data) else { return (nil, ["all"]) }
        return (settings, unread.names)
    }

    /// What is saved: nil when nothing is, or when it cannot be read at all.
    static func saved() -> AppSettings? {
        // Shared with the extensions; older versions saved in the app's own defaults.
        guard let data = SharedStorage.defaults.data(forKey: key) ?? UserDefaults.standard.data(forKey: key) else { return nil }
        let (settings, unread) = read(data)
        // The next change saves over what was there. Keep a copy apart, once, and say so in the diary.
        if !unread.isEmpty, SharedStorage.defaults.data(forKey: unreadableKey) != data {
            SharedStorage.defaults.set(data, forKey: unreadableKey)
            Diagnostics.shared.log("Settings not read in full (\(unread.joined(separator: ", "))): a copy is kept as \(unreadableKey)")
        }
        return settings
    }

    static func load() -> AppSettings { saved() ?? AppSettings() }

    /// A note for this word now exists in Anki.
    mutating func markMined(_ key: String, at date: Date = Date()) {
        guard !key.isEmpty else { return }
        if mined.insert(key).inserted { minedDates[key] = date }
    }

    mutating func forgetMined(_ key: String) {
        mined.remove(key)
        minedDates[key] = nil
    }

    mutating func forgetAllMined() {
        mined = []
        minedDates = [:]
    }

    mutating func remember(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        history.removeAll { $0 == q }
        history.insert(q, at: 0)
        if history.count > 40 { history.removeLast(history.count - 40) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { SharedStorage.defaults.set(data, forKey: Self.key) }
    }
}
