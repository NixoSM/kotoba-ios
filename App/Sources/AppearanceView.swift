import SwiftUI
import UniformTypeIdentifiers
import KotobaCore

/// Yomitan's display options, with a live preview on top.
struct AppearanceView: View {
    @Environment(AppModel.self) private var model
    @State private var addingFont = false
    @State private var fonts = FontCatalog.all()

    var body: some View {
        @Bindable var model = model
        let a = $model.settings.appearance
        VStack(spacing: 0) {
            ResultsWebView(html: previewHTML, onAction: { _ in })
                .frame(height: 300)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
            Form {
                Section {
                    ThemePicker(selection: a.theme)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(tr("Tema"))
                }

                Section {
                    fontPicker(tr("Testo"), selection: a.bodyFont)
                    fontPicker(tr("Lemma"), selection: a.headwordFont)
                    LabeledContent(tr("Dimensione")) {
                        Stepper("\(Int(a.wrappedValue.fontSize)) pt", value: a.fontSize, in: 12...28, step: 1)
                            .fixedSize()
                    }
                    VStack(alignment: .leading) {
                        LabeledContent(tr("Interlinea"), value: a.wrappedValue.lineHeight.formatted(.number.precision(.fractionLength(2))))
                        Slider(value: a.lineHeight, in: 1.0...2.2, step: 0.05)
                    }
                    Button(tr("Aggiungi un font (.ttf, .otf)…"), systemImage: "textformat") { addingFont = true }
                } header: {
                    Text(tr("Caratteri"))
                } footer: {
                    Text(tr("Klee One, Shippori Mincho e Zen Maru Gothic sono inclusi nell'app. Puoi aggiungere qualsiasi font giapponese che hai in File."))
                }

                Section(tr("Disposizione")) {
                    Picker(tr("Layout"), selection: a.layout) {
                        ForEach(Appearance.Layout.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(tr("Lemma"), selection: a.termDisplay) {
                        ForEach(Appearance.TermDisplay.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle(tr("Nomi dei dizionari"), isOn: a.showDictionaryNames)
                    Toggle(tr("Categorie grammaticali"), isOn: a.showTags)
                }

                Section(tr("Frequenza")) {
                    Picker(tr("Mostra"), selection: a.frequency) {
                        ForEach(Appearance.FrequencyDisplay.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle(tr("Linea sopra la lettura"), isOn: a.pitchNotation)
                    Toggle(tr("Grafico a punti"), isOn: a.pitchGraph)
                    Toggle(tr("Numero [n]"), isOn: a.pitchNumber)
                } header: {
                    Text(tr("Accento"))
                }

                Section {
                    TextEditor(text: a.customCSS)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(tr("CSS personalizzato"))
                } footer: {
                    Text(tr("Come il «Custom CSS» di Yomitan. Esempio: .headword { color: var(--shu); }"))
                }

                Section {
                    Button(tr("Ripristina l'aspetto predefinito"), role: .destructive) {
                        model.settings.appearance = Appearance()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Palette.paper)
        .navigationTitle(tr("Aspetto"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $addingFont, allowedContentTypes: [.font, UTType(filenameExtension: "ttf") ?? .font, UTType(filenameExtension: "otf") ?? .font]) { result in
            guard case .success(let url) = result else { return }
            do {
                let id = try FontCatalog.importFont(from: url)
                fonts = FontCatalog.all()
                model.settings.appearance.bodyFont = id
            } catch {
                model.errorMessage = tr("Non riesco a copiare il font: {0}", error.localizedDescription)
            }
        }
    }

    private func fontPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(fonts) { font in
                Text(font.name)
                    .font(font.postScriptName.map { .kotoba($0, size: 17) } ?? .body)
                    .tag(font.id)
            }
        }
        .pickerStyle(.navigationLink)
    }

    private var previewHTML: String {
        var g = HeadwordGroup(id: "preview", expression: "言葉", reading: "ことば", matchedText: "言葉", reasons: [])
        g.partsOfSpeech = ["n"]
        g.definitions = [
            ("JMdict (Legacy)", ["word", "phrase", "expression", "language"]),
            ("大辞林 第四版", ["①人が声に出して言ったり文字に書いて表したりする、意味のある表現。<br>「―を交わす」"]),
        ]
        // The Italian sample dictionary only in the Italian app.
        if L10n.current == .it {
            g.definitions.insert(("小学館 和伊中辞典 第2版", ["parola, vocabolo; (言語) lingua; (表現) espressione"]), at: 1)
        }
        g.frequencies = [FrequencyInfo(dictionary: "JPDB", value: 312, display: "312"),
                         FrequencyInfo(dictionary: "BCCWJ", value: 845, display: "845")]
        g.pitches = [PitchInfo(dictionary: "アクセント辞典", reading: "ことば", positions: [3])]
        let options = ResultsPage.Options(stylesheets: [:], canMine: true, appearance: model.settings.appearance)
        return ResultsPage.page(body: ResultsPage.entry(g, link: "kotoba://none", options: options), options: options)
    }
}

/// Swatches you can scroll through: each shows the theme's paper, ink and accent.
private struct ThemePicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                swatch(id: "auto", name: tr("Auto"), mark: "自", light: .named("washi"), dark: .named("sumi"))
                ForEach(ThemePalette.all) { theme in
                    swatch(id: theme.id, name: theme.label, mark: theme.mark, light: theme, dark: theme)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private func swatch(id: String, name: String, mark: String, light: ThemePalette, dark: ThemePalette) -> some View {
        let selected = selection == id
        return Button { selection = id } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 0) {
                        tile(light, mark: mark)
                        if light != dark { tile(dark, mark: mark) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    Rectangle().fill(Color(UIColor(hex: light.accent))).frame(width: 7, height: 24).padding(.trailing, 12)
                }
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Palette.shu : Palette.rule, lineWidth: selected ? 2.5 : 1))
                Text(name).font(.caption.weight(selected ? .semibold : .regular)).foregroundStyle(selected ? Palette.shu : Palette.muted)
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ p: ThemePalette, mark: String) -> some View {
        Text(mark)
            .font(.mincho(30, bold: true))
            .foregroundStyle(Color(UIColor(hex: p.ink)))
            .frame(width: 41, height: 78)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor(hex: p.paper)))
    }
}
