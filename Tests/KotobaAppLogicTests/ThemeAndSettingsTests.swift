import XCTest
import KotobaCore
@testable import KotobaAppLogic

final class ThemeContrastTests: XCTestCase {
    private func channels(_ hex: UInt32) -> [Double] {
        [Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)]
    }

    private func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { v -> Double in
            let x = v / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// The WCAG contrast ratio: 4.5 for small text, 3 for icons.
    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The chips (tags, buttons) are the paper with 7% of the ink over it.
    private func chip(_ theme: ThemePalette, on base: UInt32) -> [Double] {
        zip(channels(base), channels(theme.ink)).map { $0 * 0.93 + $1 * 0.07 }
    }

    func testSmallTextIsReadableInEveryTheme() {
        for theme in ThemePalette.all {
            let paper = channels(theme.paper), muted = channels(theme.muted), accent = channels(theme.accent)
            XCTAssertGreaterThanOrEqual(contrast(muted, paper), 4.5, "\(theme.id): grey text on the page")
            XCTAssertGreaterThanOrEqual(contrast(muted, chip(theme, on: theme.paper)), 4.5, "\(theme.id): grey text on a chip")
            XCTAssertGreaterThanOrEqual(contrast(muted, channels(theme.raised)), 4.5, "\(theme.id): grey text on a card")
            XCTAssertGreaterThanOrEqual(contrast(accent, paper), 4.5, "\(theme.id): accent text on the page")
            XCTAssertGreaterThanOrEqual(contrast(accent, chip(theme, on: theme.paper)), 4.5, "\(theme.id): accent on a chip")
            XCTAssertGreaterThanOrEqual(contrast(channels(theme.ink), paper), 7, "\(theme.id): the text itself")
            // The tick of a word already in Anki: paper-coloured on the accent.
            XCTAssertGreaterThanOrEqual(contrast(paper, accent), 3, "\(theme.id): icon on a filled button")
        }
    }

    func testEveryThemeHasItsVariablesInThePage() {
        for theme in ThemePalette.all {
            let css = ThemePalette.css(for: theme.id)
            XCTAssertTrue(css.contains("color-scheme:\(theme.dark ? "dark" : "light")"), theme.id)
            XCTAssertTrue(css.contains(String(format: "--muted:#%06X", theme.muted)), theme.id)
        }
        XCTAssertTrue(ThemePalette.css(for: "auto").contains("prefers-color-scheme: dark"))
        XCTAssertEqual(ThemePalette.named("no-such-theme").id, "washi")
    }
}

final class AppSettingsTests: XCTestCase {
    /// Settings saved by an older version lack the newer keys: they must load, not reset.
    func testOlderSettingsStillLoad() throws {
        let old = #"{"mined":["猫|ねこ"],"history":["猫"],"appearance":{"theme":"sumi","fontSize":19}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.mined, ["猫|ねこ"])
        XCTAssertEqual(settings.appearance.theme, "sumi")
        XCTAssertEqual(settings.appearance.fontSize, 19)
        XCTAssertEqual(settings.appearance.layout, .comfortable)
        XCTAssertEqual(settings.language, .system)
        XCTAssertTrue(settings.clipboardLookup)
        XCTAssertNil(settings.ankiFormat)
    }

