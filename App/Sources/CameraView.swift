import SwiftUI
import PhotosUI
import Photos
import Vision
import VisionKit
import AVFoundation
import KotobaCore

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
        .onAppear(perform: takeRequest)
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
    @State private var query = ""
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var showingResults = false
    @State private var note: String?

    var body: some View {
        Group {
            if let image {
                PhotoReader(image: image, selecting: selecting,
                            highlightLength: outcome.direct.first?.matchedText.count ?? 0) { text, line in
                    query = text
                    sentence = line
                }
                .ignoresSafeArea(edges: .bottom)
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
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            var result = await model.search(text)
            result.sentence = sentence.isEmpty ? text : sentence
            outcome = result
            showingResults = !result.direct.isEmpty || !result.byMeaning.isEmpty
        }
        .sheet(isPresented: $showingResults) {
            CameraResultsSheet(outcome: outcome, query: query, onOpenInSearch: { text in
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
        query = ""
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
    let onOpenInSearch: (String) -> Void
    @State private var path: [Lookup] = []

    var body: some View {
        NavigationStack(path: $path) {
            ResultsPane(outcome: outcome, query: query, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
                .navigationDestination(for: Lookup.self) { lookup in
                    LookupPage(lookup: lookup, onLookup: { path.append($0) }, onSearch: onOpenInSearch)
                }
                .navigationTitle(outcome.direct.first?.matchedText ?? query)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A line of text found on the photo, with a box for every character
/// (Vision's normalized coordinates: origin bottom-left).
struct OCRLine {
    var text: [Character]
    var boxes: [CGRect]
}

/// A zoomable photo. In tap mode every word is outlined and a tap looks up the
/// text from that character on, like Yomitan; select mode uses Live Text.
struct PhotoReader: UIViewRepresentable {
    let image: UIImage
    var selecting: Bool
    /// How many characters the first result matched, to highlight them.
    var highlightLength: Int
    /// Text from the tapped character on, and its whole line (the Anki sentence).
    let onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black

        let imageView = LayoutImageView()
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
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        imageView.onLayout = { [weak coordinator = context.coordinator] in coordinator?.redraw() }
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        c.onPick = onPick
        c.show(image)
        c.setSelecting(selecting)
        if c.highlightLength != highlightLength {
            c.highlightLength = highlightLength
            c.redraw()
        }
    }

    final class LayoutImageView: UIImageView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
        var onPick: (String, String) -> Void
        let interaction = ImageAnalysisInteraction()
        let analyzer = ImageAnalyzer()
        weak var imageView: UIImageView?
        private var shown: UIImage?
        private var transcript = ""
        private var lines: [OCRLine] = []
        private var selecting = false
        private var tappedAt: (line: Int, index: Int)?
        var highlightLength = 0
        private let overlay = CAShapeLayer()
        private let highlight = CAShapeLayer()

        init(onPick: @escaping (String, String) -> Void) {
            self.onPick = onPick
            super.init()
            interaction.delegate = self
            overlay.fillColor = UIColor.clear.cgColor
            overlay.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
            overlay.lineWidth = 1
            overlay.lineDashPattern = [3, 3]
            highlight.fillColor = UIColor(Palette.shu).withAlphaComponent(0.35).cgColor
            highlight.strokeColor = UIColor(Palette.shu).cgColor
            highlight.lineWidth = 2
        }

        func show(_ image: UIImage) {
            guard shown !== image, let imageView else { return }
            shown = image
            imageView.image = image
            if overlay.superlayer == nil {
                imageView.layer.addSublayer(overlay)
                imageView.layer.addSublayer(highlight)
            }
            lines = []
            tappedAt = nil
            redraw()
            interaction.analysis = nil
            interaction.preferredInteractionTypes = []
            Task {
                var configuration = ImageAnalyzer.Configuration([.text])
                configuration.locales = ["ja-JP", "en-US"]
                guard let analysis = try? await analyzer.analyze(image, configuration: configuration), shown === image else { return }
                interaction.analysis = analysis
                transcript = analysis.transcript
                setSelecting(selecting, force: true)
            }
            guard let cgImage = image.cgImage else { return }
            Task.detached(priority: .userInitiated) {
                let found = Self.recognize(cgImage)
                await MainActor.run { [weak self] in
                    guard let self, self.shown === image else { return }
                    self.lines = found
                    self.redraw()
                }
            }
        }

        func setSelecting(_ on: Bool, force: Bool = false) {
            guard force || on != selecting else { return }
            selecting = on
            interaction.preferredInteractionTypes = on && interaction.analysis != nil ? .textSelection : []
            interaction.selectableItemsHighlighted = on
            overlay.isHidden = on
            highlight.isHidden = on
        }

        nonisolated static func recognize(_ image: CGImage) -> [OCRLine] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let string = candidate.string
                var chars: [Character] = []
                var boxes: [CGRect] = []
                var index = string.startIndex
                while index < string.endIndex {
                    let next = string.index(after: index)
                    let box = (try? candidate.boundingBox(for: index..<next))?.boundingBox ?? .zero
                    chars.append(string[index])
                    boxes.append(box)
                    index = next
                }
                return OCRLine(text: chars, boxes: boxes)
            }
        }

        /// Where the image sits inside the view (aspect fit).
        private var imageRect: CGRect {
            guard let imageView, let image = imageView.image else { return .zero }
            return AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        }

        private func viewRect(_ box: CGRect) -> CGRect {
            let r = imageRect
            return CGRect(x: r.minX + box.minX * r.width, y: r.minY + (1 - box.maxY) * r.height,
                          width: box.width * r.width, height: box.height * r.height)
        }

        func redraw() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard let imageView else { return }
            overlay.frame = imageView.bounds
            highlight.frame = imageView.bounds
            let outlines = UIBezierPath()
            for line in lines {
                let frame = line.boxes.filter { $0 != .zero }.reduce(CGRect.null) { $0.union($1) }
                guard !frame.isNull else { continue }
                outlines.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3))
            }
            overlay.path = outlines.cgPath
            let marked = UIBezierPath()
            if let tappedAt, lines.indices.contains(tappedAt.line) {
                let line = lines[tappedAt.line]
                let end = min(line.boxes.count, tappedAt.index + max(1, highlightLength))
                let frame = line.boxes[tappedAt.index..<end].filter { $0 != .zero }.reduce(CGRect.null) { $0.union($1) }
                if !frame.isNull {
                    marked.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3))
                }
            }
            highlight.path = marked.cgPath
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard !selecting, let imageView else { return }
            let point = gesture.location(in: imageView)
            var best: (line: Int, index: Int, distance: CGFloat)?
            for (l, line) in lines.enumerated() {
                for (i, box) in line.boxes.enumerated() where box != .zero {
                    let rect = viewRect(box)
                    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
                    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < (best?.distance ?? 14) { best = (l, i, distance) }
                }
            }
            guard let best else { return }
            tappedAt = (best.line, best.index)
            highlightLength = 1
            redraw()
            let line = lines[best.line].text
            onPick(String(line[best.index...].prefix(24)), String(line))
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            let selected = interaction.selectedText
            guard !selected.isEmpty else { return }
            let line = transcript.split(separator: "\n").first { $0.contains(selected) }.map(String.init) ?? selected
            onPick(selected, line)
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

// MARK: - Lens

/// Live camera: the word under the crosshair is looked up as you move the phone.
private struct LensView: View {
    @Environment(AppModel.self) private var model
    let onLookup: (Lookup) -> Void
    let onSearch: (String) -> Void

    @State private var query = ""
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var frozen = false
    @State private var cameraAllowed: Bool?

    var body: some View {
        if !LensScanner.available {
            ContentUnavailableView(tr("La lente non è disponibile"), systemImage: "camera.viewfinder",
                                   description: Text(tr("Questo iPhone non riconosce il giapponese dal vivo. Usa la modalità Foto.")))
        } else if cameraAllowed == false {
            ContentUnavailableView(tr("Serve la fotocamera"), systemImage: "camera",
                                   description: Text(tr("Consenti l'accesso in Impostazioni › App › Kotoba › Fotocamera.")))
        } else {
            VStack(spacing: 0) {
                ZStack {
                    if cameraAllowed == true {
                        LensScanner(frozen: frozen) { text, line in
                            query = text
                            sentence = line
                        }
                    } else {
                        Color.black
                    }
                    Reticle()
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                frozen.toggle()
                            } label: {
                                Image(systemName: frozen ? "play.fill" : "pause.fill")
                                    .font(.title3)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .tint(.white)
                            .padding(14)
                        }
                    }
                }
                .clipped()
                Group {
                    if outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                        Text(tr("Inquadra una parola con il mirino. Tocca ⏸ per fermare l'immagine e leggere con calma."))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultsPane(outcome: outcome, query: query, onLookup: onLookup, onSearch: onSearch)
                    }
                }
                .frame(height: 300)
                .background(Palette.paper)
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: cameraAllowed = true
                case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
                default: cameraAllowed = false
                }
            }
            .task(id: query) {
                let text = query
                guard !text.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                var result = await model.search(text)
                guard !result.direct.isEmpty else { return }
                result.sentence = sentence
                outcome = result
            }
        }
    }
}

