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
                        SettingsDoor(glyph: "字", title: tr("Aspetto"), detail: appearanceSummary)
                    }
                    NavigationLink {
                        DictionariesView()
                    } label: {
                        SettingsDoor(glyph: "辞", title: tr("Dizionari"), detail: dictionariesSummary)
                    }
                    NavigationLink {
                        AnkiSettingsView()
                    } label: {
                        SettingsDoor(glyph: "札", title: "Anki", detail: ankiSummary)
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

                AboutSection()
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

    private var appearanceSummary: String {
        let a = model.settings.appearance
        return "\(FontCatalog.choice(a.bodyFont).name) · \(Int(a.fontSize)) pt · \(a.layout.label)"
    }

    private var dictionariesSummary: String {
        if case .running(let title, _, _, _) = model.importStatus { return tr("Importo {0}…", title) }
        if model.dictionaries.isEmpty { return tr("Nessuno: tocca per importarne uno") }
        let on = model.dictionaries.filter(\.enabled).count
        return on == model.dictionaries.count
            ? tr("{0} installati", model.dictionaries.count)
            : tr("{0} installati, {1} attivi", model.dictionaries.count, on)
    }

    private var ankiSummary: String {
        guard let format = model.settings.ankiFormat else { return tr("Non configurato") }
        return "\(format.model) → \(format.deck)"
    }
}

/// A row that leads to a page of settings: a kanji in a vermilion square, like a door plate.
private struct SettingsDoor: View {
    let glyph: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Text(glyph).font(.mincho(26, bold: true)).foregroundStyle(Palette.shu)
                .frame(width: 40, height: 40)
                .background(Palette.shu.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

/// Version, how long the signature lasts, and the way to the diagnostics page.
private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent(tr("Versione"), value: AppVersion.text)
            if let expiry = SigningInfo.current {
                LabeledContent(tr("Firma"), value: SignatureText.status(expiry: expiry))
            }
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label(tr("Diagnostica"), systemImage: "stethoscope")
            }
        } header: {
            Text(tr("Informazioni"))
        } footer: {
            if SigningInfo.current != nil {
                Text(tr("Con un Apple ID gratuito l'app si apre per 7 giorni dall'installazione. Reinstallala con Sideloadly prima della scadenza: dizionari e impostazioni restano."))
            }
        }
    }
}

enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// The signature's expiry in words.
enum SignatureText {
    static func status(expiry: Date, now: Date = Date()) -> String {
        switch SigningInfo.notice(expiry: expiry, now: now) {
        case .expired: tr("scaduta")
        case .soon(let days): soon(days)
        case .none: tr("valida fino al {0}", expiry.formatted(date: .abbreviated, time: .shortened))
        }
    }

    /// The sentence for the home screen; nil while there is nothing to worry about.
    static func warning(expiry: Date?, now: Date = Date()) -> String? {
        switch SigningInfo.notice(expiry: expiry, now: now) {
        case .none: nil
        case .expired: tr("La firma dell'app è scaduta: alla prossima apertura non partirà. Reinstallala con Sideloadly; dizionari e impostazioni restano.")
        case .soon(let days): tr("La firma dell'app {0}. Reinstallala con Sideloadly per continuare a usarla; dizionari e impostazioni restano.", soon(days))
        }
    }

    private static func soon(_ days: Int) -> String {
        switch days {
        case 0: tr("scade oggi")
        case 1: tr("scade domani")
        default: tr("scade tra {0} giorni", days)
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
