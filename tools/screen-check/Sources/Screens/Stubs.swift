import SwiftUI
import KotobaCore

// What the screens being checked use from files that cannot be compiled here.
enum Palette {
    static var paper: Color { Color() }
    static var raised: Color { Color() }
    static var ink: Color { Color() }
    static var muted: Color { Color() }
    static var rule: Color { Color() }
    static var shu: Color { Color() }
}
extension Font {
    static func mincho(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font { .body }
}
struct AppearanceView: View { var body: some View { EmptyView() } }
struct ResultsWebView: View {
    let html: String
    let onAction: (URL) -> Void
    var body: some View { EmptyView() }
}
@MainActor final class WordAudio {
    static let shared = WordAudio()
    enum Result { case played, notFound, failed }
    func play(expression: String, reading: String) async -> Result { .failed }
}
extension AppModel {
    static var deviceFacts: [(name: String, value: String)] { [] }
}
