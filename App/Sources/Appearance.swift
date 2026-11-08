import SwiftUI
import KotobaCore

/// How results look: the same knobs as Yomitan's "Appearance" settings,
/// plus a font picker that also accepts your own font files.
struct Appearance: Codable, Equatable {
    enum Theme: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var label: String { switch self { case .system: "Automatico"; case .light: "Carta"; case .dark: "Inchiostro" } }
        var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    }

    enum Layout: String, Codable, CaseIterable, Identifiable {
        case comfortable, compact
        var id: Self { self }
        var label: String { self == .comfortable ? "Arioso" : "Compatto" }
    }

    enum TermDisplay: String, Codable, CaseIterable, Identifiable {
        case ruby, rubyAndReading, termAndReading, termOnly
        var id: Self { self }
        var label: String {
            switch self {
            case .ruby: "Furigana sopra"
            case .rubyAndReading: "Furigana e lettura"
            case .termAndReading: "Parola【lettura】"
            case .termOnly: "Solo la parola"
            }
        }
    }

    enum FrequencyDisplay: String, Codable, CaseIterable, Identifiable {
        case average, split, hidden
        var id: Self { self }
        var label: String { switch self { case .average: "Media"; case .split: "Ogni elenco"; case .hidden: "Nascosta" } }
    }

    var theme = Theme.system
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
        case "light": theme = .light
        case "dark": theme = .dark
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
    static let builtIn: [FontChoice] = [
        FontChoice(id: "system", name: "Sistema", css: "-apple-system, 'Hiragino Sans'"),
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
    ]

    /// Fonts you added (.ttf/.otf), kept in the app's own folder.
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Fonts", isDirectory: true)
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

    static func choice(_ id: String) -> FontChoice {
        all().first { $0.id == id } ?? builtIn[1]
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

    /// Where a font file lives: bundled with the app, or added by you.
    static func fileURL(_ file: String) -> URL? {
        let name = (file as NSString).lastPathComponent
        if let bundled = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
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

// MARK: Palette

/// Sumi ink on washi paper, with one shu (vermilion) accent, like the red
/// marks in a printed dictionary.
enum Palette {
    static let paper = dynamic(light: 0xF4EEE3, dark: 0x13110E)
    static let raised = dynamic(light: 0xFBF8F2, dark: 0x1D1A16)
    static let ink = dynamic(light: 0x1D1A16, dark: 0xECE4D4)
    static let muted = dynamic(light: 0x8A8276, dark: 0x8F877B)
    static let rule = dynamic(light: 0xE2D8C6, dark: 0x2C2823)
    static let shu = dynamic(light: 0xC23C24, dark: 0xE2603F)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
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
