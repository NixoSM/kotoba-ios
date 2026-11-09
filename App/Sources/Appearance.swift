import SwiftUI
import CoreText
import KotobaCore

/// How results look: the same knobs as Yomitan's "Appearance" settings,
/// plus a font picker that also accepts your own font files.
struct Appearance: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case comfortable, compact
        var id: Self { self }
        var label: String { self == .comfortable ? tr("Arioso") : tr("Compatto") }
    }

    enum TermDisplay: String, Codable, CaseIterable, Identifiable {
        case ruby, rubyAndReading, termAndReading, termOnly
        var id: Self { self }
        var label: String {
            switch self {
            case .ruby: tr("Furigana sopra")
            case .rubyAndReading: tr("Furigana e lettura")
            case .termAndReading: tr("Parola【lettura】")
            case .termOnly: tr("Solo la parola")
            }
        }
    }

    enum FrequencyDisplay: String, Codable, CaseIterable, Identifiable {
        case average, split, hidden
        var id: Self { self }
        var label: String { switch self { case .average: tr("Media"); case .split: tr("Ogni elenco"); case .hidden: tr("Nascosta") } }
    }

    /// A ThemePalette id, or "auto" (Washi by day, Sumi by night).
    var theme = "auto"
    var bodyFont = "hiragino-sans"
    var headwordFont = "shippori-mincho"
    var fontSize = 17.0
    var lineHeight = 1.5
    var layout = Layout.comfortable
    var termDisplay = TermDisplay.ruby
    var frequency = FrequencyDisplay.average
    var showTags = true
    var showDictionaryNames = true
    var pitchNotation = true
    var pitchNumber = true
    var pitchGraph = false
    var customCSS = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Appearance()
        theme = value(.theme, d.theme)
        bodyFont = value(.bodyFont, d.bodyFont)
        headwordFont = value(.headwordFont, d.headwordFont)
        fontSize = value(.fontSize, d.fontSize)
        lineHeight = value(.lineHeight, d.lineHeight)
        layout = value(.layout, d.layout)
        termDisplay = value(.termDisplay, d.termDisplay)
        frequency = value(.frequency, d.frequency)
        showTags = value(.showTags, d.showTags)
        showDictionaryNames = value(.showDictionaryNames, d.showDictionaryNames)
        pitchNotation = value(.pitchNotation, d.pitchNotation)
        pitchNumber = value(.pitchNumber, d.pitchNumber)
        pitchGraph = value(.pitchGraph, d.pitchGraph)
        customCSS = value(.customCSS, d.customCSS)
    }

    /// Takes over what Yomitan's backup says; leaves the rest as it is.
    mutating func apply(_ y: YomitanSettings.Appearance) {
        if let family = y.fontFamily {
            let font = FontCatalog.match(yomitanFamily: family)
            bodyFont = font
            headwordFont = font
        }
        if let size = y.fontSize, size >= 10, size <= 40 { fontSize = size }
        if let height = y.lineHeight, height >= 0.8, height <= 3 { lineHeight = height }
        if let mode = y.glossaryLayoutMode { layout = mode.hasPrefix("compact") ? .compact : .comfortable }
        switch y.termDisplayMode {
        case "ruby": termDisplay = .ruby
        case "ruby-and-reading": termDisplay = .rubyAndReading
        case "term-and-reading": termDisplay = .termAndReading
        case "term-only": termDisplay = .termOnly
        default: break
        }
        if y.averageFrequency == true {
            frequency = .average
        } else if y.frequencyDisplayMode != nil {
            frequency = .split
        }
        if let v = y.pitchDownstepNotation { pitchNotation = v }
        if let v = y.pitchPositionNotation { pitchNumber = v }
        if let v = y.pitchGraph { pitchGraph = v }
        switch y.theme {
        case "light": theme = "washi"
        case "dark": theme = "sumi"
        default: break
        }
        if let css = y.customCSS, !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { customCSS = css }
    }
}

