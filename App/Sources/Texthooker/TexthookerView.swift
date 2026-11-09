import SwiftUI
import KotobaCore

/// The visual novel's text, live from the PC: tap any character to look the
/// word up from there, long-press a line to fix it.
struct TexthookerView: View {
    @Environment(AppModel.self) private var model
    @Environment(HookerModel.self) private var hooker
    let onSearch: (String) -> Void

    /// The word tapped, in which line.
    struct LinePick: Hashable {
        var lineID: UUID
        var pick: WordAim.Pick
    }

    @State private var pick: LinePick?
    @State private var outcome = AppModel.SearchOutcome()
    @State private var showingResults = false
    @State private var editing: HookLine?
    @State private var showingSetup = false
    @State private var confirmingClear = false

    private static let sheetFraction: CGFloat = 0.45

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Palette.paper.ignoresSafeArea()
                    if hooker.lines.isEmpty {
                        HookerEmptyView(onSetup: { showingSetup = true })
                    } else {
                        lineList(bottomInset: showingResults ? geometry.size.height * Self.sheetFraction : 0)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HookStatusPill(state: hooker.socketState, enabled: hooker.settings.enabled,
                                   inbox: hooker.inboxState) { showingSetup = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(tr("Collegamento e pulizia"), systemImage: "gearshape") { showingSetup = true }
                        if hooker.settings.enabled {
                            Button(tr("Ricollegati ora"), systemImage: "arrow.clockwise") { hooker.reconnect() }
                        }
                        Button(tr("Cancella tutte le righe"), systemImage: "trash", role: .destructive) { confirmingClear = true }
                            .disabled(hooker.lines.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog(tr("Cancellare tutte le righe ricevute?"), isPresented: $confirmingClear, titleVisibility: .visible) {
                Button(tr("Cancella tutte le righe"), role: .destructive) {
                    pick = nil
                    hooker.clear()
                }
            }
        }
        .onAppear {
            WordFinder.shared.attach(model.store)
            hooker.isOnScreen = true
        }
        .onDisappear { hooker.isOnScreen = false }
        .task(id: pick) {
            guard let pick else { return }
            var result = await model.search(pick.pick.query)
            guard !Task.isCancelled else { return }
            result.sentence = pick.pick.sentence
            outcome = result
            showingResults = true
        }
        .sheet(isPresented: $showingResults, onDismiss: { pick = nil }) {
            HookResultsSheet(outcome: outcome, query: pick?.pick.query ?? "", onOpenInSearch: { text in
                showingResults = false
                onSearch(text)
            })
            .presentationDetents([.fraction(Self.sheetFraction), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(Self.sheetFraction)))
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { line in
            HookLineEditor(line: line)
        }
        .sheet(isPresented: $showingSetup) {
            HookerSetupView()
        }
    }

    private func lineList(bottomInset: CGFloat) -> some View {
        let font = lineFont
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hooker.lines) { line in
                        let isLatest = line.id == hooker.lines.last?.id
                        HookLineRow(line: line, isLatest: isLatest, font: isLatest ? font.latest : font.regular,
                                    pick: pick?.lineID == line.id ? pick?.pick : nil) { index in
                            tap(line, at: index)
                        }
                        .contextMenu { menu(for: line) }
                        .id(line.id)
                    }
                }
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .safeAreaPadding(.bottom, bottomInset)
            .onChange(of: hooker.lines.last?.id) { _, last in
                // While a word is open, new lines don't pull the page away from it.
                guard let last, !showingResults else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: showingResults) { _, showing in
                let target = showing ? pick?.lineID : hooker.lines.last?.id
                guard let target else { return }
                Task {
                    // After the sheet has made room.
                    try? await Task.sleep(for: .milliseconds(showing ? 350 : 50))
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for line: HookLine) -> some View {
        Button(tr("Modifica"), systemImage: "pencil") { editing = line }
        Button(tr("Copia"), systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text }
        Button(tr("Cerca la riga intera"), systemImage: "magnifyingglass") { onSearch(line.text) }
        if line.edited {
            Button(tr("Ripristina l'originale"), systemImage: "arrow.uturn.backward") { hooker.restore(line) }
        }
        Button(tr("Elimina"), systemImage: "trash", role: .destructive) {
            if pick?.lineID == line.id { showingResults = false }
            hooker.delete(line)
        }
    }

    /// Like Yomitan, the lookup starts at the character you touch, but a finger
    /// on the middle of 天気 means 天気: the word around the touch wins. Touch
    /// inside the word shown to start exactly there instead (気 alone).
    private func tap(_ line: HookLine, at index: Int) {
        let chars = Array(line.text)
        let current = pick
        Task {
            let picked = await Task.detached(priority: .userInitiated) { () -> WordAim.Pick? in
                if let current, current.lineID == line.id, current.pick.text == chars,
                   index > current.pick.start, index < current.pick.start + current.pick.length {
                    return WordFinder.shared.pick(in: chars, start: index)
                }
                return WordAim.pick(in: chars, at: Double(index) + 0.5, favoring: nil,
                                    matchLength: WordFinder.shared.matchLength)
                    ?? WordFinder.shared.pick(in: chars, start: index)
            }.value
            guard let picked else { return }
            pick = LinePick(lineID: line.id, pick: picked)
        }
    }

    private var lineFont: (regular: Font, latest: Font) {
        let appearance = model.settings.appearance
        let name = FontCatalog.choice(appearance.bodyFont).postScriptName
        let base = CGFloat(appearance.fontSize) + 3
        func font(_ size: CGFloat) -> Font {
            if let name { return .kotoba(name, size: size) }
            return .system(size: size)
        }
        return (font(base), font(base + 5))
    }
}

// MARK: - One line

private struct HookLineRow: View {
    let line: HookLine
    let isLatest: Bool
    let font: Font
    let pick: WordAim.Pick?
    let onTap: (Int) -> Void

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.time.string(from: line.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                if line.edited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 34, alignment: .trailing)
            .padding(.top, 6)

            CharFlow(characters: Array(line.text)) {
                ForEach(Array(line.text.enumerated()), id: \.offset) { index, char in
                    let inWord = pick.map { index >= $0.start && index < $0.start + $0.length } ?? false
                    Text(String(char))
                        .font(font)
                        .foregroundStyle(inWord ? Palette.shu : isLatest ? Palette.ink : Palette.ink.opacity(0.72))
                        .padding(.vertical, 3)
                        .background(inWord ? Palette.shu.opacity(0.1) : .clear)
                        .overlay(alignment: .bottom) {
                            if inWord { Rectangle().fill(Palette.shu).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(index) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isLatest ? 14 : 9)
        .background(isLatest ? Palette.raised : .clear)
        .overlay(alignment: .leading) {
            // The current text box, marked like a bookmark ribbon.
            if isLatest { Rectangle().fill(Palette.shu).frame(width: 3) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.rule.opacity(0.5)).frame(height: 0.5).padding(.leading, 58)
        }
        .contentShape(Rectangle())
    }
}

/// Characters laid out left to right, wrapping where they run out of room.
/// Closing punctuation never starts a row (kinsoku), so 。 and 」 stay with their word.
struct CharFlow: Layout {
    private static let noLineStart: Set<Character> = ["、", "。", "，", "．", "」", "』", "）", ")", "】", "〉", "》", "！", "？", "!", "?", "…", "‥", "ー", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ッ", "ャ", "ュ", "ョ", "〜", "～"]

    var characters: [Character]? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat = 0
        var width: CGFloat = 0
        var items: [(Int, CGSize)] = []
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row(y: 0)]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let opensRow = rows[rows.count - 1].width + size.width > width && !rows[rows.count - 1].items.isEmpty
            if opensRow && !isNoLineStart(index) {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height))
            }
            rows[rows.count - 1].items.append((index, size))
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }

    private func isNoLineStart(_ index: Int) -> Bool {
        guard let characters, characters.indices.contains(index) else { return false }
        return Self.noLineStart.contains(characters[index])
    }
}

// MARK: - Results

private struct HookResultsSheet: View {
    let outcome: AppModel.SearchOutcome
    let query: String
    let onOpenInSearch: (String) -> Void
    @State private var path: [Lookup] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    Text(tr("Nessuna parola qui. Tocca un altro carattere nella riga sopra."))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ResultsPane(outcome: outcome, query: query, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
                }
            }
            .navigationDestination(for: Lookup.self) { lookup in
                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
            }
            .navigationTitle(outcome.direct.first?.matchedText ?? query)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Editing a line

private struct HookLineEditor: View {
    @Environment(HookerModel.self) private var hooker
    @Environment(\.dismiss) private var dismiss
    let line: HookLine
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .font(.system(size: 22))
                        .frame(minHeight: 140)
                } footer: {
                    Text(tr("Cancella le letture rimaste attaccate al testo (furigana), i nomi o i simboli in più. Una riga vuota viene eliminata."))
                }
                Section {
                    Button(tr("Togli le letture (furigana)"), systemImage: "textformat.size.smaller") {
                        draft = hooker.cleaned(draft)
                    }
                    if draft != line.original {
                        Button(tr("Ripristina l'originale"), systemImage: "arrow.uturn.backward") { draft = line.original }
                    }
                }
                if line.original != line.text || line.original != draft {
                    Section(tr("Arrivata dal PC")) {
                        Text(line.original)
                            .font(.callout)
                            .foregroundStyle(Palette.muted)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(tr("Modifica la riga"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annulla")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Salva")) {
                        hooker.update(line, text: draft)
                        dismiss()
                    }
                }
            }
            .onAppear { draft = line.text }
        }
    }
}

