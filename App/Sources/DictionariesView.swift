import SwiftUI
import UniformTypeIdentifiers
import KotobaCore

/// Impostazioni › Dizionari: order, on and off, import, delete.
struct DictionariesView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFiles = false
    @State private var pendingDelete: InstalledDictionary?
    @State private var shown: InstalledDictionary?

    var body: some View {
        List {
            WorkStatusSections()
            if model.dictionaries.isEmpty {
                if !model.isBusy {
                    Section { NoDictionariesYet(pick: { pickingFiles = true }) }
                }
            } else {
                Section {
                    ForEach(model.dictionaries) { dict in
                        row(dict)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                    // The database is being written: changes would wait for it.
                    .disabled(model.isBusy)
                } header: {
                    Text(tr("Ordine dei risultati"))
                } footer: {
                    Text(tr("Tieni premuto e trascina per cambiare l'ordine in cui i dizionari compaiono nei risultati. Tocca ⓘ per i dettagli. Scorri verso destra per mostrare un dizionario chiuso nei risultati (si apre toccandone il nome), verso sinistra per eliminarlo."))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle(tr("Dizionari"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.dictionaries.count > 1 { EditButton().disabled(model.isBusy) }
                Button { pickingFiles = true } label: { Label(tr("Importa"), systemImage: "plus") }
                    .disabled(model.deleting != nil)
            }
        }
        .navigationDestination(item: $shown) { dict in
            DictionaryDetailView(id: dict.id)
        }
        .dictionaryFilePicker(isPresented: $pickingFiles)
        .deleteConfirmation(for: $pendingDelete)
    }

    private func row(_ dict: InstalledDictionary) -> some View {
        let closed = model.settings.collapsedDictionaries.contains(dict.title)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dict.title)
                Text(DictionaryFacts.summary(dict))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if closed {
                    Label(tr("Chiuso nei risultati"), systemImage: "chevron.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button { shown = dict } label: {
                Image(systemName: "info.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Dettagli di {0}", dict.title))
            Toggle(dict.title, isOn: Binding(get: { dict.enabled }, set: { model.setEnabled($0, for: dict) }))
                .labelsHidden()
        }
        .swipeActions(edge: .leading) {
            Button(closed ? tr("Apri") : tr("Chiudi")) {
                if closed {
                    model.settings.collapsedDictionaries.remove(dict.title)
                } else {
                    model.settings.collapsedDictionaries.insert(dict.title)
                }
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not the "destructive" kind: that one removes the row before you have answered.
            Button(tr("Elimina")) { pendingDelete = dict }
                .tint(.red)
        }
    }
}

/// What a dictionary holds, in one line.
enum DictionaryFacts {
    static func counts(_ dict: InstalledDictionary) -> String {
        var parts: [String] = []
        if dict.termCount > 0 { parts.append(tr("{0} voci", dict.termCount.formatted())) }
        if dict.metaCount > 0 { parts.append(tr("{0} frequenze/accenti", dict.metaCount.formatted())) }
        if dict.kanjiCount > 0 { parts.append(tr("{0} kanji", dict.kanjiCount.formatted())) }
        if parts.isEmpty { parts.append(tr("vuoto")) }
        return parts.joined(separator: " · ")
    }

    static func summary(_ dict: InstalledDictionary) -> String {
        dict.revision.isEmpty ? counts(dict) : counts(dict) + " · rev. " + dict.revision
    }
}

/// Import progress, the result of the last import, a delete in progress and
/// the one-time index building: whatever the database is busy with.
struct WorkStatusSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let status = model.importStatus {
            Section { ImportStatusRow(status: status) }
        }
        if let title = model.deleting {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(tr("Elimino «{0}»…", title))
                }
            } footer: {
                Text(tr("I dizionari grandi richiedono qualche secondo. Intanto puoi continuare a cercare."))
            }
        }
        if let status = model.reverseIndexStatus {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView()
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One import: which file of how many, how far, and a way to stop.
struct ImportStatusRow: View {
    @Environment(AppModel.self) private var model
    let status: AppModel.ImportStatus

    var body: some View {
        switch status {
        case .running(let title, let fraction, let position, let total):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("Importo {0}…", title)).lineLimit(2)
                    Spacer(minLength: 8)
                    if total > 1 {
                        Text(tr("{0} di {1}", position, total))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(max(fraction, 0), 1))
                Text(tr("Tieni Kotoba aperto: lo schermo resta acceso da solo. I dizionari grandi richiedono qualche minuto."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(tr("Interrompi"), role: .cancel) { model.cancelImport() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
        case .finished(let summary):
            HStack {
                Label(summary, systemImage: "checkmark.circle")
                Spacer(minLength: 8)
                Button { model.clearImportSummary() } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("Chiudi"))
            }
        }
    }
}

/// Shown in place of the list when nothing is installed.
private struct NoDictionariesYet: View {
    let pick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Nessun dizionario")).font(.headline)
            Text(tr("Kotoba legge i dizionari nel formato di Yomitan: file .zip che scarichi una volta e restano sul telefono. Puoi sceglierne più d'uno insieme."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: pick) { Label(tr("Scegli i file…"), systemImage: "folder") }
                .buttonStyle(.borderedProminent)
            Link(destination: DictionarySources.page) {
                Label(tr("Dove trovare i dizionari"), systemImage: "safari")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}

enum DictionarySources {
    /// Yomitan's own list of recommended dictionaries, by language.
    static let page = URL(string: "https://yomitan.wiki/dictionaries/")!
}

extension View {
    /// The file picker for dictionaries: several .zip files at once.
    func dictionaryFilePicker(isPresented: Binding<Bool>) -> some View {
        modifier(DictionaryFilePicker(isPresented: isPresented))
    }

    /// Asks before a dictionary is deleted, then deletes it.
    func deleteConfirmation(for dictionary: Binding<InstalledDictionary?>) -> some View {
        modifier(DeleteConfirmation(dictionary: dictionary))
    }
}

private struct DictionaryFilePicker: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importDictionaries(from: urls)
            case .failure(let error):
                model.errorMessage = tr("Non riesco ad aprire i file scelti: {0}", error.localizedDescription)
            }
        }
    }
}

private struct DeleteConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var dictionary: InstalledDictionary?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            tr("Eliminare «{0}»?", dictionary?.title ?? ""),
            isPresented: Binding(get: { dictionary != nil }, set: { if !$0 { dictionary = nil } }),
            titleVisibility: .visible,
            presenting: dictionary
        ) { dict in
            Button(tr("Elimina"), role: .destructive) { model.delete(dict) }
            Button(tr("Annulla"), role: .cancel) {}
        } message: { dict in
            Text(tr("{0}. Viene tolto dal telefono: per riaverlo dovrai importare di nuovo il suo file.", DictionaryFacts.counts(dict)))
        }
    }
}

