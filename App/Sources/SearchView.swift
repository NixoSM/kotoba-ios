import SwiftUI
import KotobaCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var outcome = AppModel.SearchOutcome()

    private var page: String {
        ResultsPage.html(outcome: outcome, query: query, stylesheets: model.stylesheets,
                         indexStatus: model.reverseIndexStatus, mined: model.settings.mined,
                         canMine: model.settings.ankiFormat != nil)
    }

    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "search":
            if let q = value("q") { query = q }
        case "mine":
            if let section = value("s"), let i = value("i").flatMap(Int.init), let group = outcome.group(section: section, index: i) {
                model.mine(group, sentence: outcome.sentence)
            }
        default:
            break
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ResultsWebView(html: page, onAction: handle)
                    .ignoresSafeArea(edges: .bottom)
                if model.dictionaries.isEmpty {
                    ContentUnavailableView("Nessun dizionario",
                                           systemImage: "square.stack.3d.up.slash",
                                           description: Text("Importa un dizionario Yomitan (.zip) dalla scheda Dizionari."))
                } else if !query.isEmpty && outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Cerca")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "日本語 · italiano · English · romaji")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: model.pendingQuery) { _, newValue in
                if let newValue {
                    query = newValue
                    model.pendingQuery = nil
                }
            }
            .task(id: query) {
                // Small pause so we don't search on every keystroke.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                outcome = await model.search(query)
            }
        }
    }
}
