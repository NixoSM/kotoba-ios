import SwiftUI
import KotobaCore

/// The "Parole" tab: the words you have sent to Anki, laid out like the index
/// of a paper dictionary (by kana row, with a thumb index on the edge) or by
/// date. Tap one to look it up again.
struct WordsView: View {
    @Environment(AppModel.self) private var model
    @State private var order = Order.kana
    @State private var filter = ""

    enum Order: Hashable { case kana, newest }

    private var words: [IndexedWord] {
        let all = WordIndex.words(mined: model.settings.mined, dates: model.settings.minedDates)
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        let kana = Kana.toHiragana(text)
        return all.filter { $0.expression.contains(text) || Kana.toHiragana($0.reading).contains(kana) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.settings.mined.isEmpty {
                    NoWordsYet()
                } else {
                    list
                }
            }
            .background(Palette.paper)
            .navigationTitle(tr("Parole"))
            .toolbarBackground(Palette.paper, for: .navigationBar)
        }
    }

    private var list: some View {
        let shown = words
        return VStack(spacing: 0) {
            Picker(tr("Ordine"), selection: $order) {
                Text("あ か さ た な").tag(Order.kana)
                Text(tr("Più recenti")).tag(Order.newest)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if shown.isEmpty {
                Spacer()
                Text(tr("Nessuna parola corrisponde a «{0}»", filter)).foregroundStyle(Palette.muted).padding(32)
                Spacer()
            } else if order == .kana {
                KanaIndexedList(sections: WordIndex.sections(shown), open: open, forget: forget)
            } else {
                List {
                    Section {
                        ForEach(WordIndex.newestFirst(shown)) { word in
                            WordRow(word: word, showsDate: true, open: open, forget: forget)
                        }
                    } footer: {
                        Text(tr("{0} parole inviate ad Anki", model.settings.mined.count))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $filter, prompt: tr("Cerca tra le tue parole"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func open(_ word: IndexedWord) {
        model.pendingQuery = word.expression
        model.selectedTab = 0
    }

    private func forget(_ word: IndexedWord) {
        model.settings.forgetMined(word.id)
    }
}

/// The list by kana row, with the ten rows down the right edge: touch or
/// slide a finger along them to jump, as on the cut edge of a dictionary.
private struct KanaIndexedList: View {
    let sections: [WordIndex.Section]
    let open: (IndexedWord) -> Void
    let forget: (IndexedWord) -> Void

    /// Row letters and words in one column, so the list can jump to a letter.
    private enum Line: Identifiable {
        case letter(String)
        case word(IndexedWord)

        var id: String {
            switch self {
            case .letter(let row): "row:" + row
            case .word(let word): "word:" + word.id
            }
        }
    }

    private var lines: [Line] {
        sections.flatMap { section in [Line.letter(section.row)] + section.words.map { Line.word($0) } }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(lines) { line in
                    switch line {
                    case .letter(let row):
                        Text(row)
                            .font(.mincho(22, bold: true))
                            .foregroundStyle(Palette.shu)
                            .padding(.top, 10)
                            .listRowSeparator(.hidden, edges: .top)
                            .listRowBackground(Palette.paper)
                            .accessibilityAddTraits(.isHeader)
                    case .word(let word):
                        WordRow(word: word, showsDate: false, open: open, forget: forget)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .trailing) {
                ThumbIndex(present: Set(sections.map(\.row))) { row in
                    proxy.scrollTo("row:" + row, anchor: .top)
                }
            }
        }
    }
}

private struct ThumbIndex: View {
    /// Rows that have words: the others are shown pale and jump to the next one that has.
    let present: Set<String>
    let jump: (String) -> Void

    private let rows = WordIndex.rows + [WordIndex.other]
    private let rowHeight: CGFloat = 26
    @State private var touched: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color(row))
                    .frame(width: 28, height: rowHeight)
            }
        }
        .background(Palette.paper.opacity(0.85), in: Capsule())
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let index = min(max(Int(value.location.y / rowHeight), 0), rows.count - 1)
                // The row under the finger, or the next one that has words.
                let after = rows[index...].first { present.contains($0) }
                let before = rows[..<index].last { present.contains($0) }
                guard let target = after ?? before, target != touched else { return }
                touched = target
                jump(target)
            }
            .onEnded { _ in touched = nil })
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }

    private func color(_ row: String) -> Color {
        if row == touched { return Palette.shu }
        return present.contains(row) ? Palette.ink : Palette.muted.opacity(0.45)
    }
}

private struct WordRow: View {
    let word: IndexedWord
    let showsDate: Bool
    let open: (IndexedWord) -> Void
    let forget: (IndexedWord) -> Void

    var body: some View {
        Button { open(word) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.expression).font(.mincho(21)).foregroundStyle(Palette.ink)
                if !word.reading.isEmpty, word.reading != word.expression {
                    Text(word.reading).font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                if showsDate, let added = word.added {
                    Text(added.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.trailing, showsDate ? 0 : 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.paper)
        .swipeActions(edge: .trailing) {
            Button(tr("Dimentica")) { forget(word) }
                .tint(.orange)
        }
    }
}

/// Before the first word: what this tab is for and how words get here.
private struct NoWordsYet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Text("単語帳").font(.mincho(52, bold: true)).foregroundStyle(Palette.rule)
            Text(tr("Qui si raccolgono le tue parole")).font(.headline).foregroundStyle(Palette.ink)
            Text(model.settings.ankiFormat == nil
                 ? tr("Ogni parola che mandi ad Anki finisce in questo elenco. Prima configura la nota in Impostazioni › Anki.")
                 : tr("Ogni parola che mandi ad Anki con il pulsante ＋ finisce in questo elenco, in ordine di kana come in un dizionario di carta."))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
