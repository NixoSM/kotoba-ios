import SwiftUI
import KotobaCore

/// A tapped piece of Japanese text to look up, with the sentence around it.
struct Lookup: Hashable {
    var text: String
    var sentence: String
}

/// Results page plus the actions every results screen shares:
/// mining, links to other entries, and tap-to-look-up.
struct ResultsPane: View {
    @Environment(AppModel.self) private var model
    let outcome: AppModel.SearchOutcome
    let query: String
    var indexStatus: String?
    let onLookup: (Lookup) -> Void
    let onSearch: (String) -> Void

    var body: some View {
        ResultsWebView(html: ResultsPage.html(outcome: outcome, query: query, stylesheets: model.stylesheets,
                                              indexStatus: indexStatus, mined: model.settings.mined,
                                              canMine: model.settings.ankiFormat != nil),
                       onAction: handle)
    }

    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "search":
            if let q = value("q") { onSearch(q) }
        case "lookup":
            if let t = value("t") { onLookup(Lookup(text: t, sentence: value("s") ?? t)) }
        case "audio":
            guard let e = value("e"), let r = value("r") else { return }
            Task {
                switch await WordAudio.shared.play(expression: e, reading: r) {
                case .played: break
                case .notFound: model.toast = "Nessuna registrazione per \(e)"
                case .failed: model.toast = "Audio non disponibile (sei online?)"
                }
            }
        case "mine":
            if let section = value("s"), let i = value("i").flatMap(Int.init), let group = outcome.group(section: section, index: i) {
                model.mine(group, sentence: outcome.sentence)
            }
        default:
            break
        }
    }
}

/// Results for a tapped word, pushed on top of the current screen.
struct LookupPage: View {
    @Environment(AppModel.self) private var model
    let lookup: Lookup
    let onLookup: (Lookup) -> Void
    let onSearch: (String) -> Void
    @State private var outcome = AppModel.SearchOutcome()

    var body: some View {
        ResultsPane(outcome: outcome, query: lookup.text, onLookup: onLookup, onSearch: onSearch)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(outcome.direct.first?.matchedText ?? lookup.text)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                var result = await model.search(lookup.text)
                result.sentence = lookup.sentence
                outcome = result
            }
    }
}