// MARK: Fonts

struct FontChoice: Identifiable, Hashable {
    struct Face: Hashable {
        var file: String
        var weight: Int
    }

    let id: String
    let name: String
    /// CSS font-family list.
    let css: String
    /// Font files served to the results page (empty for fonts iOS already has).
    var faces: [Face] = []
    /// For the SwiftUI preview of the name.
    var postScriptName: String?
}

enum FontCatalog {
    // Computed so that "Sistema" follows the app language.
    static var builtIn: [FontChoice] { [
        FontChoice(id: "system", name: tr("Sistema"), css: "-apple-system, 'Hiragino Sans'"),
        FontChoice(id: "hiragino-sans", name: "Hiragino Sans", css: "'Hiragino Sans'", postScriptName: "HiraginoSans-W3"),
        FontChoice(id: "hiragino-mincho", name: "Hiragino Mincho", css: "'Hiragino Mincho ProN'", postScriptName: "HiraMinProN-W3"),
        FontChoice(id: "hiragino-maru", name: "Hiragino Maru Gothic", css: "'Hiragino Maru Gothic ProN'", postScriptName: "HiraMaruProN-W4"),
        FontChoice(id: "klee-one", name: "Klee One", css: "'Kotoba Klee One'",
                   faces: [.init(file: "KleeOne-Regular.ttf", weight: 400), .init(file: "KleeOne-SemiBold.ttf", weight: 600)],
                   postScriptName: "KleeOne-Regular"),
        FontChoice(id: "klee-one-semibold", name: "Klee One SemiBold", css: "'Kotoba Klee One SemiBold'",
                   faces: [.init(file: "KleeOne-SemiBold.ttf", weight: 400), .init(file: "KleeOne-SemiBold.ttf", weight: 700)],
                   postScriptName: "KleeOne-SemiBold"),
        FontChoice(id: "shippori-mincho", name: "Shippori Mincho", css: "'Kotoba Shippori Mincho'",
                   faces: [.init(file: "ShipporiMincho-Medium.ttf", weight: 400), .init(file: "ShipporiMincho-Bold.ttf", weight: 700)],
                   postScriptName: "ShipporiMincho-Medium"),
        FontChoice(id: "zen-maru", name: "Zen Maru Gothic", css: "'Kotoba Zen Maru Gothic'",
                   faces: [.init(file: "ZenMaruGothic-Medium.ttf", weight: 400)],
                   postScriptName: "ZenMaruGothic-Medium"),
    ] }