// MARK: - Status and empty screen

struct HookStatusPill: View {
    let state: HookSocket.State
    let enabled: Bool
    let inbox: HookInbox.State
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(state == .connected && pulse ? 1.35 : 1)
                    .opacity(state == .connected && pulse ? 0.6 : 1)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.raised, in: Capsule())
            .overlay(Capsule().stroke(Palette.rule.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var label: String {
        switch state {
        case .connected: return tr("In diretta dal PC")
        case .connecting: return tr("Mi collego al PC…")
        case .retrying(.refused): return tr("Aspetto Textractor…")
        case .retrying: return tr("Il PC non risponde")
        case .off:
            if inbox == .listening { return tr("In ascolto sul telefono") }
            return enabled ? tr("Manca l'indirizzo del PC") : tr("Non collegato")
        }
    }

    private var color: Color {
        switch state {
        case .connected: return Palette.shu
        case .connecting, .retrying(.refused): return .orange
        case .retrying: return .gray
        case .off: return inbox == .listening ? Palette.shu : .gray
        }
    }
}

private struct HookerEmptyView: View {
    @Environment(HookerModel.self) private var hooker
    let onSetup: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(tr("Testo dal PC"), systemImage: "desktopcomputer")
        } description: {
            if hooker.settings.enabled || hooker.settings.inbox {
                Text(tr("Collegato. Fai avanzare il testo nel gioco: ogni riga che Textractor aggancia appare qui."))
            } else {
                Text(tr("Leggi una visual novel sul PC: Textractor manda qui ogni riga, e tocchi le parole per cercarle senza staccare gli occhi dal gioco."))
            }
        } actions: {
            Button(hooker.settings.enabled ? tr("Collegamento e pulizia") : tr("Collega il PC"), action: onSetup)
                .buttonStyle(.borderedProminent)
        }
    }
}