private struct Reticle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white, lineWidth: 2)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.4), radius: 4)
            Circle().fill(Palette.shu).frame(width: 6, height: 6)
        }
        .allowsHitTesting(false)
    }
}

/// VisionKit's live text scanner; reports the text under the centre of the view.
private struct LensScanner: UIViewControllerRepresentable {
    static var available: Bool {
        DataScannerViewController.isSupported
            && DataScannerViewController.supportedTextRecognitionLanguages.contains { $0.hasPrefix("ja") }
    }

    var frozen: Bool
    let onRead: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRead: onRead) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text(languages: ["ja-JP"])],
                                                qualityLevel: .accurate,
                                                recognizesMultipleItems: true,
                                                isHighFrameRateTrackingEnabled: false,
                                                isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: false,
                                                isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onRead = onRead
        if frozen {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onRead: (String, String) -> Void
        private var last = ""

        init(onRead: @escaping (String, String) -> Void) { self.onRead = onRead }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            pick(in: dataScanner, items: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            pick(in: dataScanner, items: allItems)
        }

        /// Finds the character under the crosshair: projects the centre onto
        /// each line's reading direction (the longer side, so vertical text works).
        private func pick(in scanner: DataScannerViewController, items: [RecognizedItem]) {
            let c = CGPoint(x: scanner.view.bounds.midX, y: scanner.view.bounds.midY)
            var best: (chars: [Character], index: Int, distance: CGFloat)?
            for item in items {
                guard case .text(let text) = item else { continue }
                let chars = Array(text.transcript)
                guard !chars.isEmpty else { continue }
                let q = item.bounds
                var along = CGVector(dx: q.topRight.x - q.topLeft.x, dy: q.topRight.y - q.topLeft.y)
                var across = CGVector(dx: q.bottomLeft.x - q.topLeft.x, dy: q.bottomLeft.y - q.topLeft.y)
                let alongLength = hypot(along.dx, along.dy), acrossLength = hypot(across.dx, across.dy)
                if acrossLength > alongLength * 1.5 && chars.count > 1 { swap(&along, &across) }
                let a2 = along.dx * along.dx + along.dy * along.dy
                let b2 = across.dx * across.dx + across.dy * across.dy
                guard a2 > 1, b2 > 1 else { continue }
                let v = CGVector(dx: c.x - q.topLeft.x, dy: c.y - q.topLeft.y)
                let t = (v.dx * along.dx + v.dy * along.dy) / a2
                let s = (v.dx * across.dx + v.dy * across.dy) / b2
                let distance = max(0, -t, t - 1) * a2.squareRoot() + max(0, -s, s - 1) * b2.squareRoot()
                if distance < (best?.distance ?? 30) {
                    best = (chars, min(chars.count - 1, max(0, Int(t * CGFloat(chars.count)))), distance)
                }
            }
            guard let best else { return }
            let query = String(best.chars[best.index...].prefix(20))
            guard query != last else { return }
            last = query
            onRead(query, String(best.chars))
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
