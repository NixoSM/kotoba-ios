import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// An 8-bit grayscale copy of an image, origin top-left.
struct GrayImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Renders an image, scaled down so its long side is at most `maxSide`.
    init?(cgImage: CGImage, maxSide: Int = 2400) {
        let scale = min(1, Double(maxSide) / Double(max(cgImage.width, cgImage.height)))
        let w = max(1, Int(Double(cgImage.width) * scale)), h = max(1, Int(Double(cgImage.height) * scale))
        var buffer = [UInt8](repeating: 255, count: w * h)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.init(width: w, height: h, pixels: buffer)
    }

    /// From a camera frame in BGRA.
    init?(pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = base.assumingMemoryBound(to: UInt8.self)
        var buffer = [UInt8](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBufferPointer { out in
            for y in 0..<h {
                let row = source + y * rowBytes
                for x in 0..<w {
                    let p = row + x * 4
                    out[y * w + x] = UInt8((Int(p[2]) * 77 + Int(p[1]) * 150 + Int(p[0]) * 29) >> 8)
                }
            }
        }
        self.init(width: w, height: h, pixels: buffer)
    }

    @inline(__always) func at(_ x: Int, _ y: Int) -> UInt8 { pixels[y * width + x] }
}

/// Reads vertical Japanese (縦書き), which Apple's text recognizer can't.
///
/// The idea: find the column under a point, cut it into character cells
/// (typeset text sits on a square grid), and lay the cells side by side as a
/// horizontal line. Apple's recognizer reads that line well, and every
/// character it returns maps back to its cell on the page.
enum VerticalOCR {
    struct Result {
        var line: OCRLine
        /// Index in `line.text` of the character at the point.
        var hit: Int
    }

    static func read(_ image: GrayImage, at point: CGPoint) -> Result? {
        guard let column = findColumn(image, at: point) else { return nil }
        guard let tile = makeTile(image, column: column) else { return nil }
        return recognize(tile, column: column, image: image)
    }

    // MARK: Layout

    struct Column {
        var x0: Int, x1: Int
        var em: Double
        /// Character cells, top to bottom: (top, bottom) rows.
        var cells: [(Int, Int)]
        /// The cell under the point.
        var hit: Int
        /// Paper brightness per row.
        var background: [Double]
    }

    /// Brightness of the paper on each row: a high percentile across a band, smoothed.
    private static func rowBackground(_ image: GrayImage, x0: Int, x1: Int, y0: Int, y1: Int) -> [Double] {
        let a = max(0, x0), b = min(image.width, x1)
        guard b > a, y1 > y0 else { return [] }
        var values = [UInt8](repeating: 0, count: b - a)
        var raw = [Double](repeating: 255, count: y1 - y0)
        for y in y0..<y1 {
            for x in a..<b { values[x - a] = image.at(x, y) }
            values.sort()
            raw[y - y0] = Double(values[min(values.count - 1, values.count * 9 / 10)])
        }
        let k = max(3, image.height / 170)
        var smooth = raw
        var sum = 0.0
        var window: [Double] = []
        // Box filter with edge padding.
        let padded = Array(repeating: raw.first ?? 255, count: k) + raw + Array(repeating: raw.last ?? 255, count: k)
        for i in 0..<(2 * k + 1) { sum += padded[i]; window.append(padded[i]) }
        for i in 0..<raw.count {
            smooth[i] = max(1, sum / Double(2 * k + 1))
            if i + 2 * k + 1 < padded.count { sum += padded[i + 2 * k + 1] - padded[i] }
        }
        return smooth
    }

    private static func runs(_ mask: [Bool]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var start: Int?
        for (i, on) in mask.enumerated() {
            if on, start == nil { start = i }
            if !on, let s = start { out.append((s, i)); start = nil }
        }
        if let s = start { out.append((s, mask.count)) }
        return out
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[s.count / 2]
    }

