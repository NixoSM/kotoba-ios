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
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack(spacing: 14) {
                            Text("字").font(.mincho(26, bold: true)).foregroundStyle(Palette.shu)
                                .frame(width: 40, height: 40)
                                .background(Palette.shu.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("Aspetto"))
                                Text("\(FontCatalog.choice(model.settings.appearance.bodyFont).name) · \(Int(model.settings.appearance.fontSize)) pt · \(model.settings.appearance.layout.label)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker(selection: $model.settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label(tr("Lingua dell'app"), systemImage: "globe")
                    }
                } header: {
                    Text(tr("Lingua"))
                } footer: {
                    Text(tr("Menu e pulsanti di sistema (Annulla, Modifica, la scelta dei file) cambiano lingua alla prossima apertura dell'app."))
                }

                Section {
                    Button {
                        pickingBackup = true
                    } label: {
                        Label(tr("Importa impostazioni di Yomitan"), systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text(tr("Il file yomitan-settings-….json: applica ordine e attivazione dei dizionari, il dizionario di frequenza, l'aspetto (font, dimensioni, layout) e la nota Anki."))
                }

                Section(tr("Ordinamento dei risultati")) {
                    Picker(tr("Dizionario di frequenza"), selection: $model.settings.sortFrequencyDictionary) {
                        Text(tr("Il primo disponibile")).tag(String?.none)
                        ForEach(frequencyDictionaries, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }

                if model.settings.ankiFormat != nil {
                    AnkiFormatSection(format: Binding(
                        get: { model.settings.ankiFormat ?? .example },
                        set: { model.settings.ankiFormat = $0 }))
                    Section {
                        Button(tr("Dimentica le parole già minate"), role: .destructive) { model.settings.mined = [] }
                    } footer: {
                        Text(tr("AnkiMobile non permette di controllare i duplicati: Kotoba ricorda da solo le {0} parole che hai già inviato.", model.settings.mined.count))
                    }
                } else {
                    Section {
                        Button(tr("Configura una nota Anki a mano")) { model.settings.ankiFormat = .example }
                    } header: {
                        Text("Anki")
                    } footer: {
                        Text(tr("Oppure importa le impostazioni di Yomitan qui sopra: la tua nota viene configurata da sola."))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(tr("Impostazioni"))
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

        Section {
            ForEach($format.fields, id: \.name) { $field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name).font(.subheadline.weight(.semibold))
                    TextField(tr("vuoto"), text: $field.template)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        } header: {
            Text(tr("Campi"))
        } footer: {
            let unsupported = AnkiFieldRenderer.unsupportedMarkers(in: format)
            Text(unsupported.isEmpty
                 ? tr("Segnaposto disponibili:") + " {expression} {reading} {furigana} {furigana-plain} {glossary} {glossary-first} {sentence} {cloze-prefix} {cloze-body} {cloze-suffix} {pitch-accents} {frequencies} {frequency-harmonic-rank} {part-of-speech}."
                 : tr("Per ora restano vuoti:") + " " + unsupported.map { "{\($0)}" }.joined(separator: " ") + ". " + tr("Audio e immagini non passano tramite il collegamento di AnkiMobile."))
        }
    }
}
