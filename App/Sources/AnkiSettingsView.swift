import SwiftUI
import KotobaCore

/// Impostazioni › Anki: the note Kotoba fills in AnkiMobile.
struct AnkiSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingForget = false
    @State private var confirmingRemove = false

    var body: some View {
        Form {
            if model.settings.ankiFormat != nil {
                AnkiNoteSections(format: Binding(
                    get: { model.settings.ankiFormat ?? .example },
                    set: { model.settings.ankiFormat = $0 }))
                Section {
                    Button(tr("Dimentica le parole già inviate"), role: .destructive) { confirmingForget = true }
                        .disabled(model.settings.mined.isEmpty)
                } footer: {
                    Text(tr("AnkiMobile non permette di controllare i duplicati: Kotoba ricorda da solo le {0} parole che hai già inviato, e le elenca nella scheda Parole.", model.settings.mined.count))
                }
                Section {
                    Button(tr("Rimuovi la nota Anki"), role: .destructive) { confirmingRemove = true }
                }
            } else {
                Section {
                    Button(tr("Configura una nota Anki a mano")) { model.settings.ankiFormat = .example }
                } footer: {
                    Text(tr("Oppure, in Impostazioni, importa le impostazioni di Yomitan: la tua nota viene configurata da sola. Serve AnkiMobile installato su questo iPhone."))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle("Anki")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.settings.ankiFormat != nil {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .confirmationDialog(tr("Dimenticare le {0} parole già inviate?", model.settings.mined.count),
                            isPresented: $confirmingForget, titleVisibility: .visible) {
            Button(tr("Dimentica"), role: .destructive) { model.settings.forgetAllMined() }
            Button(tr("Annulla"), role: .cancel) {}
        } message: {
            Text(tr("Le note in Anki restano. Kotoba smette solo di segnare queste parole come già aggiunte."))
        }
        .confirmationDialog(tr("Rimuovere la nota Anki?"), isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(tr("Rimuovi"), role: .destructive) { model.settings.ankiFormat = nil }
            Button(tr("Annulla"), role: .cancel) {}
        } message: {
            Text(tr("Mazzo, tipo di nota e campi vengono cancellati da Kotoba; in Anki non cambia nulla. Il pulsante ＋ sparisce dai risultati."))
        }
    }
}

/// Deck, note type and tags, then the fields: name, what goes in it, add, remove, reorder.
private struct AnkiNoteSections: View {
    @Binding var format: AnkiNoteFormat

    var body: some View {
        Section {
            LabeledContent(tr("Mazzo")) { TextField(tr("Mazzo"), text: $format.deck).multilineTextAlignment(.trailing) }
            LabeledContent(tr("Tipo di nota")) { TextField(tr("Tipo di nota"), text: $format.model).multilineTextAlignment(.trailing) }
            LabeledContent(tr("Etichette")) {
                TextField(tr("Etichette"), text: Binding(
                    get: { format.tags.joined(separator: " ") },
                    set: { format.tags = $0.split(separator: " ").map(String.init) }))
                .multilineTextAlignment(.trailing)
            }
        } header: {
            Text(tr("Nota Anki (AnkiMobile)"))
        } footer: {
            Text(tr("I nomi devono essere identici a quelli in AnkiMobile, maiuscole comprese."))
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

        Section {
            // By position, not by name: a name being typed must not move the row.
            ForEach(format.fields.indices, id: \.self) { i in
                AnkiFieldRow(name: name(at: i), template: template(at: i))
            }
            .onDelete { format.fields.remove(atOffsets: $0) }
            .onMove { format.fields.move(fromOffsets: $0, toOffset: $1) }
            Button {
                format.fields.append(AnkiNoteFormat.Field(name: newFieldName(), template: ""))
            } label: {
                Label(tr("Aggiungi un campo"), systemImage: "plus")
            }
        } header: {
            Text(tr("Campi"))
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let unsupported = AnkiFieldRenderer.unsupportedMarkers(in: format)
        let basics = tr("Il nome è quello del campo in AnkiMobile; sotto, cosa metterci: tocca {…} per inserire un segnaposto. Scorri un campo verso sinistra per toglierlo.")
        guard !unsupported.isEmpty else { return basics }
        return basics + "\n\n" + tr("Per ora restano vuoti:") + " " + unsupported.map { "{\($0)}" }.joined(separator: " ") + ". "
            + tr("Audio e immagini non passano tramite il collegamento di AnkiMobile.")
    }

    // The row may outlive its field for a moment while one is being removed.
    private func name(at i: Int) -> Binding<String> {
        Binding(get: { format.fields.indices.contains(i) ? format.fields[i].name : "" },
                set: { if format.fields.indices.contains(i) { format.fields[i].name = $0 } })
    }

    private func template(at i: Int) -> Binding<String> {
        Binding(get: { format.fields.indices.contains(i) ? format.fields[i].template : "" },
                set: { if format.fields.indices.contains(i) { format.fields[i].template = $0 } })
    }

    private func newFieldName() -> String {
        let taken = Set(format.fields.map(\.name))
        let base = tr("Campo")
        var n = format.fields.count + 1
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

private struct AnkiFieldRow: View {
    @Binding var name: String
    @Binding var template: String

    /// As they are written in a field: {expression}, {glossary}…
    private static let placeholders = AnkiFieldRenderer.supportedMarkers.map { "{" + $0 + "}" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(tr("Nome del campo"), text: $name)
                    .font(.subheadline.weight(.semibold))
                Menu {
                    ForEach(Self.placeholders, id: \.self) { placeholder in
                        Button(placeholder) { template += placeholder }
                    }
                } label: {
                    Image(systemName: "curlybraces").frame(width: 32, height: 28)
                }
                .accessibilityLabel(tr("Inserisci un segnaposto"))
            }
            TextField(tr("vuoto"), text: $template, axis: .vertical)
                .font(.footnote.monospaced())
                .lineLimit(1...4)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}