    static func findColumn(_ image: GrayImage, at point: CGPoint) -> Column? {
        let W = image.width, H = image.height
        let px = Int(point.x), py = Int(point.y)
        guard px >= 0, px < W, py >= 0, py < H else { return nil }

        // 1. Columns near the point, from the ink profile across a window.
        let r = Int(Double(min(W, H)) * 0.1), rv = Int(Double(H) * 0.2)
        let x0 = max(0, px - r), x1 = min(W, px + r), y0 = max(0, py - rv), y1 = min(H, py + rv)
        let bg = rowBackground(image, x0: x0, x1: x1, y0: y0, y1: y1)
        guard !bg.isEmpty else { return nil }
        var profile = [Int](repeating: 0, count: x1 - x0)
        for y in y0..<y1 {
            let limit = 0.62 * bg[y - y0]
            for x in x0..<x1 where Double(image.at(x, y)) < limit { profile[x - x0] += 1 }
        }
        guard let peak = profile.max(), peak > 0 else { return nil }
        let raw = runs(profile.map { Double($0) > 0.12 * Double(peak) }).map { ($0.0 + x0, $0.1 + x0) }
        guard !raw.isEmpty else { return nil }
        let gapMax = max(2, 0.12 * median(raw.map { Double($0.1 - $0.0) }))
        var merged: [(Int, Int)] = []
        for run in raw {
            if let last = merged.last, Double(run.0 - last.1) <= gapMax {
                merged[merged.count - 1] = (last.0, run.1)
            } else {
                merged.append(run)
            }
        }
        let typical = median(merged.map { Double($0.1 - $0.0) })
        var columns = merged.filter { Double($0.1 - $0.0) <= 2.5 * typical && $0.1 - $0.0 >= 2 }
        if columns.isEmpty { columns = merged }
        let widths = columns.map { Double($0.1 - $0.0) }.sorted()
        var em = widths[min(widths.count - 1, widths.count * 3 / 4)] / 0.9
        guard em >= 6 else { return nil }

        // 2. The column under the point (furigana columns are too narrow to count).
        var main = columns.filter { Double($0.1 - $0.0) >= 0.5 * em }
        if main.isEmpty { main = columns }
        func distance(_ c: (Int, Int)) -> Int { (c.0 - 2...c.1 + 2).contains(px) ? 0 : min(abs(c.0 - px), abs(c.1 - px)) }
        guard let column = main.min(by: { distance($0) < distance($1) }), Double(distance(column)) <= em else { return nil }
        let w = Double(column.1 - column.0)
        if w < 1.3 * em { em = max(em, w / 0.95) }
        let cx = Double(column.0 + column.1) / 2
        let half = max(w * 0.6, em * 0.5)
        let xa = max(0, Int(cx - half)), xb = min(W, Int(cx + half))
        guard xb - xa >= 4 else { return nil }

        // 3. Character cells down the column.
        let ya = max(0, Int(Double(py) - 25 * em)), yb = min(H, Int(Double(py) + 25 * em))
        let background = rowBackground(image, x0: xa - Int(em), x1: xb + Int(em), y0: ya, y1: yb)
        guard !background.isEmpty else { return nil }
        var inkRows = [Bool](repeating: false, count: yb - ya)
        for y in ya..<yb {
            let limit = 0.62 * background[y - ya]
            for x in xa..<xb where Double(image.at(x, y)) < limit {
                inkRows[y - ya] = true
                break
            }
        }
        var grouped: [(Int, Int)] = []
        for seg in runs(inkRows) {
            if let last = grouped.last, Double(seg.1 - last.0) <= 1.05 * em, Double(seg.0 - last.1) < 0.5 * em {
                grouped[grouped.count - 1] = (last.0, seg.1)
            } else {
                grouped.append(seg)
            }
        }
        var cells: [(Int, Int)] = []
        for (a, b) in grouped {
            let length = Double(b - a)
            let n = length > 1.3 * em ? max(1, Int((length / em).rounded())) : 1
            for k in 0..<n {
                cells.append((ya + a + Int(length * Double(k) / Double(n)), ya + a + Int(length * Double(k + 1) / Double(n))))
            }
        }
        guard !cells.isEmpty else { return nil }
        func cellDistance(_ c: (Int, Int)) -> Int { (c.0...c.1).contains(py) ? 0 : min(abs(c.0 - py), abs(c.1 - py)) }
        let hit = cells.indices.min { cellDistance(cells[$0]) < cellDistance(cells[$1]) }!
        guard Double(cellDistance(cells[hit])) <= em else { return nil }
        // Keep the stretch of text around the point (a big gap ends the column).
        var s = hit, e = hit
        while s > 0, Double(cells[s].0 - cells[s - 1].1) < 1.5 * em { s -= 1 }
        while e < cells.count - 1, Double(cells[e + 1].0 - cells[e].1) < 1.5 * em { e += 1 }

        var fullBackground = [Double](repeating: 255, count: H)
        for y in ya..<yb { fullBackground[y] = background[y - ya] }
        return Column(x0: xa, x1: xb, em: em, cells: Array(cells[s...e]), hit: hit - s, background: fullBackground)
    }

    // MARK: Tile

    struct Tile {
        var image: CGImage
        var pad: Int
        var step: Int
    }

    /// Lays the cells out left to right, each glyph cleaned up and centred.
    static func makeTile(_ image: GrayImage, column: Column) -> Tile? {
        let em = max(8, Int(column.em.rounded()))
        let step = Int(Double(em) * 1.15), pad = em / 2
        let tileW = column.cells.count * step + 2 * pad, tileH = em + 2 * pad
        guard let context = CGContext(data: nil, width: tileW, height: tileH, bitsPerComponent: 8, bytesPerRow: tileW,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: tileW, height: tileH))
        context.interpolationQuality = .high
        let cw = column.x1 - column.x0

