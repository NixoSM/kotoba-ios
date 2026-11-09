import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KotobaCore

/// "Kotoba" in the Share sheet. With the dictionaries shared with the app it
/// shows the definitions in a panel over the app you are reading; otherwise it
/// opens Kotoba with the search done.
final class ShareViewController: UIViewController {
    private var started = false

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .overFullScreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        URLOpener.responder = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await start() }
    }

    private func start() async {
        guard let text = await sharedText() else { return finish() }
        if SharedStorage.databaseIsShared {
            showPanel(text)
        } else {
            openInApp(text)
        }
    }

    private func showPanel(_ text: String) {
        let model = AppModel()
        let panel = SharePanel(model: model, text: String(text.prefix(300)),
                               close: { [weak self] in self?.finish() },
                               openInApp: { [weak self] query in self?.openInApp(query) })
        let host = UIHostingController(rootView: panel)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func openInApp(_ text: String) {
        var components = URLComponents(string: "kotoba://search")
        components?.queryItems = [URLQueryItem(name: "q", value: String(text.prefix(300)))]
        guard let url = components?.url else { return finish() }
        URLOpener.open(url) { [weak self] _ in self?.finish() }
    }

    private func sharedText() async -> String? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    let text = (value as? String) ?? (value as? NSAttributedString)?.string
                    if let text = cleaned(text) { return text }
                }
            }
            if let text = cleaned(item.attributedContentText?.string) { return text }
        }
        return nil
    }

    private func cleaned(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// The panel: the shared text (tap a character to look up from there),
/// then the same results as in the app, with audio and Anki.
struct SharePanel: View {
    let model: AppModel
    let text: String
    let close: () -> Void
    let openInApp: (String) -> Void

    @State private var start = 0
    @State private var outcome = AppModel.SearchOutcome()
    @State private var path: [Lookup] = []
    @State private var shown = false

    private var characters: [Character] { Array(text) }
    private var query: String { String(characters[min(start, characters.count - 1)...]) }
    private var matched: Int { outcome.direct.first?.matchedText.count ?? 0 }
    private var showsStrip: Bool { characters.count > 1 && Kana.containsJapanese(text) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(shown ? 0.28 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)
                VStack(spacing: 0) {
                    Capsule().fill(Palette.rule).frame(width: 38, height: 5).padding(.top, 8)
                    HStack(spacing: 10) {
                        if showsStrip { strip } else {
                            Text(text).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer()
                        }
                        Button { openInApp(query) } label: {
                            Image(systemName: "arrow.up.forward.app").font(.title3)
                        }
                        .accessibilityLabel(tr("Apri in Kotoba"))
                        Button(action: dismiss) {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Palette.muted)
                        }
                        .accessibilityLabel(tr("Chiudi"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Rectangle().fill(Palette.rule).frame(height: 1)
                    NavigationStack(path: $path) {
                        ResultsPane(outcome: outcome, query: query,
                                    onLookup: { path.append($0) }, onSearch: openInApp)
                            .toolbar(path.isEmpty ? .hidden : .visible, for: .navigationBar)
                            .navigationDestination(for: Lookup.self) { lookup in
                                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: openInApp)
                            }
                    }
                }
                .frame(height: geometry.size.height * 0.62 + geometry.safeAreaInsets.bottom)
                .background(Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                .offset(y: shown ? 0 : geometry.size.height)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .tint(Palette.shu)
        .preferredColorScheme(ThemePalette.colorScheme(for: model.settings.appearance.theme))
        .environment(model)
        .onAppear { withAnimation(.snappy(duration: 0.3)) { shown = true } }
        .task(id: start) {
            var result = await model.search(query)
            // Another character was tapped meanwhile: keep only the latest answer.
            guard !Task.isCancelled else { return }
            result.sentence = text
            outcome = result
        }
    }

    /// The selected text, one tappable character at a time.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(characters.indices, id: \.self) { i in
                    let inMatch = i >= start && i < start + max(matched, 1)
                    Text(String(characters[i]))
                        .font(.mincho(22, bold: inMatch))
                        .foregroundStyle(inMatch ? Palette.shu : Palette.ink)
                        .padding(.horizontal, 1)
                        .padding(.vertical, 4)
                        .background(inMatch ? Palette.shu.opacity(0.12) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { start = i; path = [] }
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.snappy(duration: 0.25)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: close)
    }
}
