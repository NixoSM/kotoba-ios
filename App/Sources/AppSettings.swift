import Foundation
import KotobaCore

/// Preferences that survive restarts, saved as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    var ankiFormat: AnkiNoteFormat?
    var sortFrequencyDictionary: String?
    /// expression|reading of words already sent to Anki (AnkiMobile can't tell us about duplicates).
    var mined: Set<String> = []

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
