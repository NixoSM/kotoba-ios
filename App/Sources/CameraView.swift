import SwiftUI
import PhotosUI
import Photos
import Vision
import VisionKit
import AVFoundation
import KotobaCore
import KotobaOCR

/// Two ways to read Japanese around you:
/// the lens (live camera, the word under the crosshair is looked up as you move)
/// and photos/screenshots (tap any word, or select with Live Text).
struct CameraView: View {
    @Environment(AppModel.self) private var model
    let onLookup: (String) -> Void

    enum Mode: Hashable { case lens, photo }
    @State private var mode = Mode.photo
    @State private var path: [Lookup] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .lens: LensView(onLookup: { path.append($0) }, onSearch: onLookup)
                case .photo: PhotoView(onSearch: onLookup)
                }
            }
            .background(Palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        Text(tr("Lente")).tag(Mode.lens)
                        Text(tr("Foto")).tag(Mode.photo)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .navigationDestination(for: Lookup.self) { lookup in
                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: onLookup)
            }
        }
        .onAppear {
            WordFinder.shared.attach(model.store)
            takeRequest()
        }
        .onChange(of: model.cameraRequest) { _, _ in takeRequest() }
    }

    private func takeRequest() {
        guard let request = model.cameraRequest else { return }
        path = []
        switch request {
        case .lens:
            mode = .lens
            model.cameraRequest = nil
        case .screenshot:
            mode = .photo
        }
    }
}

// MARK: - Photos and screenshots

private struct PhotoView: View {
    @Environment(AppModel.self) private var model
    let onSearch: (String) -> Void

    @State private var image: UIImage?
    @State private var takingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var selecting = false
    @State private var pick: WordAim.Pick?
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var showingResults = false
    @State private var readingPage = false
    @State private var note: String?
    /// 0: decide from the page, 1: 横 (horizontal), 2: 縦 (vertical).
    @AppStorage("photoOrientation") private var orientation = 0

    private var query: String { pick?.query ?? "" }

    var body: some View {
        Group {
            if let image {
                PhotoReader(image: image, vertical: orientation == 0 ? nil : orientation == 2, selecting: selecting,
                            pick: pick, pendingTap: nil,
                            onMiss: { selecting = true }, onReading: { readingPage = $0 }) { picked, around in
                    pick = picked
                    sentence = around
                }
                .id(orientation)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottomLeading) {
                    if readingPage {
                        Label(tr("Leggo la pagina…"), systemImage: "text.viewfinder")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(14)
                    }
                }
                .overlay(alignment: .top) {
                    Picker("", selection: $selecting) {
                        Text(tr("Tocca")).tag(false)
                        Text(tr("Seleziona")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                }
            } else {
                ContentUnavailableView {
                    Label(tr("Leggi dal mondo reale"), systemImage: "text.viewfinder")
                } description: {
                    Text(tr("Scatta una foto, scegline una o apri il tuo ultimo screenshot. Poi tocca una parola giapponese: la definizione appare qui sotto."))
                } actions: {
                    VStack(spacing: 10) {
                        Button(tr("Ultimo screenshot"), systemImage: "camera.metering.matrix") { Task { await openScreenshot(id: nil) } }
                            .buttonStyle(.borderedProminent)
                        HStack {
                            Button(tr("Scatta foto")) { takingPhoto = true }
                                .buttonStyle(.bordered)
                            PhotosPicker(tr("Dalla libreria"), selection: $pickerItem, matching: .images)
                                .buttonStyle(.bordered)
                        }
                        if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .toolbar {
            if image != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(tr("Direzione del testo"), selection: $orientation) {
                            Text(tr("Automatica")).tag(0)
                            Text(tr("横 orizzontale")).tag(1)
                            Text(tr("縦 verticale")).tag(2)
                        }
                    } label: { Image(systemName: orientation == 2 ? "text.alignright" : orientation == 1 ? "text.alignleft" : "textformat") }
                    Menu {
                        Button(tr("Ultimo screenshot"), systemImage: "camera.metering.matrix") { Task { await openScreenshot(id: nil) } }
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label(tr("Dalla libreria"), systemImage: "photo.on.rectangle") }
                        Button(tr("Scatta foto"), systemImage: "camera") { takingPhoto = true }
                    } label: { Image(systemName: "plus.viewfinder") }
                }
            }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraCapture { show($0) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    show(picked)
                }
                pickerItem = nil
            }
        }
        .task { await takeScreenshotRequest() }
        .onChange(of: model.cameraRequest) { _, _ in Task { await takeScreenshotRequest() } }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            var result = await model.search(text)
            guard !Task.isCancelled else { return }
            result.sentence = sentence.isEmpty ? text : sentence
            outcome = result
            showingResults = !result.direct.isEmpty || !result.byMeaning.isEmpty || pick != nil
        }
        .sheet(isPresented: $showingResults) {
            CameraResultsSheet(outcome: outcome, query: query, pick: pick, onSelect: { index in
                if let current = pick, let moved = WordFinder.shared.pick(in: current.text, start: index) { pick = moved }
            }, onOpenInSearch: { text in
                showingResults = false
                onSearch(text)
            })
            .presentationDetents([.fraction(0.4), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
            .presentationDragIndicator(.visible)
        }
    }

    private func show(_ picked: UIImage) {
        image = picked.uprighted()
        pick = nil
        sentence = ""
        outcome = AppModel.SearchOutcome()
        showingResults = false
        selecting = false
    }

    private func takeScreenshotRequest() async {
        guard case .screenshot(let id) = model.cameraRequest else { return }
        model.cameraRequest = nil
        await openScreenshot(id: id)
    }

    private func openScreenshot(id: String?) async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else {
            note = tr("Kotoba non può vedere le foto: Impostazioni › App › Kotoba › Foto.")
            return
        }
        let asset = id.flatMap { PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject } ?? AppModel.latestScreenshot()
        guard let asset else {
            note = tr("Non trovo screenshot.")
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let picked: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize,
                                                  contentMode: .default, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let picked { show(picked) }
    }
}

private struct CameraResultsSheet: View {
    let outcome: AppModel.SearchOutcome
    let query: String
    let pick: WordAim.Pick?
    let onSelect: (Int) -> Void
    let onOpenInSearch: (String) -> Void
    @State private var path: [Lookup] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let pick {
                    ContextStrip(pick: pick, onSelect: onSelect)
                    Divider()
                }
                if outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    Text(tr("Nessuna parola qui. Tocca un altro carattere nella riga sopra."))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ResultsPane(outcome: outcome, query: query, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
                }
            }
            .navigationDestination(for: Lookup.self) { lookup in
                LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
            }
            .navigationTitle(outcome.direct.first?.matchedText ?? query)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension UIImage {
    /// Redrawn with the orientation baked in, so Vision's boxes match the pixels.
    func uprighted() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
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
