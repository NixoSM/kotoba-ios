import SwiftUI
import PhotosUI
import VisionKit
import KotobaCore

/// Take or pick a photo, select Japanese text on it with Apple's Live Text
/// (which also reads vertical text), and see the definitions right below.
struct CameraView: View {
    @Environment(AppModel.self) private var model
    let onLookup: (String) -> Void

    @State private var image: UIImage?
    @State private var takingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selection = ""
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    LiveTextImageView(image: image) { selected, line in
                        selection = selected
                        sentence = line
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView {
                        Label("Leggi dal mondo reale", systemImage: "text.viewfinder")
                    } description: {
                        Text("Scatta una foto o scegline una. Poi tieni premuto sul testo giapponese, anche verticale, e trascina per selezionare la parola: la definizione appare qui sotto.")
                    } actions: {
                        HStack {
                            Button("Scatta foto") { takingPhoto = true }
                                .buttonStyle(.borderedProminent)
                            PhotosPicker("Dalla libreria", selection: $pickerItem, matching: .images)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Fotocamera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if image != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        PhotosPicker(selection: $pickerItem, matching: .images) { Image(systemName: "photo.on.rectangle") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { takingPhoto = true } label: { Image(systemName: "camera") }
                    }
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraCapture { image = $0; reset() }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        image = picked
                        reset()
                    }
                }
            }
            .task(id: selection) {
                let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                var result = await model.search(text)
                result.sentence = sentence.isEmpty ? text : sentence
                outcome = result
                showingResults = !result.direct.isEmpty || !result.byMeaning.isEmpty
            }
            .sheet(isPresented: $showingResults) {
                CameraResultsSheet(outcome: outcome, query: selection, onOpenInSearch: { onLookup(selection) })
                    .presentationDetents([.fraction(0.4), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func reset() {
        selection = ""
        sentence = ""
        showingResults = false
    }
}

private struct CameraResultsSheet: View {
    @Environment(AppModel.self) private var model
    let outcome: AppModel.SearchOutcome
    let query: String
    let onOpenInSearch: () -> Void

    var body: some View {
        NavigationStack {
            ResultsWebView(html: ResultsPage.html(outcome: outcome, query: query, stylesheets: model.stylesheets,
                                                  indexStatus: nil, mined: model.settings.mined,
                                                  canMine: model.settings.ankiFormat != nil)) { url in
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
                if url.host == "mine", let s = value("s"), let i = value("i").flatMap(Int.init), let g = outcome.group(section: s, index: i) {
                    model.mine(g, sentence: outcome.sentence)
                } else if url.host == "search", let q = value("q") {
                    model.pendingQuery = q
                    onOpenInSearch()
                }
            }
            .navigationTitle(query)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A zoomable photo with Live Text selection.
struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    /// Selected text, and the whole line it sits in (used as the Anki sentence).
    let onSelection: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        imageView.addInteraction(context.coordinator.interaction)
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSelection = onSelection
        context.coordinator.show(image)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
        var onSelection: (String, String) -> Void
        let interaction = ImageAnalysisInteraction()
        let analyzer = ImageAnalyzer()
        weak var imageView: UIImageView?
        private var shown: UIImage?
        private var transcript = ""

        init(onSelection: @escaping (String, String) -> Void) {
            self.onSelection = onSelection
            super.init()
            interaction.delegate = self
        }

        func show(_ image: UIImage) {
            guard shown !== image else { return }
            shown = image
            imageView?.image = image
            interaction.analysis = nil
            interaction.preferredInteractionTypes = []
            Task {
                var configuration = ImageAnalyzer.Configuration([.text])
                configuration.locales = ["ja-JP", "en-US"]
                guard let analysis = try? await analyzer.analyze(image, configuration: configuration), shown === image else { return }
                interaction.analysis = analysis
                interaction.preferredInteractionTypes = .textSelection
                interaction.selectableItemsHighlighted = true
                transcript = analysis.transcript
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            let selected = interaction.selectedText
            let line = transcript.split(separator: "\n").first { $0.contains(selected) }.map(String.init) ?? selected
            onSelection(selected, line)
        }
    }
}

/// The system camera, for one photo.
private struct CameraCapture: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
