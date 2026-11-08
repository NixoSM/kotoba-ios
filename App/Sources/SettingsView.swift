import SwiftUI
import UniformTypeIdentifiers
import KotobaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingBackup = false
    @State private var frequencyDictionaries: [String] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Button {
                        pickingBackup = true
                    } label: {
                        Label("Importa impostazioni di Yomitan", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Il file yomitan-settings-….json: applica ordine e attivazione dei dizionari, il dizionario di frequenza per l'ordinamento e la nota Anki.")
                }

                Section("Ordinamento dei risultati") {
                    Picker("Dizionario di frequenza", selection: $model.settings.sortFrequencyDictionary) {
                        Text("Il primo disponibile").tag(String?.none)
                        ForEach(frequencyDictionaries, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }

                if model.settings.ankiFormat != nil {
                    AnkiFormatSection(format: Binding(
                        get: { model.settings.ankiFormat ?? .example },
                        set: { model.settings.ankiFormat = $0 }))
                    Section {
                        Button("Dimentica le parole già minate", role: .destructive) { model.settings.mined = [] }
                    } footer: {
                        Text("AnkiMobile non permette di controllare i duplicati: Kotoba ricorda da solo le \(model.settings.mined.count) parole che hai già inviato.")
                    }
                } else {
                    Section {
                        Button("Configura una nota Anki a mano") { model.settings.ankiFormat = .example }
                    } header: {
                        Text("Anki")
                    } footer: {
                        Text("Oppure importa le impostazioni di Yomitan qui sopra: la tua nota viene configurata da sola.")
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .fileImporter(isPresented: $pickingBackup, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { model.importYomitanSettings(from: url) }
                frequencyDictionaries = model.store?.frequencyDictionaries() ?? []
            }
            .onAppear { frequencyDictionaries = model.store?.frequencyDictionaries() ?? [] }
        }
    }
}

private struct AnkiFormatSection: View {
    @Binding var format: AnkiNoteFormat

    var body: some View {
        Section {
            LabeledContent("Mazzo") { TextField("Mazzo", text: $format.deck).multilineTextAlignment(.trailing) }
            LabeledContent("Tipo di nota") { TextField("Tipo di nota", text: $format.model).multilineTextAlignment(.trailing) }
            LabeledContent("Etichette") {
                TextField("Etichette", text: Binding(
                    get: { format.tags.joined(separator: " ") },
                    set: { format.tags = $0.split(separator: " ").map(String.init) }))
                .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Nota Anki (AnkiMobile)")
        } footer: {
            Text("I nomi devono essere identici a quelli in AnkiMobile, maiuscole comprese.")
        }

        Section {
            ForEach($format.fields, id: \.name) { $field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name).font(.subheadline.weight(.semibold))
                    TextField("vuoto", text: $field.template)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text("Campi")
        } footer: {
            let unsupported = AnkiFieldRenderer.unsupportedMarkers(in: format)
            Text(unsupported.isEmpty
                 ? "Segnaposto disponibili: {expression} {reading} {furigana} {furigana-plain} {glossary} {glossary-first} {sentence} {cloze-prefix} {cloze-body} {cloze-suffix} {pitch-accents} {frequencies} {frequency-harmonic-rank} {part-of-speech}."
                 : "Per ora restano vuoti: " + unsupported.map { "{\($0)}" }.joined(separator: " ") + ". Audio e immagini non passano tramite il collegamento di AnkiMobile.")
        }
    }
}
