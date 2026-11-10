import SwiftUI
import CoreText
import Observation

/// The colours in use. `Palette` reads them from here, which tells SwiftUI
/// which screens used a colour: when the theme changes it repaints those,
/// instead of the whole app being rebuilt (and losing its place) as before.
@Observable
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()
    fileprivate(set) var light = ThemePalette.named("washi")
    fileprivate(set) var dark = ThemePalette.named("sumi")
}

/// The app's colours, following the chosen theme.
enum Palette {
    static func apply(_ setting: String) {
        let pair = ThemePalette.pair(for: setting)
        let store = ThemeStore.shared
        if store.light != pair.light { store.light = pair.light }
        if store.dark != pair.dark { store.dark = pair.dark }
    }

    static var paper: Color { color(\.paper) }
    static var raised: Color { color(\.raised) }
    static var ink: Color { color(\.ink) }
    static var muted: Color { color(\.muted) }
    static var rule: Color { color(\.rule) }
    static var shu: Color { color(\.accent) }

    private static func color(_ key: KeyPath<ThemePalette, UInt32>) -> Color {
        let store = ThemeStore.shared
        let light = store.light[keyPath: key], dark = store.dark[keyPath: key]
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension ThemePalette {
    static func colorScheme(for setting: String) -> ColorScheme? {
        setting == "auto" ? nil : (named(setting).dark ? .dark : .light)
    }
}

extension FontCatalog {
    /// Copies a font file into the app and returns its id.
    static func importFont(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        return "file:" + url.lastPathComponent
    }
}

#if KOTOBA_EXTENSION
extension FontCatalog {
    /// The app gets its fonts from Info.plist; the share panel registers the
    /// app's copies itself, once. A font that fails to load falls back to the
    /// system serif (see `Font.kotoba`).
    static func registerBundledFonts() {
        for file in ["ShipporiMincho-Medium.ttf", "ShipporiMincho-Bold.ttf"] {
            if let url = fileURL(file) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
#endif

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
