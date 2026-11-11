import SwiftUI
import AVFoundation
import VisionKit
import KotobaCore
import KotobaOCR

/// A zoomable photo you read by touch. A tap looks up the word under the
/// finger (the dictionary decides which word that is); Select uses Live Text.
/// On a vertical page every column is read in the background, so taps become
/// instant and the Anki sentence can run across columns.
struct PhotoReader: UIViewRepresentable {
    let image: UIImage
    /// true: 縦書き; false: horizontal; nil: horizontal first, vertical where nothing horizontal is found.
    var vertical: Bool?
    var selecting: Bool
    /// The word on screen (it may have been moved from the strip).
    var pick: WordAim.Pick?
    /// A tap to act on as soon as the photo is ready (made on the live camera).
    var pendingTap: PendingTap?
    /// A tap found no text there.
    var onMiss: (() -> Void)? = nil
    /// Whether the page is being read in the background.
    var onReading: ((Bool) -> Void)? = nil
    /// The word tapped, and the sentence around it.
    let onPick: (WordAim.Pick, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false

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
        imageView.onLayout = { [weak coordinator = context.coordinator] in coordinator?.laidOut() }
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        c.onPick = onPick
        c.onMiss = onMiss
        c.onReading = onReading
        c.vertical = vertical
        c.show(image)
        c.setSelecting(selecting)
        c.follow(pick)
        if let pendingTap { c.handle(pendingTap) }
    }

    static func dismantleUIView(_ scroll: UIScrollView, coordinator: Coordinator) {
        coordinator.stop()
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
        var onPick: (WordAim.Pick, String) -> Void
        var onMiss: (() -> Void)?
        var onReading: ((Bool) -> Void)?
        var vertical: Bool?
        let interaction = ImageAnalysisInteraction()
        let analyzer = ImageAnalyzer()
        weak var imageView: UIImageView?

        private var shown: UIImage?
        private var transcript = ""
        /// Horizontal lines from Apple's recognizer (the whole photo, read once).
        private var rows: [OCRLine] = []
        private var rowsReady = false
        /// Vertical columns read so far.
        private var columns: [OCRLine] = []
        /// The character size on this page, from the first column read (gray pixels).
        private var em: Double?
        private var grayTask: Task<GrayImage?, Never>?
        private var sweep: Task<Void, Never>?
        private var tapReading = false
        /// Learned from the page or a tap: this page is 縦書き.
        private var pageIsVertical = false
        /// Whether the page's direction is known (always, unless `vertical` is nil).
        private var decided = false
        private var selecting = false
        private var selected: (vertical: Bool, line: Int, start: Int, length: Int)?
        private var handledTap: UUID?
        private var waitingTap: CGPoint?
        private let overlay = CAShapeLayer()
        private let highlight = CAShapeLayer()

        init(onPick: @escaping (WordAim.Pick, String) -> Void) {
            self.onPick = onPick
            super.init()
            interaction.delegate = self
            overlay.fillColor = UIColor.clear.cgColor
            overlay.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
            overlay.lineWidth = 1
            overlay.lineDashPattern = [3, 3]
            highlight.fillColor = UIColor(Palette.shu).withAlphaComponent(0.3).cgColor
            highlight.strokeColor = UIColor(Palette.shu).cgColor
            highlight.lineWidth = 2
        }

        private var readsVertical: Bool { vertical ?? pageIsVertical }

        func stop() {
            sweep?.cancel()
            grayTask?.cancel()
        }

        func show(_ image: UIImage) {
            guard shown !== image, let imageView else { return }
            stop()
            shown = image
            imageView.image = image
            if overlay.superlayer == nil {
                imageView.layer.addSublayer(overlay)
                imageView.layer.addSublayer(highlight)
            }
            rows = []
            rowsReady = false
            columns = []
            em = nil
            sweep = nil
            pageIsVertical = false
            decided = vertical != nil
            selected = nil
            waitingTap = nil
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
            grayTask = Task.detached(priority: .userInitiated) { GrayImage(cgImage: cgImage) }
            if vertical == true {
                startSweep()
            }
            // Horizontal lines are read anyway: a vertical page often has a horizontal title or page header.
            Task.detached(priority: vertical == true ? .utility : .userInitiated) {
                let found = HorizontalOCR.lines(in: cgImage)
                await MainActor.run { [weak self] in
                    guard let self, self.shown === image else { return }
                    self.rows = found
                    self.rowsReady = true
                    if self.decided {
                        self.redraw()
                        self.tapWhenReady()
                    } else {
                        self.decide()
                    }
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

        /// The strip moved the word: move the highlight with it.
        func follow(_ pick: WordAim.Pick?) {
            guard let pick, let s = selected else { return }
            let line = s.vertical ? columns[safe: s.line] : rows[safe: s.line]
            guard let line, line.text == pick.text, pick.start != s.start || pick.length != s.length else { return }
            selected = (s.vertical, s.line, pick.start, pick.length)
            redraw()
        }

        func handle(_ pending: PendingTap) {
            guard handledTap != pending.id else { return }
            handledTap = pending.id
            waitingTap = pending.point
            tapWhenReady()
        }

        func laidOut() {
            redraw()
            tapWhenReady()
        }

        /// A waiting tap runs once the photo is on screen and, for horizontal text, read.
        private func tapWhenReady() {
            guard let point = waitingTap, imageRect.width > 0, readsVertical || (rowsReady && decided) else { return }
            waitingTap = nil
            tap(at: point)
        }

        // MARK: Geometry

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
            // On a vertical page, horizontal "lines" are mostly rows cut across columns: don't show them.
            for line in (readsVertical ? columns : rows + columns) {
                let frame = line.frame
                guard !frame.isNull else { continue }
                outlines.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3))
            }
            overlay.path = outlines.cgPath
            let marked = UIBezierPath()
            if let s = selected, let line = s.vertical ? columns[safe: s.line] : rows[safe: s.line] {
                let frame = line.frame(of: s.start..<(s.start + s.length))
                if !frame.isNull {
                    marked.append(UIBezierPath(roundedRect: viewRect(frame).insetBy(dx: -2, dy: -2), cornerRadius: 3))
                }
            }
            highlight.path = marked.cgPath
        }

        // MARK: Taps

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard !selecting, let imageView else { return }
            tap(at: gesture.location(in: imageView))
        }