        for (i, cell) in column.cells.enumerated() {
            let ch = cell.1 - cell.0
            guard ch > 0 else { continue }
            // Normalize against the paper so shadows don't matter.
            var values = [Double](repeating: 1, count: cw * ch)
            var low = 1.0
            for y in 0..<ch {
                let bg = column.background[cell.0 + y]
                for x in 0..<cw {
                    let v = min(1, Double(image.at(column.x0 + x, cell.0 + y)) / bg)
                    values[y * cw + x] = v
                    low = min(low, v)
                }
            }
            let range = max(0.05, 0.9 - low)
            var bytes = [UInt8](repeating: 255, count: cw * ch)
            var minX = cw, maxX = -1, minY = ch, maxY = -1
            for y in 0..<ch {
                for x in 0..<cw {
                    let v = UInt8(max(0, min(255, (values[y * cw + x] - low) / range * 255)))
                    bytes[y * cw + x] = v
                    if v < 140 {
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else { continue }
            var gw = maxX - minX + 1, gh = maxY - minY + 1
            var glyph = [UInt8](repeating: 255, count: gw * gh)
            for y in 0..<gh { for x in 0..<gw { glyph[y * gw + x] = bytes[(minY + y) * cw + minX + x] } }

            let ox = pad + i * step, oy = pad
            var target: CGRect
            if Double(gw) < 0.35 * Double(em) && Double(gh) > 0.5 * Double(em) {
                // A long vertical stroke (ー, ――, brackets): turn it to its horizontal form.
                var turned = [UInt8](repeating: 255, count: gw * gh)
                for y in 0..<gh { for x in 0..<gw { turned[(gw - 1 - x) * gh + y] = glyph[y * gw + x] } }
                glyph = turned
                swap(&gw, &gh)
                target = CGRect(x: ox + (em - gw) / 2, y: oy + (em - gh) / 2, width: gw, height: gh)
            } else if Double(gh) < 0.5 * Double(em) && Double(gw) < 0.6 * Double(em) && Double(minX) > 0.35 * Double(cw) {
                // A small mark at the top right (、。っ in vertical): bottom left, as in horizontal text.
                target = CGRect(x: ox + em / 10, y: oy + em - gh, width: gw, height: gh)
            } else {
                target = CGRect(x: ox + (em - gw) / 2, y: oy + (em - gh) / 2, width: gw, height: gh)
            }
            // Too big for the cell (a neighbour crept in): shrink to fit.
            if target.width > CGFloat(em) || target.height > CGFloat(em) {
                let s = CGFloat(em) / max(target.width, target.height)
                let size = CGSize(width: target.width * s, height: target.height * s)
                target = CGRect(x: CGFloat(ox) + (CGFloat(em) - size.width) / 2, y: CGFloat(oy) + (CGFloat(em) - size.height) / 2,
                                width: size.width, height: size.height)
            }
            guard let provider = CGDataProvider(data: Data(glyph) as CFData),
                  let glyphImage = CGImage(width: gw, height: gh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: gw,
                                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { continue }
            // Core Graphics counts y from the bottom.
            context.draw(glyphImage, in: CGRect(x: target.minX, y: CGFloat(tileH) - target.maxY, width: target.width, height: target.height))
        }
        guard let tile = context.makeImage() else { return nil }
        return Tile(image: tile, pad: pad, step: step)
    }

    // MARK: Recognition

    static func recognize(_ tile: Tile, column: Column, image: GrayImage) -> Result? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: tile.image, options: [:]).perform([request])
        let tileW = Double(tile.image.width)
        var found: [(cell: Int, char: Character)] = []
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var index = string.startIndex
            while index < string.endIndex {
                let next = string.index(after: index)
                let char = string[index]
                if !char.isWhitespace, let box = try? candidate.boundingBox(for: index..<next)?.boundingBox {
                    let cell = Int((box.midX * tileW - Double(tile.pad)) / Double(tile.step))
                    if column.cells.indices.contains(cell) { found.append((cell, normalized(char))) }
                }
                index = next
            }
        }
        guard !found.isEmpty else { return nil }
        let W = Double(image.width), H = Double(image.height)
        var line = OCRLine(text: [], boxes: [])
        var hit: Int?
        for item in found {
            let cell = column.cells[item.cell]
            line.text.append(item.char)
            line.boxes.append(CGRect(x: Double(column.x0) / W, y: 1 - Double(cell.1) / H,
                                     width: Double(column.x1 - column.x0) / W, height: Double(cell.1 - cell.0) / H))
            if hit == nil, item.cell >= column.hit { hit = line.text.count - 1 }
        }
        return Result(line: line, hit: hit ?? line.text.count - 1)
    }

    /// Vertical-only shapes the recognizer may return as something else.
    private static func normalized(_ c: Character) -> Character {
        switch c {
        case "|", "｜", "丨": "ー"
        case "﹁": "「"
        case "﹂": "」"
        case "﹃": "『"
        case "﹄": "』"
        default: c
        }
    }
}
