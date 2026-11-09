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
                            highlightLength: outcome.direct.first?.matchedText.count ?? 0,
                            onMiss: { selecting = true }) { text, line in
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

/// A zoomable photo. In tap mode every word is outlined and a tap looks up the
/// text from that character on, like Yomitan; select mode uses Live Text.
struct PhotoReader: UIViewRepresentable {
    let image: UIImage
    var selecting: Bool
    /// How many characters the first result matched, to highlight them.
    var highlightLength: Int
    /// A tap found no text there (often vertical text, which only Live Text reads).
    var onMiss: (() -> Void)? = nil
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
        c.onMiss = onMiss
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
        var onMiss: (() -> Void)?
        let interaction = ImageAnalysisInteraction()
        let analyzer = ImageAnalyzer()
        weak var imageView: UIImageView?
        private var shown: UIImage?
        private var transcript = ""
        private var lines: [OCRLine] = []
        /// Grayscale copy for reading vertical text, made on the first tap that needs it.
        private var gray: GrayImage?
        private var readingVertical = false
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
            gray = nil
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
            if let tappedAt, lines.indices.contains(tappedAt.line), tappedAt.index < lines[tappedAt.line].boxes.count {
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
            guard let best else {
                readVertical(at: point)
                return
            }
            tappedAt = (best.line, best.index)
            highlightLength = 1
            redraw()
            let line = lines[best.line].text
            onPick(String(line[best.index...].prefix(24)), String(line))
        }

        /// Vertical text: VerticalOCR reads the column under the tap.
        private func readVertical(at point: CGPoint) {
            guard !readingVertical, let image = shown, let cgImage = image.cgImage else { return }
            let r = imageRect
            guard r.width > 0, r.contains(point) else { return }
            let fx = (point.x - r.minX) / r.width, fy = (point.y - r.minY) / r.height
            readingVertical = true
            let cached = gray
            Task.detached(priority: .userInitiated) {
                let gray = cached ?? GrayImage(cgImage: cgImage)
                let result = gray.flatMap { VerticalOCR.read($0, at: CGPoint(x: fx * CGFloat($0.width), y: fy * CGFloat($0.height))) }
                await MainActor.run { [weak self] in
                    guard let self, self.shown === image else { return }
                    self.readingVertical = false
                    self.gray = gray
                    guard let result else {
                        // Still nothing: let Live Text try (selection mode).
                        if self.interaction.analysisHasText(at: point) { self.onMiss?() }
                        return
                    }
                    self.lines.append(result.line)
                    self.tappedAt = (self.lines.count - 1, result.hit)
                    self.highlightLength = 1
                    self.redraw()
                    let text = result.line.text
                    self.onPick(String(text[result.hit...].prefix(24)), String(text))
                }
            }
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
/// Vision reads a band around the crosshair and gives a box for every
/// character, so the lookup starts exactly at the character under the dot.
/// Pause freezes the picture into a photo you can tap or select (vertical text too).
private struct LensView: View {
    @Environment(AppModel.self) private var model
    let onLookup: (Lookup) -> Void
    let onSearch: (String) -> Void

    @State private var lens = LensController()
    @State private var query = ""
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var frozen: UIImage?
    @State private var selecting = false
    @State private var cameraAllowed: Bool?
    /// 縦: vertical text, read with Live Text's scanner instead of Vision.
    @AppStorage("lensVertical") private var vertical = false

    var body: some View {
        if cameraAllowed == false {
            ContentUnavailableView(tr("Serve la fotocamera"), systemImage: "camera",
                                   description: Text(tr("Consenti l'accesso in Impostazioni › App › Kotoba › Fotocamera.")))
        } else {
            VStack(spacing: 0) {
                ZStack {
                    if let frozen {
                        PhotoReader(image: frozen, selecting: selecting, highlightLength: matched, onMiss: { selecting = true }) { text, line in
                            query = text
                            sentence = line
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
                    } else if cameraAllowed == true {
                        LiveReader(controller: lens, vertical: vertical, highlightLength: matched) { text, line in
                            query = text
                            sentence = line
                        }
                        Reticle()
                        VStack {
                            HStack {
                                Picker("", selection: $vertical) {
                                    Text("横").tag(false)
                                    Text("縦").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 96)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(10)
                                Spacer()
                            }
                            Spacer()
                        }
                    } else {
                        Color.black
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: toggleFreeze) {
                                Image(systemName: frozen == nil ? "pause.fill" : "play.fill")
                                    .font(.title3)
                                    .frame(width: 52, height: 52)
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
                        Text(frozen == nil
                             ? (vertical
                                ? tr("縦: metti il punto rosso sul primo carattere della parola, con le colonne dritte sullo schermo.")
                                : tr("Metti il punto rosso sul primo carattere della parola. Per i libri in verticale scegli 縦 in alto."))
                             : tr("Tocca una parola, anche nel testo verticale. Seleziona usa invece Live Text."))
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
            .onAppear { if frozen == nil { lens.start() } }
            .onDisappear { lens.stop() }
            .task(id: query) {
                let text = query
                guard !text.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                var result = await model.search(text)
                guard !result.direct.isEmpty || frozen != nil else { return }
                result.sentence = sentence
                outcome = result
            }
        }
    }

    private var matched: Int { outcome.direct.first?.matchedText.count ?? 0 }

    private func toggleFreeze() {
        if frozen != nil {
            frozen = nil
            selecting = false
            lens.start()
        } else {
            Task {
                guard let still = await lens.snapshot() else { return }
                lens.stop()
                frozen = still
                selecting = false
            }
        }
    }
}

private struct Reticle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.4), radius: 3)
            Circle().fill(Palette.shu).frame(width: 7, height: 7)
                .overlay(Circle().stroke(.white, lineWidth: 1))
        }
        .allowsHitTesting(false)
    }
}

/// Lets the SwiftUI view start, stop and photograph the live reader.
@MainActor
final class LensController {
    fileprivate weak var view: LiveReaderView?
    private(set) var wantsRunning = false

    func start() {
        wantsRunning = true
        view?.start()
    }

    func stop() {
        wantsRunning = false
        view?.stop()
    }

    func snapshot() async -> UIImage? { view?.snapshot() }

    fileprivate func attach(_ view: LiveReaderView) {
        self.view = view
        if wantsRunning { view.start() }
    }
}

private struct LiveReader: UIViewRepresentable {
    let controller: LensController
    var vertical: Bool
    var highlightLength: Int
    let onRead: (String, String) -> Void

    func makeUIView(context: Context) -> LiveReaderView {
        let view = LiveReaderView()
        view.onRead = onRead
        controller.attach(view)
        return view
    }

    func updateUIView(_ view: LiveReaderView, context: Context) {
        view.onRead = onRead
        view.vertical = vertical
        view.highlightLength = highlightLength
    }

    static func dismantleUIView(_ view: LiveReaderView, coordinator: ()) {
        view.stop()
    }
}

/// Camera preview plus Vision text recognition around the centre.
final class LiveReaderView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var onRead: ((String, String) -> Void)?
    var highlightLength = 1 { didSet { if highlightLength != oldValue { redraw() } } }
    /// 縦書き: read the column under the dot with VerticalOCR.
    var vertical = false {
        didSet {
            guard vertical != oldValue else { return }
            let on = vertical
            queue.async { [weak self] in self?.verticalMode = on }
            lines = []
            hit = nil
            lastQuery = ""
            redraw()
        }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kotoba.lens")
    private var device: AVCaptureDevice?
    private var configured = false
    private let outlines = CAShapeLayer()
    private let marked = CAShapeLayer()

    // Main thread state.
    private var lines: [OCRLine] = []
    private var hit: (line: Int, index: Int)?
    private var imageSize = CGSize(width: 1080, height: 1920)
    private var lastQuery = ""
    private var latestFrame: CVPixelBuffer?

    // Capture queue state.
    nonisolated(unsafe) private var busy = false
    nonisolated(unsafe) private var lastRun: CFTimeInterval = 0
    nonisolated(unsafe) private var regionOfInterest = CGRect(x: 0.05, y: 0.35, width: 0.9, height: 0.3)
    nonisolated(unsafe) private var verticalMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        preview.videoGravity = .resizeAspectFill
        preview.session = session
        outlines.fillColor = UIColor.clear.cgColor
        outlines.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        outlines.lineWidth = 1
        outlines.lineDashPattern = [3, 3]
        marked.fillColor = UIColor(Palette.shu).withAlphaComponent(0.3).cgColor
        marked.strokeColor = UIColor(Palette.shu).cgColor
        marked.lineWidth = 2
        layer.addSublayer(outlines)
        layer.addSublayer(marked)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    func start() {
        if !configured { configure() }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    private func configure() {
        configured = true
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        device = camera
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        // Portrait frames, so Vision's coordinates match the screen.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        if (try? camera.lockForConfiguration()) != nil {
            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
            if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
            camera.unlockForConfiguration()
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard let device, gesture.state == .changed, (try? device.lockForConfiguration()) != nil else { return }
        let zoom = device.videoZoomFactor * gesture.scale
        device.videoZoomFactor = min(max(1, zoom), min(6, device.activeFormat.videoMaxZoomFactor))
        device.unlockForConfiguration()
        gesture.scale = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outlines.frame = bounds
        marked.frame = bounds
        updateRegion()
        redraw()
    }

    // MARK: Geometry

    /// The image as shown (aspect fill), in view coordinates.
    private var shownImageRect: CGRect {
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Vision box (normalized, origin bottom-left) to view rect.
    private func viewRect(_ box: CGRect) -> CGRect {
        let r = shownImageRect
        return CGRect(x: r.minX + box.minX * r.width, y: r.minY + (1 - box.maxY) * r.height,
                      width: box.width * r.width, height: box.height * r.height)
    }

    /// Read only a band around the crosshair: faster, and nothing off-screen.
    private func updateRegion() {
        let r = shownImageRect
        guard r.width > 0, r.height > 0, bounds.height > 0 else { return }
        let visibleWidth = min(1, bounds.width / r.width)
        let bandHeight = min(1, bounds.height * 0.45 / r.height)
        let region = CGRect(x: 0.5 - visibleWidth / 2, y: 0.5 - bandHeight / 2, width: visibleWidth, height: bandHeight)
        queue.async { [weak self] in self?.regionOfInterest = region }
    }

    // MARK: Recognition

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard !busy, now - lastRun > 0.2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        lastRun = now
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        nonisolated(unsafe) let frame = buffer
        if verticalMode {
            var found: [OCRLine] = []
            if let gray = GrayImage(pixelBuffer: buffer),
               let result = VerticalOCR.read(gray, at: CGPoint(x: gray.width / 2, y: gray.height / 2)) {
                found = [result.line]
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.imageSize = size
                self.latestFrame = frame
                self.update(found)
                self.queue.async { self.busy = false }
            }
            return
        }
        let region = regionOfInterest
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.regionOfInterest = region
        try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
        let found: [OCRLine] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string
            var chars: [Character] = []
            var boxes: [CGRect] = []
            var index = string.startIndex
            while index < string.endIndex {
                let next = string.index(after: index)
                var box = (try? candidate.boundingBox(for: index..<next))?.boundingBox ?? .zero
                if box != .zero {
                    // Results are relative to the region of interest.
                    box = CGRect(x: region.minX + box.minX * region.width, y: region.minY + box.minY * region.height,
                                 width: box.width * region.width, height: box.height * region.height)
                }
                chars.append(string[index])
                boxes.append(box)
                index = next
            }
            return OCRLine(text: chars, boxes: boxes)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.imageSize = size
            self.latestFrame = frame
            self.update(found)
            self.queue.async { self.busy = false }
        }
    }

    private func update(_ found: [OCRLine]) {
        lines = found
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var best: (line: Int, index: Int, distance: CGFloat)?
        for (l, line) in found.enumerated() {
            for (i, box) in line.boxes.enumerated() where box != .zero {
                let rect = viewRect(box)
                let dx = max(rect.minX - center.x, 0, center.x - rect.maxX)
                let dy = max(rect.minY - center.y, 0, center.y - rect.maxY)
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < (best?.distance ?? 10) { best = (l, i, distance) }
            }
        }
        if let best {
            let line = found[best.line].text
            let query = String(line[best.index...].prefix(20))
            hit = (best.line, best.index)
            // Keep the highlight on the same word while it is still under the dot.
            if query != lastQuery {
                lastQuery = query
                highlightLength = 1
                onRead?(query, String(line))
            }
        } else {
            hit = nil
        }
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let outlinePath = UIBezierPath()
        for line in lines {
            let frame = line.boxes.filter { $0 != .zero }.reduce(CGRect.null) { $0.union($1) }
            if !frame.isNull { outlinePath.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3)) }
        }
        outlines.path = outlinePath.cgPath
        let markedPath = UIBezierPath()
        if let hit, lines.indices.contains(hit.line), hit.index < lines[hit.line].boxes.count {
            let boxes = lines[hit.line].boxes
            let end = min(boxes.count, hit.index + max(1, highlightLength))
            let frame = boxes[hit.index..<end].filter { $0 != .zero }.reduce(CGRect.null) { $0.union($1) }
            if !frame.isNull { markedPath.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3)) }
        }
        marked.path = markedPath.cgPath
    }

    /// The last frame, cropped to what is on screen.
    func snapshot() -> UIImage? {
        guard let frame = latestFrame else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        let r = shownImageRect
        guard r.width > 0 else { return nil }
        // Visible part in image pixels (CIImage origin is bottom-left).
        let scale = imageSize.width / r.width
        let visible = CGRect(x: -r.minX * scale, y: -r.minY * scale, width: bounds.width * scale, height: bounds.height * scale)
        let crop = CGRect(x: visible.minX, y: imageSize.height - visible.maxY, width: visible.width, height: visible.height)
            .intersection(image.extent)
        guard let cg = CIContext().createCGImage(image, from: crop) else { return nil }
        return UIImage(cgImage: cg)
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