        private func nearest(_ point: CGPoint, in lines: [OCRLine]) -> (line: Int, position: Double)? {
            var best: (line: Int, position: Double, distance: CGFloat)?
            for (i, line) in lines.enumerated() {
                guard let found = line.locate(point, reach: 16, toView: viewRect) else { continue }
                if found.distance < (best?.distance ?? .infinity) { best = (i, found.position, found.distance) }
            }
            return best.map { ($0.line, $0.position) }
        }

        func tap(at point: CGPoint) {
            if readsVertical {
                if let hit = nearest(point, in: columns) {
                    choose(vertical: true, line: hit.line, position: hit.position)
                } else {
                    readColumn(at: point)
                }
                return
            }
            guard rowsReady, decided else {
                waitingTap = point
                return
            }
            if let hit = nearest(point, in: rows) {
                choose(vertical: false, line: hit.line, position: hit.position)
            } else if let hit = nearest(point, in: columns) {
                choose(vertical: true, line: hit.line, position: hit.position)
            } else {
                readColumn(at: point)
            }
        }

        private func choose(vertical isVertical: Bool, line index: Int, position: Double) {
            let lines = isVertical ? columns : rows
            guard lines.indices.contains(index), let pick = WordFinder.shared.pick(in: lines[index], at: position) else { return }
            selected = (isVertical, index, pick.start, pick.length)
            redraw()
            onPick(pick, sentence(for: pick, vertical: isVertical, line: index))
        }

        /// The sentence around the word, continued into the neighbouring columns (or lines).
        private func sentence(for pick: WordAim.Pick, vertical isVertical: Bool, line index: Int) -> String {
            let lines = isVertical ? columns : rows
            let next = OCRLine.adjacent(to: index, in: lines)
            return WordAim.sentence(of: pick, before: next.before?.text, after: next.after?.text)
        }

        /// The column under the tap, read with the vertical reader.
        private func readColumn(at point: CGPoint) {
            guard !tapReading, let image = shown else { return }
            let r = imageRect
            guard r.width > 0, r.contains(point) else { return }
            let fx = (point.x - r.minX) / r.width, fy = (point.y - r.minY) / r.height
            tapReading = true
            Task {
                let gray = await grayTask?.value
                let result: VerticalOCR.Result? = await Task.detached(priority: .userInitiated) {
                    gray.flatMap { VerticalOCR.read($0, at: CGPoint(x: fx * CGFloat($0.width), y: fy * CGFloat($0.height))) }
                }.value
                tapReading = false
                guard shown === image else { return }
                if let result {
                    pageIsVertical = true
                    em = em ?? result.em
                    let index = add(result.line)
                    redraw()
                    choose(vertical: true, line: index, position: result.position)
                    startSweep()
                } else if let hit = nearest(point, in: rows) {
                    choose(vertical: false, line: hit.line, position: hit.position)
                } else if interaction.analysisHasText(at: point) {
                    onMiss?()
                }
            }
        }

        /// Adds a column, replacing one it mostly overlaps (the same column read again). Returns its index.
        @discardableResult
        private func add(_ line: OCRLine) -> Int {
            let frame = line.frame
            if let same = columns.firstIndex(where: { other in
                let i = other.frame.intersection(frame)
                return !i.isNull && i.width * i.height > 0.5 * min(frame.width * frame.height, other.frame.width * other.frame.height)
            }) {
                // Keep the longer reading; a selection on it stays valid only if the text is unchanged.
                if line.text.count > columns[same].text.count {
                    if let s = selected, s.vertical, s.line == same, line.text != columns[same].text { selected = nil }
                    columns[same] = line
                }
                return same
            }
            columns.append(line)
            return columns.count - 1
        }

