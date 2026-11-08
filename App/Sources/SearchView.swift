import SwiftUI
import KotobaCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var path: [Lookup] = []

    private func search(_ text: String) {
        path = []
        query = text
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ResultsPane(outcome: outcome, query: query, indexStatus: model.reverseIndexStatus,
                            onLookup: { path.append($0) }, onSearch: search)
                    .ignoresSafeArea(edges: .bottom)
                if model.dictionaries.isEmpty {
                    ContentUnavailableView("Nessun dizionario",
                                           systemImage: "square.stack.3d.up.slash",
                                           description: Text("Importa un dizionario Yomitan (.zip) dalla scheda Dizionari."))
                } else if !query.isEmpty && outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationDestination(for: Lookup.self) { lookup in
                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: search)
            }
            .navigationTitle("Cerca")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "日本語 · italiano · English · romaji")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: model.pendingQuery) { _, newValue in
                if let newValue {
                    search(newValue)
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