    /// Fonts you added (.ttf/.otf), kept in the app's own folder.
    static var folder: URL {
        let url = SharedStorage.folder.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func custom() -> [FontChoice] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { ["ttf", "otf"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted().map { file in
            let name = (file as NSString).deletingPathExtension
            return FontChoice(id: "file:" + file, name: name, css: "'Kotoba File \(name.replacingOccurrences(of: "'", with: ""))'",
                              faces: [.init(file: file, weight: 400)])
        }
    }

    static func all() -> [FontChoice] { builtIn + custom() }

    #if KOTOBA_EXTENSION
    /// The app gets its fonts from Info.plist; the share panel registers the
    /// app's copies itself, once. A font that fails to load falls back to the
    /// system serif (see `Font.kotoba`).
    static func registerBundledFonts() {
        for file in ["ShipporiMincho-Medium.ttf", "ShipporiMincho-Bold.ttf"] {
            if let url = fileURL(file) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
    #endif

    /// Called on every redraw of the results: lists the Fonts folder only for fonts you added.
    static func choice(_ id: String) -> FontChoice {
        let fonts = builtIn
        if let found = fonts.first(where: { $0.id == id }) { return found }
        return (id.hasPrefix("file:") ? custom().first { $0.id == id } : nil) ?? fonts[1]
    }

    /// Copies a font file into the app and returns its id.
    static func importFont(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        return "file:" + url.lastPathComponent
    }

    /// The bundle that carries the font files. The share panel has none of
    /// its own (they would double the app's size): it reads the app's, which
    /// sits two folders up (Kotoba.app/PlugIns/KotobaShare.appex).
    static let fontBundle: Bundle = {
        #if KOTOBA_EXTENSION
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app) ?? .main
        #else
        return .main
        #endif
    }()

    /// Where a font file lives: bundled with the app, or added by you.
    static func fileURL(_ file: String) -> URL? {
        let name = (file as NSString).lastPathComponent
        if let bundled = fontBundle.url(forResource: (name as NSString).deletingPathExtension,
                                        withExtension: (name as NSString).pathExtension) { return bundled }
        let added = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: added.path) ? added : nil
    }

    /// Yomitan stores a CSS family name; pick the closest font we have.
    static func match(yomitanFamily family: String) -> String {
        let f = family.lowercased()
        if f.contains("klee") { return f.contains("semi") || f.contains("bold") ? "klee-one-semibold" : "klee-one" }
        if f.contains("shippori") { return "shippori-mincho" }
        if f.contains("maru") { return f.contains("zen") ? "zen-maru" : "hiragino-maru" }
        if f.contains("mincho") || f.contains("serif") || f.contains("明朝") { return "hiragino-mincho" }
        if let own = custom().first(where: { f.contains($0.name.lowercased()) }) { return own.id }
        return "hiragino-sans"
    }

    static func fontFaceCSS(_ choices: [FontChoice]) -> String {
        var seen: Set<String> = []
        var css = ""
        for choice in choices where seen.insert(choice.id).inserted {
            let family = choice.css.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            for face in choice.faces {
                let format = face.file.lowercased().hasSuffix(".otf") ? "opentype" : "truetype"
                css += "@font-face{font-family:'\(family)';font-weight:\(face.weight);src:url('\(MediaSchemeHandler.fontURL(face.file))') format('\(format)');}\n"
            }
        }
        return css
    }
}

// MARK: Themes

/// A complete colour set for the app and the results page.
struct ThemePalette: Identifiable, Hashable {
    let id: String
    let name: String
    /// The character on the theme's swatch.
    let mark: String
    let dark: Bool
    let paper: UInt32
    let raised: UInt32
    let ink: UInt32
    let muted: UInt32
    let rule: UInt32
    let accent: UInt32

    static let all: [ThemePalette] = [
        // Paper and sumi ink, vermilion seal: the printed dictionary.
        ThemePalette(id: "washi", name: "Washi", mark: "紙", dark: false,
                     paper: 0xF4EEE3, raised: 0xFBF8F2, ink: 0x1D1A16, muted: 0x8A8276, rule: 0xE2D8C6, accent: 0xC23C24),
        ThemePalette(id: "sumi", name: "Sumi", mark: "墨", dark: true,
                     paper: 0x13110E, raised: 0x1D1A16, ink: 0xECE4D4, muted: 0x8F877B, rule: 0x2C2823, accent: 0xE2603F),
        // Indigo-dyed cloth with gold thread.
        ThemePalette(id: "ai", name: "Aizome", mark: "藍", dark: true,
                     paper: 0x0E1626, raised: 0x152036, ink: 0xE4E8F1, muted: 0x8290AB, rule: 0x233150, accent: 0xE3B25A),
        // Petals on white, plum-coloured ink.
        ThemePalette(id: "sakura", name: "Sakura", mark: "桜", dark: false,
                     paper: 0xFBF2F3, raised: 0xFFF9FA, ink: 0x34262B, muted: 0x9A7F87, rule: 0xEFD8DD, accent: 0xC94F78),
        // Tea-ceremony green, quiet and low contrast.
        ThemePalette(id: "matcha", name: "Matcha", mark: "茶", dark: false,
                     paper: 0xEDEFE2, raised: 0xF6F7EE, ink: 0x1F2619, muted: 0x7B836C, rule: 0xD6DBC4, accent: 0x4F7A28),
        // Old-book sepia, gentle for long reading.
        ThemePalette(id: "kohaku", name: "Kohaku", mark: "琥", dark: false,
                     paper: 0xF1E4C8, raised: 0xF7EDD6, ink: 0x3A2C1A, muted: 0x8C7556, rule: 0xDCC9A3, accent: 0x9A4A1F),
        // Shinjuku at 2 a.m.: violet night, neon pink.
        ThemePalette(id: "yoru", name: "Yoru", mark: "夜", dark: true,
                     paper: 0x0D0C16, raised: 0x171527, ink: 0xE8E6F7, muted: 0x7D7A99, rule: 0x25223B, accent: 0xFF5C8A),
        // Fresh snow, cold blue: crisp and modern.
        ThemePalette(id: "yuki", name: "Yuki", mark: "雪", dark: false,
                     paper: 0xF7F8FA, raised: 0xFFFFFF, ink: 0x15181D, muted: 0x7C8490, rule: 0xE3E6EB, accent: 0x2563C9),
    ]

    /// Shown under the swatch: romanised, or in kanji for Japanese.
    var label: String {
        guard L10n.current == .ja else { return name }
        return ["washi": "和紙", "sumi": "墨", "ai": "藍染", "sakura": "桜", "matcha": "抹茶",
                "kohaku": "琥珀", "yoru": "夜", "yuki": "雪"][id] ?? name
    }

    static func named(_ id: String) -> ThemePalette { all.first { $0.id == id } ?? all[0] }

    /// Light and dark palettes for a setting ("auto" follows the system).
    static func pair(for setting: String) -> (light: ThemePalette, dark: ThemePalette) {
        setting == "auto" ? (named("washi"), named("sumi")) : (named(setting), named(setting))
    }

    static func colorScheme(for setting: String) -> ColorScheme? {
        setting == "auto" ? nil : (named(setting).dark ? .dark : .light)
    }

    /// CSS custom properties for the results page.
    var cssVariables: String {
        func hex(_ v: UInt32) -> String { "#" + String(format: "%06X", v) }
        return "--paper:\(hex(paper));--raised:\(hex(raised));--ink:\(hex(ink));--muted:\(hex(muted));--rule:\(hex(rule));--shu:\(hex(accent));"
            + "--chip:color-mix(in srgb, \(hex(ink)) 7%, transparent);"
    }

    static func css(for setting: String) -> String {
        let p = pair(for: setting)
        if setting == "auto" {
            return ":root{color-scheme:light dark;\(p.light.cssVariables)}@media (prefers-color-scheme: dark){:root{\(p.dark.cssVariables)}}"
        }
        return ":root{color-scheme:\(p.light.dark ? "dark" : "light");\(p.light.cssVariables)}"
    }
}

/// The app's colours, following the chosen theme.
enum Palette {
    nonisolated(unsafe) private static var current = ThemePalette.pair(for: "auto")

    static func apply(_ setting: String) { current = ThemePalette.pair(for: setting) }

    static var paper: Color { color(\.paper) }
    static var raised: Color { color(\.raised) }
    static var ink: Color { color(\.ink) }
    static var muted: Color { color(\.muted) }
    static var rule: Color { color(\.rule) }
    static var shu: Color { color(\.accent) }

    private static func color(_ key: KeyPath<ThemePalette, UInt32>) -> Color {
        let pair = current
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: pair.dark[keyPath: key]) : UIColor(hex: pair.light[keyPath: key]) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// A bundled font for the app's own screens, falling back to the system serif.
    static func kotoba(_ postScriptName: String, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        UIFont(name: postScriptName, size: size) != nil
            ? .custom(postScriptName, size: size, relativeTo: style)
            : .system(size: size, design: .serif)
    }

    static func mincho(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        kotoba(bold ? "ShipporiMincho-Bold" : "ShipporiMincho-Medium", size: size, relativeTo: style)
    }
}