        // MARK: The whole page

        /// Automatic direction: is this page horizontal or 縦書き? Apple's lines win
        /// when they read as Japanese words; otherwise a few columns near the centre
        /// are read, and the reading made of real words wins.
        private func decide() {
            guard !decided, let image = shown else { return }
            let rows = rows
            onReading?(true)
            Task { [weak self] in
                let horizontal: (score: Double, japanese: Int) = await Task.detached(priority: .userInitiated) {
                    var total = 0, score = 0.0
                    for row in rows where row.text.count >= 2 {
                        let c = WordFinder.shared.coverage(row.text)
                        total += c.japanese
                        score += c.score * Double(c.japanese)
                    }
                    return (total > 0 ? score / Double(total) : 0, total)
                }.value
                guard let self, self.shown === image else { return }
                let lengths = rows.map(\.text.count).sorted()
                let median = lengths.isEmpty ? 0 : lengths[lengths.count / 2]
                if horizontal.japanese >= 8, horizontal.score >= 0.55, median >= 4 {
                    self.settle()
                    return
                }
                guard let gray = await self.grayTask?.value else {
                    self.settle()
                    return
                }
                var best: (result: VerticalOCR.Result, score: Double)?
                for (fx, fy) in [(0.5, 0.5), (0.4, 0.4), (0.6, 0.6)] {
                    guard self.shown === image else { return }
                    let found: (result: VerticalOCR.Result, score: Double, japanese: Int)? = await Task.detached(priority: .userInitiated) {
                        guard let read = VerticalOCR.read(gray, at: CGPoint(x: fx * Double(gray.width), y: fy * Double(gray.height))) else { return nil }
                        let c = WordFinder.shared.coverage(read.line.text)
                        return (read, c.score, c.japanese)
                    }.value
                    if let found, found.japanese >= 5, found.score > (best?.score ?? -1) { best = (found.result, found.score) }
                    if let best, best.score >= 0.7 { break }
                }
                guard self.shown === image else { return }
                if let best, best.score >= max(0.4, horizontal.score + 0.15) {
                    self.pageIsVertical = true
                    self.em = best.result.em
                    self.add(best.result.line)
                    self.settle()
                    self.startSweep()
                } else {
                    self.settle()
                }
            }
        }

        private func settle() {
            decided = true
            onReading?(false)
            redraw()
            tapWhenReady()
        }

        /// Reads every column of a vertical page, nearest the centre first.
        private func startSweep() {
            guard sweep == nil, let image = shown else { return }
            onReading?(true)
            sweep = Task { [weak self] in
                defer { if let self, self.shown === image { self.onReading?(false) } }
                guard let gray = await self?.grayTask?.value else { return }
                let W = Double(gray.width), H = Double(gray.height)
                func read(_ p: CGPoint) async -> VerticalOCR.Result? {
                    await Task.detached(priority: .utility) { VerticalOCR.read(gray, at: p) }.value
                }
                // The character size, from a column already read or a few tries around the centre.
                var size = self?.em
                if size == nil {
                    for (fx, fy) in [(0.5, 0.5), (0.35, 0.5), (0.65, 0.5), (0.5, 0.3), (0.5, 0.7), (0.2, 0.5), (0.8, 0.5)] {
                        guard !Task.isCancelled, let self, self.shown === image else { return }
                        if let result = await read(CGPoint(x: fx * W, y: fy * H)) {
                            size = result.em
                            self.em = result.em
                            self.pageIsVertical = true
                            self.add(result.line)
                            self.redraw()
                            break
                        }
                    }
                }
                guard let em = size, em > 4 else { return }
                var seeds: [CGPoint] = []
                for fy in [0.5, 0.25, 0.75] {
                    for x in stride(from: 0.6 * em, to: W - 0.6 * em, by: 0.9 * em) { seeds.append(CGPoint(x: x, y: fy * H)) }
                }
                let centre = CGPoint(x: W / 2, y: H / 2)
                seeds.sort { hypot($0.x - centre.x, $0.y - centre.y) < hypot($1.x - centre.x, $1.y - centre.y) }
                for seed in seeds {
                    guard !Task.isCancelled, let self, self.shown === image else { return }
                    // Skip points inside a column already read.
                    let n = CGPoint(x: seed.x / W, y: 1 - seed.y / H)
                    let padX = 0.35 * em / W, padY = 0.6 * em / H
                    if self.columns.contains(where: { $0.frame.insetBy(dx: -padX, dy: -padY).contains(n) }) { continue }
                    if let result = await read(seed) {
                        guard self.shown === image else { return }
                        self.add(result.line)
                        self.redraw()
                    }
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            let selected = interaction.selectedText
            guard !selected.isEmpty else { return }
            let line = transcript.split(separator: "\n").first { $0.contains(selected) }.map(String.init) ?? selected
            let text = Array(selected)
            let pick = WordAim.Pick(text: text, start: 0, length: WordFinder.shared.matchLength(text[...]))
            onPick(pick, line)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
