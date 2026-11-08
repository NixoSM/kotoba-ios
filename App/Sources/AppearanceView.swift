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
                Section("Tema") {
                    Picker("Tema", selection: a.theme) {
                        ForEach(Appearance.Theme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    fontPicker("Testo", selection: a.bodyFont)
                    fontPicker("Lemma", selection: a.headwordFont)
                    LabeledContent("Dimensione") {
                        Stepper("\(Int(a.wrappedValue.fontSize)) pt", value: a.fontSize, in: 12...28, step: 1)
                            .fixedSize()
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Interlinea", value: a.wrappedValue.lineHeight.formatted(.number.precision(.fractionLength(2))))
                        Slider(value: a.lineHeight, in: 1.0...2.2, step: 0.05)
                    }
                    Button("Aggiungi un font (.ttf, .otf)…", systemImage: "textformat") { addingFont = true }
                } header: {
                    Text("Caratteri")
                } footer: {
                    Text("Klee One, Shippori Mincho e Zen Maru Gothic sono inclusi nell'app. Puoi aggiungere qualsiasi font giapponese che hai in File.")
                }

                Section("Disposizione") {
                    Picker("Layout", selection: a.layout) {
                        ForEach(Appearance.Layout.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Lemma", selection: a.termDisplay) {
                        ForEach(Appearance.TermDisplay.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Nomi dei dizionari", isOn: a.showDictionaryNames)
                    Toggle("Categorie grammaticali", isOn: a.showTags)
                }

                Section("Frequenza") {
                    Picker("Mostra", selection: a.frequency) {
                        ForEach(Appearance.FrequencyDisplay.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle("Linea sopra la lettura", isOn: a.pitchNotation)
                    Toggle("Grafico a punti", isOn: a.pitchGraph)
                    Toggle("Numero [n]", isOn: a.pitchNumber)
                } header: {
                    Text("Accento")
                }

                Section {
                    TextEditor(text: a.customCSS)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("CSS personalizzato")
                } footer: {
                    Text("Come il «Custom CSS» di Yomitan. Esempio: .headword { color: var(--shu); }")
                }

                Section {
                    Button("Ripristina l'aspetto predefinito", role: .destructive) {
                        model.settings.appearance = Appearance()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Palette.paper)
        .navigationTitle("Aspetto")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $addingFont, allowedContentTypes: [.font, UTType(filenameExtension: "ttf") ?? .font, UTType(filenameExtension: "otf") ?? .font]) { result in
            guard case .success(let url) = result else { return }
            do {
                let id = try FontCatalog.importFont(from: url)
                fonts = FontCatalog.all()
                model.settings.appearance.bodyFont = id
            } catch {
                model.errorMessage = "Non riesco a copiare il font: \(error.localizedDescription)"
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
            ("小学館 和伊中辞典 第2版", ["parola, vocabolo; (言語) lingua; (表現) espressione"]),
            ("大辞林 第四版", ["①人が声に出して言ったり文字に書いて表したりする、意味のある表現。<br>「―を交わす」"]),
        ]
        g.frequencies = [FrequencyInfo(dictionary: "JPDB", value: 312, display: "312"),
                         FrequencyInfo(dictionary: "BCCWJ", value: 845, display: "845")]
        g.pitches = [PitchInfo(dictionary: "アクセント辞典", reading: "ことば", positions: [3])]
        let options = ResultsPage.Options(stylesheets: [:], canMine: true, appearance: model.settings.appearance)
        return ResultsPage.page(body: ResultsPage.entry(g, link: "kotoba://none", options: options), options: options)
    }
}
