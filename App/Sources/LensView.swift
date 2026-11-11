import SwiftUI
import AVFoundation
import AVKit
import CoreMotion
import KotobaCore
import KotobaOCR

/// Live camera: the word under the dot is looked up as you move the phone.
/// A word shows once several frames agree on it, and stays until another one
/// clearly takes over; frames taken while the phone moves are skipped.
/// Touching the picture (or pause, or a volume button) takes a full-resolution
/// photo you can read by touch, the whole page included.
struct LensView: View {
    @Environment(AppModel.self) private var model
    let onLookup: (Lookup) -> Void
    let onSearch: (String) -> Void

    @State private var lens = LensController()
    @State private var pick: WordAim.Pick?
    @State private var sentence = ""
    @State private var outcome = AppModel.SearchOutcome()
    @State private var frozen: UIImage?
    @State private var freezing = false
    @State private var pendingTap: PendingTap?
    @State private var selecting = false
    @State private var cameraAllowed: Bool?
    @State private var torch = false
    @State private var zoom: CGFloat = 1
    @State private var readingPage = false
    @State private var locks = 0
    /// 縦: vertical text, read with Kotoba's own column reader.
    @AppStorage("lensVertical") private var vertical = false

    var body: some View {
        if cameraAllowed == false {
            ContentUnavailableView(tr("Serve la fotocamera"), systemImage: "camera",
                                   description: Text(tr("Consenti l'accesso in Impostazioni › App › Kotoba › Fotocamera.")))
        } else {
            VStack(spacing: 0) {
                ZStack {
                    if let frozen {
                        PhotoReader(image: frozen, vertical: vertical, selecting: selecting, pick: pick, pendingTap: pendingTap,
                                    onMiss: { selecting = true }, onReading: { readingPage = $0 }) { picked, around in
                            pick = picked
                            sentence = around
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
                        LiveReader(controller: lens, vertical: vertical,
                                   onPick: { picked in
                                       pick = picked
                                       sentence = picked.sentence
                                       locks += 1
                                   },
                                   onSentence: { picked, whole in
                                       // Still the word on screen: its sentence, read across lines or columns.
                                       if pick == picked { sentence = whole }
                                   },
                                   onTap: { point in freeze(tapAt: point) },
                                   onShutter: { freeze(tapAt: nil) },
                                   onZoom: { zoom = $0 })
                        Reticle()
                        liveControls
                    } else {
                        Color.black
                    }
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if frozen != nil, readingPage {
                                Label(tr("Leggo la pagina…"), systemImage: "text.viewfinder")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(14)
                            }
                            Spacer()
                            Button(action: { frozen == nil ? freeze(tapAt: nil) : unfreeze() }) {
                                Group {
                                    if freezing {
                                        ProgressView()
                                    } else {
                                        Image(systemName: frozen == nil ? "pause.fill" : "play.fill").font(.title3)
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .background(.ultraThinMaterial, in: Circle())
                            }
                            .tint(.white)
                            .padding(14)
                        }
                    }
                }
                .clipped()
                panel
            }
            .sensoryFeedback(.impact(weight: .light), trigger: locks)
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: cameraAllowed = true
                case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
                default: cameraAllowed = false
                }
            }
            .onAppear { if frozen == nil { lens.start() } }
            .onDisappear {
                lens.stop()
                torch = false
            }
            .task(id: pick?.query) {
                guard let pick else { return }
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                var result = await model.search(pick.query)
                guard !Task.isCancelled else { return }
                guard !result.direct.isEmpty || frozen != nil else { return }
                result.sentence = sentence.isEmpty ? pick.sentence : sentence
                outcome = result
            }
            .onChange(of: sentence) { _, whole in
                // The sentence read across columns can arrive after the definition:
                // Anki gets it as long as these results are still the word's.
                guard !whole.isEmpty, let pick,
                      outcome.searchedText == pick.query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                outcome.sentence = whole
            }
        }
    }

    private var liveControls: some View {
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
                Spacer()
                Button {
                    torch.toggle()
                    lens.setTorch(torch)
                } label: {
                    Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.white)
                .accessibilityLabel(tr("Torcia"))
            }
            .padding(10)
            Spacer()
            HStack {
                Button { lens.toggleZoom() } label: {
                    Text(zoom < 1.05 ? "1×" : String(format: "%.1f×", zoom))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(width: 46, height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .tint(.white)
                .accessibilityLabel(tr("Zoom"))
                .padding(14)
                .padding(.bottom, 10)
                Spacer()
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if let pick {
                ContextStrip(pick: pick, onSelect: select)
                Divider()
            }
            Group {
                if outcome.direct.isEmpty && outcome.byMeaning.isEmpty {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: showsResults ? .infinity : nil)
                        .fixedSize(horizontal: false, vertical: !showsResults)
                } else {
                    ResultsPane(outcome: outcome, query: pick?.query ?? "", onLookup: onLookup, onSearch: onSearch)
                }
            }
        }
        // Only the hint to show: the panel is as tall as the hint (larger
        // text sizes included) and the camera gets the rest. Room for the
        // definition once a word is found.
        .frame(height: showsResults ? 320 : nil)
        .background(Palette.paper)
        .animation(.easeOut(duration: 0.25), value: showsResults)
    }

    private var showsResults: Bool {
        pick != nil || !outcome.direct.isEmpty || !outcome.byMeaning.isEmpty
    }

    private var hint: String {
        if frozen != nil { return tr("Tocca una parola. Le colonne già lette hanno il bordo tratteggiato; Seleziona usa Live Text.") }
        return vertical
            ? tr("縦: punta una parola con le colonne dritte. Per leggere la pagina intera allontanati, metti 1× e tocca lo schermo.")
            : tr("Punta il punto rosso su una parola: si aggancia quando è ferma. Tocca lo schermo per fermare l'immagine e scegliere col dito.")
    }

    /// A tap on the strip: look up from that character, and hold the picture still while you choose.
    private func select(_ index: Int) {
        guard let current = pick, let moved = WordFinder.shared.pick(in: current.text, start: index) else { return }
        pick = moved
        // Same line: keep the sentence already read across lines when it still holds the word's.
        if !sentence.contains(moved.sentence) { sentence = moved.sentence }
        if frozen == nil { freeze(tapAt: nil) }
    }

    private func freeze(tapAt point: CGPoint?) {
        guard frozen == nil, !freezing else { return }
        freezing = true
        lens.pauseReading()
        Task {
            let still = await lens.capture()
            freezing = false
            guard let still else {
                lens.resumeReading()
                return
            }
            lens.stop()
            torch = false
            selecting = false
            readingPage = false
            pendingTap = point.map { PendingTap(point: $0) }
            frozen = still
        }
    }

    private func unfreeze() {
        frozen = nil
        pendingTap = nil
        selecting = false
        readingPage = false
        lens.start()
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

/// Lets the SwiftUI view drive the live reader.
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

    /// Stops reading frames (the camera keeps running) while a photo is taken.
    func pauseReading() { view?.reading = false }
    func resumeReading() { view?.reading = true }

    /// A full-resolution photo of what is on screen (or the last frame, if the photo fails).
    func capture() async -> UIImage? { await view?.capture() }

    func setTorch(_ on: Bool) { view?.setTorch(on) }
    func toggleZoom() { view?.toggleZoom() }

    fileprivate func attach(_ view: LiveReaderView) {
        self.view = view
        if wantsRunning { view.start() }
    }
}