    func testAWrongValueDoesNotLoseTheRest() throws {
        let odd = #"{"mined":["a|b"],"language":"klingon","appearance":{"layout":"sideways","theme":"yuki"},"history":"none"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        XCTAssertEqual(settings.mined, ["a|b"])
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.appearance.theme, "yuki")
        XCTAssertEqual(settings.appearance.layout, .comfortable)
        XCTAssertEqual(settings.history, [])
    }

    /// The list of words sent to Anki has no other copy: a part written in a
    /// shape this version cannot read must not reset it, nor anything else.
    func testAPartInAnotherShapeDoesNotLoseTheRest() throws {
        let odd = #"{"mined":["猫|ねこ"],"ankiFormat":"deck","collapsedDictionaries":7,"sortFrequencyDictionary":["JPDB"],"history":["猫"],"minedDates":{"猫|ねこ":"ieri"}}"#
        let (settings, unread) = AppSettings.read(Data(odd.utf8))
        XCTAssertEqual(settings?.mined, ["猫|ねこ"])
        XCTAssertEqual(settings?.history, ["猫"])
        XCTAssertNil(settings?.ankiFormat)
        XCTAssertEqual(settings?.collapsedDictionaries, [])
        XCTAssertEqual(unread.sorted(), ["ankiFormat", "collapsedDictionaries", "minedDates", "sortFrequencyDictionary"])

        let words = #"{"mined":{"猫|ねこ":true},"history":["猫"]}"#
        let second = AppSettings.read(Data(words.utf8))
        XCTAssertEqual(second.settings?.mined, [])
        XCTAssertEqual(second.settings?.history, ["猫"])
        XCTAssertEqual(second.unread, ["mined"])

        let fine = AppSettings.read(Data(#"{"mined":["a|b"]}"#.utf8))
        XCTAssertEqual(fine.unread, [], "a missing part is not an unread one")
    }

    func testSettingsThatCannotBeReadAreKeptApart() throws {
        let defaults = SharedStorage.defaults
        let before = defaults.data(forKey: "settings.v1")
        defer {
            defaults.set(before, forKey: "settings.v1")
            defaults.removeObject(forKey: AppSettings.unreadableKey)
        }
        Diagnostics.shared.clear()

        // Not settings at all: nothing is loaded, and the app keeps the ones it is using.
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "settings.v1")
        XCTAssertNil(AppSettings.saved())
        XCTAssertEqual(AppSettings.load(), AppSettings())
        XCTAssertEqual(defaults.data(forKey: AppSettings.unreadableKey), garbage)
        XCTAssertEqual(Diagnostics.shared.entries.filter { $0.contains("Settings not read in full (all)") }.count, 1)
        // Coming back to the app reads them again: one copy, one line in the diary.
        XCTAssertNil(AppSettings.saved())
        XCTAssertEqual(Diagnostics.shared.entries.filter { $0.contains("Settings not read in full") }.count, 1)

        // One part in another shape: the rest loads, and the whole is kept before the next save replaces it.
        let partly = Data(#"{"mined":["猫|ねこ"],"ankiFormat":"deck"}"#.utf8)
        defaults.set(partly, forKey: "settings.v1")
        var loaded = try XCTUnwrap(AppSettings.saved())
        XCTAssertEqual(loaded.mined, ["猫|ねこ"])
        XCTAssertEqual(defaults.data(forKey: AppSettings.unreadableKey), partly)
        XCTAssertTrue(Diagnostics.shared.entries.contains { $0.contains("Settings not read in full (ankiFormat)") })
        loaded.remember("猫")
        loaded.save()
        XCTAssertEqual(AppSettings.saved(), loaded)
        XCTAssertEqual(defaults.data(forKey: AppSettings.unreadableKey), partly, "the copy stays after the save")
        Diagnostics.shared.clear()
    }

    func testSavedSettingsComeBack() throws {
        var settings = AppSettings()
        settings.remember("  食べる ")
        settings.remember("猫")
        settings.remember("食べる")
        settings.remember("猿轡 (さるぐつわ) gag, reading higurashi!")
        settings.mined.insert("猫|ねこ")
        settings.appearance.theme = "matcha"
        settings.save()
        let loaded = AppSettings.load()
        XCTAssertEqual(loaded.history, ["食べる", "猫"], "newest first, each once, trimmed, no long pasted text")
        XCTAssertEqual(loaded, settings)
    }

    func testHistoryKeepsTheLatestForty() {
        var settings = AppSettings()
        for i in 0..<60 { settings.remember("parola \(i)") }
        XCTAssertEqual(settings.history.count, 40)
        XCTAssertEqual(settings.history.first, "parola 59")
        settings.remember("   ")
        XCTAssertEqual(settings.history.count, 40)
    }
}

final class TranslationTests: XCTestCase {
    func testPlaceholdersAreFilledInEveryLanguage() {
        defer { L10n.apply(.it) }
        for language in [AppLanguage.it, .en, .ja] {
            L10n.apply(language)
            let text = tr("Parole che iniziano con «{0}»", "食べ")
            XCTAssertTrue(text.contains("食べ"), "\(language): \(text)")
            XCTAssertFalse(text.contains("{0}"), "\(language): \(text)")
        }
        L10n.apply(.en)
        XCTAssertEqual(tr("negativo"), "negative")
        XCTAssertEqual(Reason.whileDoing.italianLabel, "while")
    }
}