/// One dictionary: what it says about itself, and its switches.
struct DictionaryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: Int64
    @State private var index: DictionaryIndex?
    @State private var hasFrequencies = false
    @State private var pendingDelete: InstalledDictionary?

    private var dictionary: InstalledDictionary? { model.dictionaries.first { $0.id == id } }

    var body: some View {
        Form {
            if let dict = dictionary {
                content(dict)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle(dictionary?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .deleteConfirmation(for: $pendingDelete)
        .onAppear {
            index = model.store?.index(ofDictionary: id)
            hasFrequencies = dictionary.map { model.store?.frequencyDictionaries().contains($0.title) ?? false } ?? false
        }
        // Deleted (from here or elsewhere): there is nothing left to show.
        .onChange(of: dictionary == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    @ViewBuilder
    private func content(_ dict: InstalledDictionary) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(dict.title).font(.mincho(26, bold: true)).foregroundStyle(Palette.ink)
                Text(DictionaryFacts.summary(dict)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }

        Section {
            Toggle(tr("Usa nelle ricerche"), isOn: Binding(get: { dict.enabled }, set: { model.setEnabled($0, for: dict) }))
            Toggle(tr("Chiuso nei risultati"), isOn: Binding(
                get: { model.settings.collapsedDictionaries.contains(dict.title) },
                set: { closed in
                    if closed {
                        model.settings.collapsedDictionaries.insert(dict.title)
                    } else {
                        model.settings.collapsedDictionaries.remove(dict.title)
                    }
                }))
            if hasFrequencies {
                Toggle(tr("Ordina i risultati con le sue frequenze"), isOn: Binding(
                    get: { model.settings.sortFrequencyDictionary == dict.title },
                    set: { model.settings.sortFrequencyDictionary = $0 ? dict.title : nil }))
            }
        } footer: {
            Text(tr("Un dizionario chiuso mostra solo il nome sotto la parola: si apre toccandolo. Utile per quelli lunghi, come le enciclopedie."))
        }
        .disabled(model.isBusy)

        if let index {
            DictionaryIndexSection(index: index)
        }

        Section {
            if model.deleting == dict.title {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(tr("Elimino «{0}»…", dict.title))
                }
            } else {
                Button(tr("Elimina dizionario"), role: .destructive) { pendingDelete = dict }
                    .disabled(model.isBusy)
            }
        }
    }
}

/// What the dictionary's own index.json says.
private struct DictionaryIndexSection: View {
    let index: DictionaryIndex

    private var languages: String? {
        switch (index.sourceLanguage, index.targetLanguage) {
        case let (from?, to?): from + " → " + to
        case let (from?, nil): from
        case let (nil, to?): "→ " + to
        default: nil
        }
    }

    var body: some View {
        Section {
            if let author = index.author, !author.isEmpty {
                LabeledContent(tr("Autore"), value: author)
            }
            if let languages {
                LabeledContent(tr("Lingue"), value: languages)
            }
            LabeledContent(tr("Revisione"), value: index.revision)
            LabeledContent(tr("Formato"), value: String(index.formatVersion))
            if let text = index.description, !text.isEmpty {
                Text(text).font(.subheadline)
            }
            if let text = index.attribution, !text.isEmpty {
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
            if let address = index.url, let url = URL(string: address), url.scheme == "https" || url.scheme == "http" {
                Link(destination: url) {
                    Label(tr("Sito del dizionario"), systemImage: "safari")
                }
            }
        } header: {
            Text(tr("Informazioni"))
        }
    }
}
