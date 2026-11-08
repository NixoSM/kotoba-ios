import SwiftUI
import KotobaCore

/// One headword with every dictionary's definitions merged under it
/// (Yomitan's "merge" result mode, which is how you have it set up).
struct HeadwordGroup: Identifiable {
    let id: String
    let expression: String
    let reading: String
    let matchedText: String
    let reasons: [Reason]
    /// HTML fragments per dictionary, in dictionary priority order.
    var definitions: [(dictionary: String, items: [String])]

    static func group(_ results: [(entry: TermEntry, matchedText: String, reasons: [Reason])]) -> [HeadwordGroup] {
        var order: [String] = []
        var groups: [String: HeadwordGroup] = [:]
        for r in results {
            let key = r.entry.expression + "|" + r.entry.reading
            let items = GlossaryHTML.items(fromJSON: r.entry.glossaryJSON)
            if groups[key] == nil {
                order.append(key)
                groups[key] = HeadwordGroup(id: key, expression: r.entry.expression, reading: r.entry.reading,
                                            matchedText: r.matchedText, reasons: r.reasons, definitions: [])
            }
            if let i = groups[key]!.definitions.firstIndex(where: { $0.dictionary == r.entry.dictionary }) {
                groups[key]!.definitions[i].items += items
            } else {
                groups[key]!.definitions.append((r.entry.dictionary, items))
            }
        }
        return order.compactMap { groups[$0] }
    }
}

extension LookupResult {
    var groupInput: (entry: TermEntry, matchedText: String, reasons: [Reason]) {
        (entry, matchedText, deinflection.reasons)
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var outcome = AppModel.SearchOutcome()

    private var page: String {
        ResultsPage.html(outcome: outcome, query: query, stylesheets: model.stylesheets,
                         indexStatus: model.reverseIndexStatus)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ResultsWebView(html: page) { query = $0 }
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
            .task(id: query) {
                // Small pause so we don't search on every keystroke.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                outcome = await model.search(query)
            }
        }
    }
}
