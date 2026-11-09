import Foundation
import KotobaCore

/// Preferences that survive restarts, saved as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var ankiFormat: AnkiNoteFormat?
    var sortFrequencyDictionary: String?
    /// expression|reading of words already sent to Anki (AnkiMobile can't tell us about duplicates).
    var mined: Set<String> = []
    /// Dictionaries shown closed in results (tap the name to open), e.g. Pixiv.
    var collapsedDictionaries: Set<String> = []
    var appearance = Appearance()
    /// Recent searches, newest first.
    var history: [String] = []
    /// Language of the app's own words.
    var language = AppLanguage.system

    init() {}

    // Written by hand so that settings saved by older versions, which lack
    // newer keys, still load instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ankiFormat = try c.decodeIfPresent(AnkiNoteFormat.self, forKey: .ankiFormat)
        sortFrequencyDictionary = try c.decodeIfPresent(String.self, forKey: .sortFrequencyDictionary)
        mined = try c.decodeIfPresent(Set<String>.self, forKey: .mined) ?? []
        collapsedDictionaries = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedDictionaries) ?? []
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? Appearance()
        history = (try? c.decodeIfPresent([String].self, forKey: .history)) ?? []
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? .system
    }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    mutating func remember(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        history.removeAll { $0 == q }
        history.insert(q, at: 0)
        if history.count > 40 { history.removeLast(history.count - 40) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
