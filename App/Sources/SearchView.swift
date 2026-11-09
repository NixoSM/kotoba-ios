import SwiftUI
import KotobaCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var path: [Lookup] = []
    @State private var searching = false

    private func search(_ text: String) {
        path = []
        query = text
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Palette.paper.ignoresSafeArea()
                if model.dictionaries.isEmpty {
                    EmptyLibrary()
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    HomeView(onSearch: search)
                } else if !searching && outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    NoResults(query: query)
                } else {
                    ResultsPane(outcome: outcome, query: query, indexStatus: model.reverseIndexStatus,
                                onLookup: { path.append($0) }, onSearch: search)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationDestination(for: Lookup.self) { lookup in
                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: search)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.paper, for: .navigationBar)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("日本語 · italiano · English · romaji"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: model.pendingQuery) { _, newValue in
                if let newValue {
                    search(newValue)
                    model.pendingQuery = nil
                }
            }
            .task(id: query) {
                searching = true
                // Small pause so we don't search on every keystroke.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                outcome = await model.search(query)
                searching = false
                // Remember it once you stop typing and something was found.
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, !outcome.direct.isEmpty || !outcome.byMeaning.isEmpty else { return }
                model.settings.remember(query)
            }
        }
    }
}

/// What you see before typing: the wordmark and your recent searches.
private struct HomeView: View {
    @Environment(AppModel.self) private var model
    let onSearch: (String) -> Void

    private var totalTerms: Int { model.dictionaries.filter(\.enabled).map(\.termCount).reduce(0, +) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 14) {
                    Rectangle().fill(Palette.shu).frame(width: 4, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("言葉").font(.mincho(44, bold: true)).foregroundStyle(Palette.ink)
                        Text(tr("{0} dizionari · {1} voci", model.dictionaries.filter(\.enabled).count, totalTerms.formatted(.number.notation(.compactName))))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 12)

                if model.settings.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("Prova a cercare"), systemImage: "sparkle")
                            .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Palette.shu)
                        ForEach(examples, id: \.query) { example in
                            Button { onSearch(example.query) } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(example.query).font(.mincho(22)).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text(example.hint).font(.footnote).foregroundStyle(Palette.muted)
                                }
                            }
                            Divider().overlay(Palette.rule)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(tr("Recenti")).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(Palette.shu)
                            Spacer()
                            Button(tr("Cancella")) { model.settings.history = [] }
                                .font(.caption).tint(Palette.muted)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(model.settings.history.prefix(30), id: \.self) { item in
                                Button { onSearch(item) } label: {
                                    Text(item)
                                        .font(Kana.containsJapanese(item) ? .mincho(19) : .callout)
                                        .foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.rule))
                                }
                                .contextMenu {
                                    Button(tr("Rimuovi"), systemImage: "trash", role: .destructive) {
                                        model.settings.history.removeAll { $0 == item }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private let examples: [(query: String, hint: String)] = [
        ("食べなかった", tr("forme coniugate")),
        ("taberu", "romaji"),
        ("gatto", tr("dall'italiano")),
        ("to run", tr("dall'inglese")),
    ]
}

private struct NoResults: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Text("無").font(.mincho(64, bold: true)).foregroundStyle(Palette.rule)
            Text(tr("Nessun risultato per «{0}»", query)).font(.headline).foregroundStyle(Palette.ink)
            Text(tr("Controlla di aver attivato i dizionari giusti, o prova la forma base della parola."))
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("辞書").font(.mincho(64, bold: true)).foregroundStyle(Palette.rule)
            Text(tr("Nessun dizionario")).font(.headline).foregroundStyle(Palette.ink)
            Text(tr("Importa un dizionario Yomitan (.zip) dalla scheda Dizionari."))
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

/// Lays chips out in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
