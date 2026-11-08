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
                Section {
                    ForEach(model.dictionaries) { dict in
                        Toggle(isOn: Binding(get: { dict.enabled }, set: { model.setEnabled($0, for: dict) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dict.title)
                                Text("\(dict.termCount.formatted()) voci · \(dict.metaCount.formatted()) frequenze/accenti · rev. \(dict.revision)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { model.dictionaries[$0] }.forEach(model.delete) }
                } header: {
                    Text("Ordine dei risultati")
                } footer: {
                    Text("Trascina per cambiare l'ordine in cui i dizionari compaiono nei risultati. Scorri a sinistra per eliminare.")
                }
            }
            .navigationTitle("Dizionari")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pickingFile = true } label: { Label("Importa", systemImage: "plus") }
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
                Text("Importo \(title)…")
                ProgressView(value: fraction)
                Text("Puoi lasciare l'app aperta: i dizionari grandi richiedono qualche minuto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .finished(let title, let terms):
            Label("\(title): \(terms.formatted()) voci importate", systemImage: "checkmark.circle")
        }
    }
}