private struct LiveReader: UIViewRepresentable {
    let controller: LensController
    var vertical: Bool
    let onPick: (WordAim.Pick) -> Void
    let onSentence: (WordAim.Pick, String) -> Void
    let onTap: (CGPoint) -> Void
    let onShutter: () -> Void
    let onZoom: (CGFloat) -> Void

    func makeUIView(context: Context) -> LiveReaderView {
        let view = LiveReaderView()
        view.vertical = vertical
        updateUIView(view, context: context)
        controller.attach(view)
        return view
    }

    func updateUIView(_ view: LiveReaderView, context: Context) {
        view.onPick = onPick
        view.onSentence = onSentence
        view.onTap = onTap
        view.onShutter = onShutter
        view.onZoom = onZoom
        view.vertical = vertical
    }

    static func dismantleUIView(_ view: LiveReaderView, coordinator: ()) {
        view.retire()
    }
}

/// Camera preview plus reading around the centre, one frame at a time.
final class LiveReaderView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var onPick: ((WordAim.Pick) -> Void)?
    /// A word's sentence joined with the line or column next to it, when it
    /// runs on there (a pick alone only has its own line).
    var onSentence: ((WordAim.Pick, String) -> Void)?
    var onTap: ((CGPoint) -> Void)?
    var onShutter: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    /// Whether frames are read.
    var reading = true {
        didSet {
            let on = reading
            queue.async { [weak self] in self?.readingOn = on }
        }
    }
    /// 縦書き: read the column under the dot with the vertical reader.
    var vertical = false {
        didSet {
            guard vertical != oldValue else { return }
            let on = vertical
            queue.async { [weak self] in self?.verticalMode = on }
            resetReading()
        }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "kotoba.lens.session")
    private let queue = DispatchQueue(label: "kotoba.lens.frames")
    private let photoOutput = AVCapturePhotoOutput()
    private var photoReady = false
    private var device: AVCaptureDevice?
    private var configured = false
    /// The zoom at which the page is sharp at the closest distance the lens can focus.
    private var comfortableZoom: CGFloat = 1
    private let outlines = CAShapeLayer()
    private let marked = CAShapeLayer()
    private var stabilizer = PickStabilizer()
    private var captures: [Int64: PhotoCapture] = [:]

    // Main thread state.
    private var lines: [OCRLine] = []
    private var markedFrame: CGRect?
    private var imageSize = CGSize(width: 1440, height: 1920)
    private var latestFrame: CVPixelBuffer?

    // Frame queue state.
    nonisolated(unsafe) private let motion = CMMotionManager()
    nonisolated(unsafe) private var busy = false
    nonisolated(unsafe) private var lastRun: CFTimeInterval = 0
    nonisolated(unsafe) private var verticalMode = false
    nonisolated(unsafe) private var readingOn = true
    nonisolated(unsafe) private var favored: String?
    /// The word picked in the last frame read, and what is needed for the
    /// rest of its sentence: the lines next to it (horizontal text, read with
    /// the frame) or the column and picture to read the next columns from.
    nonisolated(unsafe) private var lastRead: (pick: WordAim.Pick, column: (gray: GrayImage, result: VerticalOCR.Result)?,
                                               before: [Character]?, after: [Character]?)?
    /// The part of the frame on screen (normalized, origin top-left).
    nonisolated(unsafe) private var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Horizontal text is read in this band around the dot (Vision's coordinates).
    nonisolated(unsafe) private var band = CGRect(x: 0, y: 0.35, width: 1, height: 0.3)
    /// How far from a character the dot may be, as a share of the frame's width.
    nonisolated(unsafe) private var reach: CGFloat = 0.012

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
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        if #available(iOS 17.2, *) {
            // A volume button takes the photo, as in the Camera app.
            addInteraction(AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended { self?.onShutter?() }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Off screen for good: never starts again (a new view takes its place).
    private var retired = false

    func retire() {
        retired = true
        stop()
    }

    func start() {
        guard !retired else { return }
        if !configured { configure() }
        if motion.isGyroAvailable, !motion.isGyroActive {
            motion.gyroUpdateInterval = 1.0 / 30
            motion.startGyroUpdates()
        }
        resetReading()
        reading = true
        let session = session
        sessionQueue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        motion.stopGyroUpdates()
        let session = session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    private func resetReading() {
        stabilizer.reset()
        lines = []
        markedFrame = nil
        queue.async { [weak self] in
            self?.favored = nil
            self?.lastRead = nil
        }
        redraw()
    }

    // MARK: Camera

    private func configure() {
        configured = true
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        device = camera
        let format = Self.readingFormat(camera)
        session.beginConfiguration()
        if format == nil { session.sessionPreset = .hd1920x1080 }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoReady = true
        }
        if let format, (try? camera.lockForConfiguration()) != nil {
            camera.activeFormat = format
            camera.unlockForConfiguration()
        }
        // Portrait frames and photos, so coordinates match the screen.
        for connection in [output.connection(with: .video), photoOutput.connection(with: .video), preview.connection] {
            if let connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
        session.commitConfiguration()

        // Photos up to 12 MP: sharp enough for furigana, quick to take.
        let sizes = camera.activeFormat.supportedMaxPhotoDimensions.filter { Int($0.width) * Int($0.height) <= 4032 * 3024 }
        if photoReady, let largest = sizes.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = largest
        }
        let d = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        imageSize = CGSize(width: CGFloat(min(d.width, d.height)), height: CGFloat(max(d.width, d.height)))
        comfortableZoom = Self.comfortableZoom(camera)
        if (try? camera.lockForConfiguration()) != nil {
            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
            if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
            if camera.isSmoothAutoFocusSupported { camera.isSmoothAutoFocusEnabled = false }
            camera.videoZoomFactor = min(comfortableZoom, camera.activeFormat.videoMaxZoomFactor)
            camera.unlockForConfiguration()
        }
        onZoom?(camera.videoZoomFactor)
        updateGeometry()
    }

    /// A 4:3 format (more of a square screen area has real pixels) whose photos reach 12 MP.
    private static func readingFormat(_ device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        var best: (format: AVCaptureDevice.Format, score: Int)?
        for format in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard d.width == 1920, d.height == 1440,
                  format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) else { continue }
            let photo = format.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.filter { $0 <= 4032 * 3024 }.max() ?? 0
            let fullRange = CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? 1 : 0
            let score = photo * 2 + fullRange
            if score > (best?.score ?? -1) { best = (format, score) }
        }
        return best?.format
    }

    /// People bring the phone close to make text big, closer than the lens can focus.
    /// Zooming in by the right amount makes text big at a distance where it is sharp:
    /// about 8 cm of page across the screen at the closest focus distance.
    private static func comfortableZoom(_ device: AVCaptureDevice) -> CGFloat {
        let closest = Double(device.minimumFocusDistance)
        guard closest > 0 else { return 1.5 }
        let fov = Double(device.activeFormat.videoFieldOfView) * .pi / 180
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let shortOverLong = Double(min(d.width, d.height)) / Double(max(d.width, d.height))
        let longSide = 80 / shortOverLong
        let distance = (longSide / 2) / tan(fov / 2)
        return CGFloat(min(2.5, max(1, closest / distance)))
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard let device, gesture.state == .changed, (try? device.lockForConfiguration()) != nil else { return }
        let zoom = device.videoZoomFactor * gesture.scale
        device.videoZoomFactor = min(max(1, zoom), min(8, device.activeFormat.videoMaxZoomFactor))
        device.unlockForConfiguration()
        gesture.scale = 1
        onZoom?(device.videoZoomFactor)
    }

    func toggleZoom() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let target = device.videoZoomFactor > 1.05 ? 1 : min(max(comfortableZoom, 1.5), device.activeFormat.videoMaxZoomFactor)
        device.ramp(toVideoZoomFactor: target, withRate: 6)
        device.unlockForConfiguration()
        onZoom?(target)
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onTap?(gesture.location(in: self))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outlines.frame = bounds
        marked.frame = bounds
        updateGeometry()
        redraw()
    }

    // MARK: Geometry

    /// The frame as shown (aspect fill), in view coordinates.
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

    /// The part of the frame on screen, normalized with the origin at the top left.
    private var visibleFraction: CGRect {
        let r = shownImageRect
        guard r.width > 0, r.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: -r.minX / r.width, y: -r.minY / r.height, width: bounds.width / r.width, height: bounds.height / r.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func updateGeometry() {
        let r = shownImageRect
        guard r.width > 0, r.height > 0, bounds.height > 0 else { return }
        let visible = visibleFraction
        let bandHeight = min(1, bounds.height * 0.45 / r.height)
        let band = CGRect(x: visible.minX, y: 0.5 - bandHeight / 2, width: visible.width, height: bandHeight)
        let reach = 12 / r.width
        queue.async { [weak self] in
            self?.visible = visible
            self?.band = band
            self?.reach = reach
        }
    }

    // MARK: Reading

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard readingOn, !busy, now - lastRun > 0.12, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        nonisolated(unsafe) let frame = buffer
        // A moving phone gives blurred frames, and the dot isn't on anything yet.
        if let rate = motion.gyroData?.rotationRate,
           (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot() > 0.6 {
            DispatchQueue.main.async { [weak self] in self?.latestFrame = frame }
            return
        }
        busy = true
        lastRun = now
        let W = CGFloat(CVPixelBufferGetWidth(buffer)), H = CGFloat(CVPixelBufferGetHeight(buffer))
        let favored = favored
        var line: OCRLine?
        var shown: [OCRLine] = []
        var position: Double?
        var column: (gray: GrayImage, result: VerticalOCR.Result)?
        var around: (before: [Character]?, after: [Character]?) = (nil, nil)
        if verticalMode {
            // Only what is on screen; the dot is the frame's centre.
            let v = visible
            let crop = CGRect(x: v.minX * W, y: v.minY * H, width: v.width * W, height: v.height * H).integral
                .intersection(CGRect(x: 0, y: 0, width: W, height: H))
            if let gray = GrayImage(pixelBuffer: buffer, crop: crop),
               let result = VerticalOCR.read(gray, at: CGPoint(x: W / 2 - crop.minX, y: H / 2 - crop.minY)) {
                let cw = CGFloat(gray.width), ch = CGFloat(gray.height)
                let mapped = result.line.mapped { box in
                    CGRect(x: (crop.minX + box.minX * cw) / W, y: 1 - (crop.minY + (1 - box.minY) * ch) / H,
                           width: box.width * cw / W, height: box.height * ch / H)
                }
                line = mapped
                shown = [mapped]
                position = result.position
                column = (gray, result)
            }
        } else {
            shown = HorizontalOCR.lines(in: buffer, region: band, languageCorrection: false)
            let toPixels: (CGRect) -> CGRect = { b in CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H) }
            let centre = CGPoint(x: W / 2, y: H / 2)
            var best: (line: OCRLine, position: Double, distance: CGFloat)?
            for candidate in shown {
                guard let found = candidate.locate(centre, reach: reach * W, toView: toPixels) else { continue }
                if found.distance < (best?.distance ?? .infinity) { best = (candidate, found.position, found.distance) }
            }
            line = best?.line
            position = best?.position
            if let best, let index = shown.firstIndex(of: best.line) {
                let next = OCRLine.adjacent(to: index, in: shown)
                around = (next.before?.text, next.after?.text)
            }
        }
        var pick: WordAim.Pick?
        if let line, let position { pick = WordFinder.shared.pick(in: line, at: position, favoring: favored) }
        if let pick { lastRead = (pick, column, around.before, around.after) }
        let size = CGSize(width: W, height: H)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.imageSize = size
            self.latestFrame = frame
            self.update(line: line, shown: shown, pick: pick)
            self.queue.async { self.busy = false }
        }
    }

    private func update(line: OCRLine?, shown: [OCRLine], pick: WordAim.Pick?) {
        guard reading else { return }
        lines = shown
        if let changed = stabilizer.feed(pick, at: CACurrentMediaTime()) {
            let word = changed.word
            queue.async { [weak self] in self?.favored = word }
            onPick?(changed)
            readSentence(for: changed)
        }
        // Box the word on screen where it is in this frame.
        markedFrame = nil
        if let word = stabilizer.shown.map({ Array($0.word) }), let line, line.text.count >= word.count {
            let target = pick?.start ?? 0
            var best: Int?
            for s in 0...(line.text.count - word.count) where Array(line.text[s..<(s + word.count)]) == word {
                if best == nil || abs(s - target) < abs(best! - target) { best = s }
            }
            if let best { markedFrame = line.frame(of: best..<(best + word.count)) }
        }
        redraw()
    }

    /// The word's whole sentence, once per word, when it runs off its line:
    /// 「…二つの人格・」 goes on in the next column. Vertical text reads the
    /// columns either side (the frame only read the one under the dot).
    private func readSentence(for shownPick: WordAim.Pick) {
        let edges = WordAim.sentenceEdges(of: shownPick)
        guard edges.start || edges.end else { return }
        queue.async { [weak self] in
            // The word as picked in the last frame it was seen in.
            guard let self, let last = self.lastRead, last.pick.word == shownPick.word else { return }
            var before = last.before, after = last.after
            if let column = last.column {
                let next = VerticalOCR.neighbours(column.gray, of: column.result)
                before = next.before?.line.text
                after = next.after?.line.text
            }
            guard before != nil || after != nil else { return }
            let sentence = WordAim.sentence(of: last.pick, before: before, after: after)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.stabilizer.shown == shownPick else { return }
                self.onSentence?(shownPick, sentence)
            }
        }
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let outlinePath = UIBezierPath()
        for line in lines {
            let frame = line.frame
            if !frame.isNull { outlinePath.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3)) }
        }
        outlines.path = outlinePath.cgPath
        let markedPath = UIBezierPath()
        if let markedFrame, !markedFrame.isNull {
            markedPath.append(UIBezierPath(roundedRect: viewRect(markedFrame).insetBy(dx: -2, dy: -2), cornerRadius: 3))
        }
        marked.path = markedPath.cgPath
    }

    // MARK: Stills

    /// The last frame, cropped to what is on screen.
    func snapshot() -> UIImage? {
        guard let frame = latestFrame else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        let v = visibleFraction
        let w = image.extent.width, h = image.extent.height
        // CIImage counts y from the bottom.
        let crop = CGRect(x: v.minX * w, y: (1 - v.maxY) * h, width: v.width * w, height: v.height * h).intersection(image.extent)
        guard let cg = CIContext().createCGImage(image, from: crop) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// A full-resolution photo cropped to what is on screen; the last frame if that fails.
    func capture() async -> UIImage? {
        let fallback = snapshot()
        guard photoReady, session.isRunning else { return fallback }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        if photoOutput.maxPhotoDimensions.width > 0 { settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions }
        // Reading a page shouldn't sound like taking a picture (where the law allows it).
        if #available(iOS 18.0, *), photoOutput.isShutterSoundSuppressionSupported {
            settings.isShutterSoundSuppressionEnabled = true
        }
        let visible = visibleFraction
        let frameSize = imageSize
        let id = settings.uniqueID
        let output = photoOutput
        let photo: UIImage? = await withCheckedContinuation { continuation in
            let capture = PhotoCapture { continuation.resume(returning: $0) }
            captures[id] = capture
            output.capturePhoto(with: settings, delegate: capture)
            // Never wait for ever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { capture.finish(nil) }
        }
        captures[id] = nil
        guard let upright = photo?.uprighted(), let cg = upright.cgImage else { return fallback }
        // The video frame is the photo's centre (same shape, or a crop of it): keep what was on screen.
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let frameInPhoto = AVMakeRect(aspectRatio: frameSize, insideRect: full)
        let crop = CGRect(x: frameInPhoto.minX + visible.minX * frameInPhoto.width,
                          y: frameInPhoto.minY + visible.minY * frameInPhoto.height,
                          width: visible.width * frameInPhoto.width, height: visible.height * frameInPhoto.height)
            .integral.intersection(full)
        guard let cropped = cg.cropping(to: crop) else { return fallback }
        return UIImage(cgImage: cropped)
    }
}

/// Receives one photo; `finish` runs its callback at most once (photo or time-out).
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var done: ((UIImage?) -> Void)?
    private let lock = NSLock()

    init(done: @escaping (UIImage?) -> Void) {
        self.done = done
    }

    func finish(_ image: UIImage?) {
        let callback: ((UIImage?) -> Void)? = lock.withLock {
            defer { done = nil }
            return done
        }
        callback?(image)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        finish(error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil)
    }
}
