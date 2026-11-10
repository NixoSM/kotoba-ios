import SwiftUI
import UIKit

/// Impostazioni › Diagnostica: what this install is made of and what it has
/// been doing, as text to copy into a message when something goes wrong.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var report = DiagnosticsReport(facts: [], log: [])

    var body: some View {
        List {
            Section {
                ForEach(report.facts.indices, id: \.self) { i in
                    FactRow(name: report.facts[i].name, value: report.facts[i].value)
                }
            } footer: {
                Text(tr("Niente di tutto questo lascia il telefono, se non lo copi tu."))
            }

            Section {
                if report.log.isEmpty {
                    Text(tr("Ancora nessun evento.")).foregroundStyle(.secondary)
                } else {
                    // Newest first: what just went wrong is at the top.
                    ForEach(Array(report.log.reversed().enumerated()), id: \.offset) { line in
                        Text(line.element)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(tr("Diario"))
            }

            if !report.log.isEmpty {
                Section {
                    Button(tr("Svuota il diario"), role: .destructive) {
                        Diagnostics.shared.clear()
                        reload()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle(tr("Diagnostica"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: report.text)
                Button {
                    UIPasteboard.general.string = report.text
                    model.toast = tr("Copiato")
                } label: {
                    Label(tr("Copia"), systemImage: "doc.on.doc")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        report = model.diagnosticsReport(device: AppModel.deviceFacts)
    }
}

private struct FactRow: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.footnote.monospaced()).textSelection(.enabled)
        }
    }
}
