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
    var definitions: [(dictionary: String, items: [String])]

    static func group(_ results: [(entry: TermEntry, matchedText: String, reasons: [Reason])]) -> [HeadwordGroup] {
        var order: [String] = []
        var groups: [String: HeadwordGroup] = [:]
        for r in results {
            let key = r.entry.expression + "|" + r.entry.reading
            let items = GlossaryText.items(fromJSON: r.entry.glossaryJSON)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if model.dictionaries.isEmpty {
                        ContentUnavailableView("Nessun dizionario",
                                               systemImage: "square.stack.3d.up.slash",
                                               description: Text("Importa un dizionario Yomitan (.zip) dalla scheda Dizionari."))
                    } else if !query.isEmpty && outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    if let reading = outcome.romajiReading, !outcome.direct.isEmpty {
                        SectionLabel(text: "Letto come \(reading)")
                    }
                    ForEach(outcome.direct) { HeadwordCard(group: $0) }
                    if !outcome.byMeaning.isEmpty {
                        SectionLabel(text: "Parole che significano «\(query.trimmingCharacters(in: .whitespaces))»")
                        if let status = model.reverseIndexStatus {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(outcome.byMeaning) { HeadwordCard(group: $0) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Cerca")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "日本語")
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

struct HeadwordCard: View {
    let group: HeadwordGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                if group.reading != group.expression {
                    Text(group.reading)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Text(group.expression)
                    .font(.custom("HiraMinProN-W6", size: 40, relativeTo: .largeTitle))
            }
            if !group.reasons.isEmpty {
                Text("\(group.matchedText)  ·  " + group.reasons.map(\.italianLabel).joined(separator: " › "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tint)
            }
            ForEach(Array(group.definitions.enumerated()), id: \.offset) { _, def in
                VStack(alignment: .leading, spacing: 6) {
                    Text(def.dictionary.uppercased())
                        .font(.caption2.weight(.semibold))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(def.items.enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            Text(item).font(.body)
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.quaternary).frame(width: 2)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}
