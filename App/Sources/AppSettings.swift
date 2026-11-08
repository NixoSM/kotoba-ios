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

    init() {}

    // Written by hand so that settings saved by older versions, which lack
    // newer keys, still load instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ankiFormat = try c.decodeIfPresent(AnkiNoteFormat.self, forKey: .ankiFormat)
        sortFrequencyDictionary = try c.decodeIfPresent(String.self, forKey: .sortFrequencyDictionary)
        mined = try c.decodeIfPresent(Set<String>.self, forKey: .mined) ?? []
        collapsedDictionaries = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedDictionaries) ?? []
    }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
