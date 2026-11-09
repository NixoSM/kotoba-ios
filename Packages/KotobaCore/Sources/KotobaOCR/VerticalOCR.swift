import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Reads vertical Japanese (縦書き), which Apple's text recognizer can't.
///
/// The idea: find the column under a point, cut it into character cells
/// (typeset text sits on a square grid), and lay the cells side by side as a
/// horizontal line. Apple's recognizer reads that line well, and every
/// character it returns maps back to its cell on the page.
public enum VerticalOCR {
    public struct Result: Sendable {
        /// The column's text, top to bottom, with a box for every character
        /// (normalized to the image, origin bottom-left).
        public var line: OCRLine
        /// Index in `line.text` of the character at the point.
        public var hit: Int
        /// Where the point falls inside that character, 0 (top) to 1 (bottom).
        public var fraction: Double
        /// Character size in pixels.
        public var em: Double
        /// The column's area, normalized like the boxes.
        public var frame: CGRect
        /// Aim position in characters along the line, for `WordAim`.
        public var position: Double { Double(hit) + fraction }
    }

    /// Reads the column under `point` (pixels, origin top-left).
    public static func read(_ image: GrayImage, at point: CGPoint) -> Result? {
        guard let column = findColumn(image, at: point) else { return nil }
        guard let tile = makeTile(image, column: column) else { return nil }
        return recognize(tile, column: column, image: image)
    }

    // MARK: Layout

    struct Column {
        /// Centre of the column on the point's row, and how far it drifts per row (a tilted page).
        var center: Double
        var slope: Double
        var aimY: Int
        /// Half the column's width.
        var half: Double
        /// Character pitch (the advance from one character to the next).
        var em: Double
        /// Character cells, top to bottom: (top, bottom) rows.
        var cells: [(Int, Int)]
        /// The cell under the point.
        var hit: Int
        /// Paper brightness per row (the whole image height).
        var background: [Double]

        /// The column's pixels on row `y`.
        func xRange(_ y: Int, width: Int) -> (Int, Int) {
            let c = center + Double(y - aimY) * slope
            return (max(0, Int((c - half).rounded())), min(width, Int((c + half).rounded())))
        }
    }

