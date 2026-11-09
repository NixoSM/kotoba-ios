import SwiftUI
import UniformTypeIdentifiers
import KotobaCore

struct DictionariesView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFile = false

    var body: some View {
        NavigationStack {
            List {
                if let status = model.importStatus {
                    Section { ImportStatusRow(status: status) }
                }
                if let status = model.reverseIndexStatus {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView()
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ForEach(model.dictionaries) { dict in
                        Toggle(isOn: Binding(get: { dict.enabled }, set: { model.setEnabled($0, for: dict) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dict.title)
                                Text(tr("{0} voci · {1} frequenze/accenti · rev. {2}", dict.termCount.formatted(), dict.metaCount.formatted(), dict.revision))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if model.settings.collapsedDictionaries.contains(dict.title) {
                                    Label(tr("Chiuso nei risultati"), systemImage: "chevron.right.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            let closed = model.settings.collapsedDictionaries.contains(dict.title)
                            Button(closed ? tr("Apri") : tr("Chiudi")) {
                                if closed {
                                    model.settings.collapsedDictionaries.remove(dict.title)
                                } else {
                                    model.settings.collapsedDictionaries.insert(dict.title)
                                }
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(tr("Elimina"), role: .destructive) { model.delete(dict) }
                        }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { model.dictionaries[$0] }.forEach(model.delete) }
                } header: {
                    Text(tr("Ordine dei risultati"))
                } footer: {
                    Text(tr("Trascina per cambiare l'ordine in cui i dizionari compaiono nei risultati. Scorri verso destra per mostrare un dizionario chiuso nei risultati (si apre toccandone il nome), verso sinistra per eliminarlo."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(tr("Dizionari"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pickingFile = true } label: { Label(tr("Importa"), systemImage: "plus") }
                        .disabled({ if case .running = model.importStatus { return true } else { return false } }())
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result { model.importDictionary(from: url) }
            }
        }
    }
}

private struct ImportStatusRow: View {
    let status: AppModel.ImportStatus

    var body: some View {
        switch status {
        case .running(let title, let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Importo {0}…", title))
                ProgressView(value: fraction)
                Text(tr("Puoi lasciare l'app aperta: i dizionari grandi richiedono qualche minuto."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .finished(let title, let terms):
            Label(tr("{0}: {1} voci importate", title, terms.formatted()), systemImage: "checkmark.circle")
        }
    }
}
