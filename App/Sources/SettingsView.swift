import SwiftUI
import UniformTypeIdentifiers
import Photos
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
                    Toggle(isOn: $model.settings.clipboardLookup) {
                        Label(tr("Cerca quello che copi"), systemImage: "doc.on.clipboard")
                    }
                    Toggle(isOn: Binding(
                        get: { model.settings.screenshotLookup },
                        set: { on in
                            guard on else { model.settings.screenshotLookup = false; return }
                            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                                Task { @MainActor in
                                    model.settings.screenshotLookup = status == .authorized || status == .limited
                                }
                            }
                        })) {
                        Label(tr("Apri gli screenshot appena fatti"), systemImage: "camera.metering.matrix")
                    }
                    NavigationLink {
                        QuickLookupGuide()
                    } label: {
                        Label(tr("Scorciatoie e doppio tocco sul retro"), systemImage: "hand.tap")
                    }
                } header: {
                    Text(tr("Ricerca rapida"))
                } footer: {
                    Text(tr("Copia una parola in qualsiasi app e torna su Kotoba: la cerca da sola. Perché iOS non lo chieda ogni volta: Impostazioni › App › Kotoba › Incolla da altre app › Consenti."))
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

/// How to reach Kotoba without opening it: Control Center, Lock Screen, Back Tap, Share.
private struct QuickLookupGuide: View {
    var body: some View {
        List {
            step("square.and.arrow.up", tr("Dal menu Condividi"),
                 tr("Seleziona del testo in qualsiasi app, tocca Condividi e poi Kotoba: la definizione appare in un pannello, senza lasciare l'app in cui leggi."))
            step("switch.2", tr("Centro di Controllo"),
                 tr("Apri il Centro di Controllo, tieni premuto su uno spazio vuoto, tocca «Aggiungi un controllo» e cerca Kotoba: «Cerca appunti» e «Lente»."))
            step("lock", tr("Schermata di blocco"),
                 tr("Tieni premuto sulla schermata di blocco, tocca Personalizza › Schermata di blocco e sostituisci la torcia o la fotocamera con un controllo di Kotoba."))
            step("hand.tap", tr("Doppio tocco sul retro"),
                 tr("1. Nell'app Comandi Rapidi crea un comando con l'azione Kotoba «Cerca negli appunti». 2. Impostazioni › Accessibilità › Tocco › Tocca il retro › Doppio tocco: scegli quel comando. Poi copia una parola e tocca due volte il retro dell'iPhone."))
            step("waveform", "Siri", tr("«Cerca gli appunti in Kotoba» oppure «Apri la lente di Kotoba»."))
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .navigationTitle(tr("Ricerca rapida"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.shu).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