    /// Brightness of the paper on each row: a high percentile across a band, smoothed.
    /// `span(y)` gives the band on row y.
    private static func rowBackground(_ image: GrayImage, y0: Int, y1: Int, span: (Int) -> (Int, Int)) -> [Double] {
        guard y1 > y0 else { return [] }
        var raw = [Double](repeating: 255, count: y1 - y0)
        var values: [UInt8] = []
        for y in y0..<y1 {
            let (a, b) = span(y)
            let lo = max(0, a), hi = min(image.width, b)
            guard hi > lo else { continue }
            values.removeAll(keepingCapacity: true)
            for x in lo..<hi { values.append(image.at(x, y)) }
            values.sort()
            raw[y - y0] = Double(values[min(values.count - 1, values.count * 9 / 10)])
        }
        let k = max(3, image.height / 170)
        let padded = Array(repeating: raw.first ?? 255, count: k) + raw + Array(repeating: raw.last ?? 255, count: k)
        var smooth = raw
        var sum = padded[0..<(2 * k + 1)].reduce(0, +)
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
        let r = Int(Double(min(W, H)) * 0.12), rv = Int(Double(H) * 0.15)
        let x0 = max(0, px - r), x1 = min(W, px + r), y0 = max(0, py - rv), y1 = min(H, py + rv)
        guard x1 - x0 >= 8 else { return nil }
        let bg = rowBackground(image, y0: y0, y1: y1) { _ in (x0, x1) }
        guard !bg.isEmpty else { return nil }
        var profile = [Int](repeating: 0, count: x1 - x0)
        for y in y0..<y1 {
            let limit = 0.62 * bg[y - y0]
            for x in x0..<x1 where Double(image.at(x, y)) < limit { profile[x - x0] += 1 }
        }
        guard let peak = profile.max(), peak > 0 else { return nil }
        let raw = runs(profile.map { Double($0) > 0.12 * Double(peak) })
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
        // Columns cut by the window's edges, furigana and emphasis dots are narrower than
        // the real thing: the size comes from the wider whole runs.
        func whole(_ run: (Int, Int)) -> Bool { run.0 > 0 && run.1 < x1 - x0 }
        func upperQuartile(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 3 / 4)]
        }
        let inner = merged.filter(whole)
        let typical = upperQuartile((inner.isEmpty ? merged : inner).map { Double($0.1 - $0.0) })
        guard typical >= 2 else { return nil }
        // A run much wider than that is a column with its furigana stuck to it: cut at the deepest valley.
        var columns: [(Int, Int)] = []
        for run in merged {
            let width = run.1 - run.0
            guard Double(width) > 1.45 * typical, width >= 8 else { columns.append(run); continue }
            let middle = (run.0 + width / 6)..<(run.1 - width / 6)
            let top = profile[run.0..<run.1].max() ?? 0
            if let cut = middle.min(by: { profile[$0] < profile[$1] }), Double(profile[cut]) < 0.3 * Double(top),
               Double(min(cut - run.0, run.1 - cut)) <= 0.65 * typical, Double(max(cut - run.0, run.1 - cut)) >= 0.75 * typical {
                columns.append((run.0, cut))
                columns.append((cut + 1, run.1))
            } else {
                columns.append(run)
            }
        }
        columns = columns.filter { $0.1 - $0.0 >= 2 }
        guard !columns.isEmpty else { return nil }
        var widths = columns.filter { whole($0) && Double($0.1 - $0.0) <= 2.5 * typical }.map { Double($0.1 - $0.0) }
        if widths.isEmpty { widths = columns.filter { Double($0.1 - $0.0) <= 2.5 * typical }.map { Double($0.1 - $0.0) } }
        if widths.isEmpty { widths = columns.map { Double($0.1 - $0.0) } }
        columns = columns.map { ($0.0 + x0, $0.1 + x0) }
        var em = upperQuartile(widths) / 0.9
        guard em >= 6 else { return nil }

        // 2. The column under the point (furigana columns are too narrow to count).
        var main = columns.filter { Double($0.1 - $0.0) >= 0.5 * em && Double($0.1 - $0.0) <= 2.5 * typical }
        if main.isEmpty { main = columns }
        func distance(_ c: (Int, Int)) -> Int { (c.0 - 2...c.1 + 2).contains(px) ? 0 : min(abs(c.0 - px), abs(c.1 - px)) }
        guard let column = main.min(by: { distance($0) < distance($1) }), Double(distance(column)) <= em else { return nil }
        let w = Double(column.1 - column.0)
        if w < 1.3 * em { em = max(em, w / 0.95) }
        let widthEm = em

        // 3. Follow the column up and down: the glyphs' centres give its centre line, tilt included.
        let (center, slope) = trackColumn(image, x: Double(column.0 + column.1) / 2, y: py, width: w, em: em)
        let half = max(w * 0.6, em * 0.5)
        func xRange(_ y: Int) -> (Int, Int) {
            let c = center + Double(y - py) * slope
            return (max(0, Int((c - half).rounded())), min(W, Int((c + half).rounded())))
        }

        // 4. Ink along the column. Its period is the character pitch, a better size than any width.
        let reach = 25 * em
        let ya = max(0, Int(Double(py) - reach)), yb = min(H, Int(Double(py) + reach))
        let background = rowBackground(image, y0: ya, y1: yb) { y in
            let (a, b) = xRange(y)
            return (a - Int(em), b + Int(em))
        }
        guard !background.isEmpty else { return nil }
        var inkCount = [Int](repeating: 0, count: yb - ya)
        for y in ya..<yb {
            let limit = 0.62 * background[y - ya]
            let (a, b) = xRange(y)
            guard b > a else { continue }
            for x in a..<b where Double(image.at(x, y)) < limit { inkCount[y - ya] += 1 }
        }
        if let pitch = pitch(of: inkCount, around: widthEm) { em = pitch }

        // 5. Character cells down the column.
        var grouped: [(Int, Int)] = []
        for seg in runs(inkCount.map { $0 > 0 }) {
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
        // One pitch wide around the centre line: whole characters, but not the furigana beside them.
        let band = min(max(0.55 * w, 0.5 * em), 0.62 * em)
        return Column(center: center, slope: slope, aimY: py, half: band, em: em,
                      cells: Array(cells[s...e]), hit: hit - s, background: fullBackground)
    }

    /// Walks along the column a character at a time and fits a line through the
    /// centres of the ink: pages are rarely square to the camera, and a column
    /// tilted by 2° drifts a whole character sideways over its length.
    private static func trackColumn(_ image: GrayImage, x: Double, y: Int, width: Double, em: Double) -> (center: Double, slope: Double) {
        let W = image.width, H = image.height
        let half = max(0.5 * width, 0.45 * em)
        let step = max(4, Int(em))
        var points: [(y: Double, x: Double)] = []
        for direction in [1, -1] {
            var cx = x
            var top = direction == 1 ? y : y - step
            for _ in 0..<28 {
                let ya = max(0, top), yb = min(H, top + step)
                let lo = max(0, Int(cx - half)), hi = min(W, Int(cx + half))
                guard yb - ya >= 2, hi - lo >= 4 else { break }
                // Paper level for this stretch, from a wider band.
                var values: [UInt8] = []
                let wlo = max(0, lo - step), whi = min(W, hi + step)
                for yy in stride(from: ya, to: yb, by: 2) { for xx in stride(from: wlo, to: whi, by: 2) { values.append(image.at(xx, yy)) } }
                values.sort()
                let limit = 0.62 * Double(values.isEmpty ? 255 : values[min(values.count - 1, values.count * 9 / 10)])
                var n = 0, sum = 0
                for yy in ya..<yb { for xx in lo..<hi where Double(image.at(xx, yy)) < limit { n += 1; sum += xx } }
                if Double(n) > 0.04 * Double((yb - ya) * (hi - lo)) {
                    let centroid = Double(sum) / Double(n)
                    points.append((Double(ya + yb) / 2, centroid))
                    cx = 0.6 * cx + 0.4 * centroid
                }
                top += direction * step
                if top >= H || top + step <= 0 { break }
            }
        }
        guard points.count >= 3 else { return (x, 0) }
        // Least squares, then again without the points far from the line (、。 sit off-centre).
        var keep = Array(repeating: true, count: points.count)
        var fit = (center: x, slope: 0.0)
        for _ in 0..<3 {
            let used = points.indices.filter { keep[$0] }
            guard used.count >= 3 else { break }
            let n = Double(used.count)
            let my = used.reduce(0.0) { $0 + points[$1].y } / n, mx = used.reduce(0.0) { $0 + points[$1].x } / n
            let sxy = used.reduce(0.0) { $0 + (points[$1].y - my) * (points[$1].x - mx) }
            let syy = used.reduce(0.0) { $0 + (points[$1].y - my) * (points[$1].y - my) }
            let slope = syy > 0 ? max(-0.14, min(0.14, sxy / syy)) : 0
            fit = (mx + slope * (Double(y) - my), slope)
            let residuals = points.map { abs($0.x - (fit.center + fit.slope * ($0.y - Double(y)))) }
            let cut = max(0.18 * em, residuals.sorted()[residuals.count * 7 / 10])
            keep = residuals.map { $0 <= cut }
        }
        return fit
    }

    /// The period of the ink along a column: printed characters sit on a fixed pitch.
    /// `guess` (from the column widths) only bounds the search.
    private static func pitch(of ink: [Int], around guess: Double) -> Double? {
        let n = ink.count
        guard n > Int(4 * guess) else { return nil }
        let mean = Double(ink.reduce(0, +)) / Double(n)
        let p = ink.map { Double($0) - mean }
        let lo = max(2, Int(0.65 * guess)), hi = min(n - 2, Int(1.6 * guess))
        guard hi > lo + 2 else { return nil }
        var scores = [Double](repeating: -1, count: hi + 1)
        var best: (lag: Int, score: Double)?
        for lag in lo...hi {
            var ab = 0.0, aa = 0.0, bb = 0.0
            for i in 0..<(n - lag) { ab += p[i] * p[i + lag]; aa += p[i] * p[i]; bb += p[i + lag] * p[i + lag] }
            let score = ab / max(1e-9, (aa * bb).squareRoot())
            scores[lag] = score
            if score > (best?.score ?? -1) { best = (lag, score) }
        }
        // A best lag at the edge of the range is the range talking, not the text.
        guard let best, best.score > 0.12, best.lag > lo, best.lag < hi else { return nil }
        // Sub-pixel: the peak of a parabola through the best lag and its neighbours.
        if best.lag > lo, best.lag < hi {
            let a = scores[best.lag - 1], b = scores[best.lag], c = scores[best.lag + 1]
            let d = a - 2 * b + c
            if d < 0 { return Double(best.lag) + 0.5 * (a - c) / d }
        }
        return Double(best.lag)
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

        for (i, cell) in column.cells.enumerated() {
            let ch = cell.1 - cell.0
            let (cx0, cx1) = column.xRange((cell.0 + cell.1) / 2, width: image.width)
            let cw = cx1 - cx0
            guard ch > 0, cw > 0 else { continue }
            // Normalize against the paper so shadows don't matter.
            var values = [Double](repeating: 1, count: cw * ch)
            var low = 1.0
            for y in 0..<ch {
                let bg = column.background[cell.0 + y]
                for x in 0..<cw {
                    let v = min(1, Double(image.at(cx0 + x, cell.0 + y)) / bg)
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
            let turn = Double(gw) < 0.35 * Double(em) && Double(gh) > 0.5 * Double(em)  // ー, ――, …, 〜
                || isCornerBracket(glyph, width: gw, height: gh, em: Double(em))          // ﹁﹂﹃﹄
            if turn {
                // Printed turned in vertical text: turn it back to its horizontal form.
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

    /// A corner bracket in its vertical form: thin strokes along two adjacent sides
    /// of its box (top and right: ﹁ opening; bottom and left: ﹂ closing), the
    /// other two sides empty. The recognizer reads them as the wrong bracket.
    static func isCornerBracket(_ glyph: [UInt8], width gw: Int, height gh: Int, em: Double) -> Bool {
        guard Double(max(gw, gh)) <= 1.0 * em, Double(min(gw, gh)) <= 0.55 * em,
              Double(min(gw, gh)) >= 0.15 * em, gw >= 4, gh >= 4 else { return false }
        var ink = 0
        for v in glyph where v < 140 { ink += 1 }
        guard Double(ink) < 0.4 * Double(gw * gh) else { return false }
        let bx = max(1, gw / 6), by = max(1, gh / 6)
        func covered(_ xs: Range<Int>, _ ys: Range<Int>, along horizontal: Bool) -> Double {
            // Share of the side's length that has ink within the band.
            let length = horizontal ? xs.count : ys.count
            var hits = 0
            if horizontal {
                for x in xs where ys.contains(where: { glyph[$0 * gw + x] < 140 }) { hits += 1 }
            } else {
                for y in ys where xs.contains(where: { glyph[y * gw + $0] < 140 }) { hits += 1 }
            }
            return Double(hits) / Double(max(1, length))
        }
        let top = covered(0..<gw, 0..<by, along: true), bottom = covered(0..<gw, (gh - by)..<gh, along: true)
        let left = covered(0..<bx, 0..<gh, along: false), right = covered((gw - bx)..<gw, 0..<gh, along: false)
        let full = 0.75, empty = 0.45
        return (top >= full && right >= full && bottom < empty && left < empty)
            || (bottom >= full && left >= full && top < empty && right < empty)
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
        found = tidy(found)
        let W = Double(image.width), H = Double(image.height)
        var line = OCRLine(text: [], boxes: [], vertical: true)
        var hit: Int?
        var fraction = 0.0
        for item in found {
            let cell = column.cells[item.cell]
            let (x0, x1) = column.xRange((cell.0 + cell.1) / 2, width: image.width)
            line.text.append(item.char)
            line.boxes.append(CGRect(x: Double(x0) / W, y: 1 - Double(cell.1) / H,
                                     width: Double(x1 - x0) / W, height: Double(cell.1 - cell.0) / H))
            if hit == nil, item.cell >= column.hit {
                hit = line.text.count - 1
                if item.cell == column.hit {
                    fraction = min(0.999, max(0, Double(column.aimY - cell.0) / Double(max(1, cell.1 - cell.0))))
                }
            }
        }
        if hit == nil { fraction = 0.999 }
        return Result(line: line, hit: hit ?? line.text.count - 1, fraction: fraction, em: column.em, frame: line.frame)
    }

    /// Fixes vertical punctuation from the characters around it: a 。 read as two
    /// dots, and brackets (turned in vertical text) read as a dash or as the
    /// wrong bracket. Both break the sentence sent to Anki.
    static func tidy(_ items: [(cell: Int, char: Character)]) -> [(cell: Int, char: Character)] {
        let dots: Set<Character> = [".", "．", "·", "・", "。", "｡"]
        let commas: Set<Character> = [",", "，", "、", "､"]
        // Several marks in one cell: one 。 or 、.
        var merged: [(cell: Int, char: Character)] = []
        var i = 0
        while i < items.count {
            var j = i
            while j + 1 < items.count, items[j + 1].cell == items[i].cell { j += 1 }
            let group = items[i...j].map(\.char)
            if group.count > 1, group.allSatisfy({ dots.contains($0) || commas.contains($0) }) {
                merged.append((items[i].cell, group.contains(where: { commas.contains($0) }) ? "、" : "。"))
            } else {
                merged.append(contentsOf: items[i...j])
            }
            i = j + 1
        }
        var chars = merged.map(\.char)
        func isKana(_ c: Character) -> Bool {
            guard let v = c.unicodeScalars.first?.value else { return false }
            return (0x3041...0x30FF).contains(v)
        }
        // Vertical text has no use for an ASCII period, except in a number.
        for k in chars.indices where chars[k] == "." || chars[k] == "．" || chars[k] == "｡" {
            let before: Character? = k > 0 ? chars[k - 1] : nil
            let after: Character? = k + 1 < chars.count ? chars[k + 1] : nil
            if !(before?.isNumber == true && after?.isNumber == true) { chars[k] = "。" }
        }
        let strong: Set<Character> = ["-", "－", "_", "→", "‐", "−", "¬", "⌐"]
        let enders: Set<Character> = ["。", "、", "！", "？", "!", "?", "」", "』", "…"]
        var open = 0
        for k in chars.indices {
            let c = chars[k]
            let before: Character? = k > 0 ? chars[k - 1] : nil
            var dash = strong.contains(c)
            // ー after anything but kana (and not part of ――) was a bracket.
            if c == "ー", let before, !isKana(before), k + 1 >= chars.count || chars[k + 1] != "ー" { dash = true }
            if dash {
                // Closing when a quote is open, or right after a word (the quote began in an earlier column).
                let closes = open > 0 || (before != nil && !enders.contains(before!))
                chars[k] = closes ? "」" : "「"
            } else if c == "「", open > 0 {
                chars[k] = "」"
            } else if c == "」", open == 0,
                      let next = chars[(k + 1)...].firstIndex(where: { $0 == "「" || $0 == "」" }), chars[next] == "」" {
                chars[k] = "「"
            }
            if chars[k] == "「" { open += 1 } else if chars[k] == "」" { open = max(0, open - 1) }
        }
        return zip(merged, chars).map { ($0.0.cell, $0.1) }
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
