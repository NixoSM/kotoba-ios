#if os(macOS)
import CoreGraphics
import CoreText
import Foundation
import ImageIO
@testable import KotobaOCR

/// A 縦書き page drawn with a real Japanese font, and where every character is.
struct RenderedPage {
    var image: GrayImage
    /// Columns right to left; characters top to bottom with their centres (pixels, origin top-left).
    var columns: [[(char: Character, center: CGPoint)]]
    var em: CGFloat
}

/// Draws vertical text the way a bunko is printed: a square grid of characters,
/// columns right to left, brackets and long vowels turned, 、。 in the top-right
/// corner of their cell, small kana shifted up and right, furigana on the right.
/// Then it makes the page look photographed: tilt, shade towards the spine, blur, noise.
enum PageRenderer {
    struct Style {
        var name: String
        var em: CGFloat = 32
        /// Distance between column centres, in em.
        var columnPitch: CGFloat = 1.75
        /// Degrees, counter-clockwise.
        var angle: CGFloat = 0
        var blurPasses = 0
        var noise = 0.0
        /// 0...1: how much darker the left edge is.
        var shade = 0.0
        var paper: CGFloat = 0.93
        var ink: CGFloat = 0.12
        var seed: UInt64 = 7
    }

    struct Ruby {
        var column: Int, start: Int, count: Int, text: String
    }

    private static let turned = Set("ー―‐…‥〜～「」『』（）【】〈〉《》")
    private static let commas = Set("、。，．")
    private static let small = Set("ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ")

    static func render(_ columns: [String], ruby: [Ruby] = [], style: Style) -> RenderedPage {
        let em = style.em
        let pitch = style.columnPitch * em
        let rows = columns.map(\.count).max() ?? 1
        let margin = 2.5 * em
        let W = Int(margin * 2 + CGFloat(columns.count) * pitch), H = Int(margin * 2 + CGFloat(rows) * em)
        var pixels = [UInt8](repeating: 255, count: W * H)
        var truth: [[(char: Character, center: CGPoint)]] = []
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setFillColor(gray: style.paper, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: W, height: H))
            // Tilt around the centre (Core Graphics counts y from the bottom).
            let tilt = CGAffineTransform(translationX: CGFloat(W) / 2, y: CGFloat(H) / 2)
                .rotated(by: style.angle * .pi / 180)
                .translatedBy(x: -CGFloat(W) / 2, y: -CGFloat(H) / 2)
            context.concatenate(tilt)
            let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, em, nil)
            let rubyFont = CTFontCreateWithName("HiraMinProN-W3" as CFString, em / 2, nil)
            let color = CGColor(gray: style.ink, alpha: 1)

            for (c, text) in columns.enumerated() {
                let cx = CGFloat(W) - margin - pitch * (CGFloat(c) + 0.5)
                var column: [(char: Character, center: CGPoint)] = []
                for (i, char) in text.enumerated() {
                    let cyDown = margin + em * (CGFloat(i) + 0.5)
                    let center = CGPoint(x: cx, y: CGFloat(H) - cyDown)
                    draw(char, at: center, font: font, em: em, color: color, in: context)
                    let p = center.applying(tilt)
                    column.append((char, CGPoint(x: p.x, y: CGFloat(H) - p.y)))
                }
                truth.append(column)
            }
            for r in ruby {
                let cx = CGFloat(W) - margin - pitch * (CGFloat(r.column) + 0.5) + 0.78 * em
                let spanTop = margin + em * CGFloat(r.start), spanHeight = em * CGFloat(r.count)
                let n = CGFloat(r.text.count)
                let step = min(em / 2, spanHeight / n)
                let top = spanTop + (spanHeight - step * n) / 2
                for (k, char) in r.text.enumerated() {
                    let cyDown = top + step * (CGFloat(k) + 0.5)
                    draw(char, at: CGPoint(x: cx, y: CGFloat(H) - cyDown), font: rubyFont, em: em / 2, color: color, in: context)
                }
            }
        }
        var image = GrayImage(width: W, height: H, pixels: pixels)
        degrade(&image, style: style)
        return RenderedPage(image: image, columns: truth, em: em)
    }

    /// One character centred on `center` (Core Graphics coordinates), in its vertical form.
    private static func draw(_ char: Character, at center: CGPoint, font: CTFont, em: CGFloat, color: CGColor, in context: CGContext) {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, String(char) as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(string)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        if turned.contains(char) {
            context.rotate(by: -.pi / 2)
        } else if commas.contains(char) {
            context.translateBy(x: 0.5 * em, y: 0.6 * em)
        } else if small.contains(char) {
            context.translateBy(x: 0.1 * em, y: 0.12 * em)
        }
        // The ideographic em box runs from 0.12 em below the baseline to 0.88 em above.
        context.textPosition = CGPoint(x: -width / 2, y: -0.38 * em)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func degrade(_ image: inout GrayImage, style: Style) {
        let W = image.width, H = image.height
        if style.shade > 0 {
            for y in 0..<H {
                for x in 0..<W {
                    let f = 1 - style.shade * (1 - Double(x) / Double(W)) * (0.7 + 0.3 * Double(y) / Double(H))
                    image.pixels[y * W + x] = UInt8(Double(image.pixels[y * W + x]) * f)
                }
            }
        }
        for _ in 0..<style.blurPasses { boxBlur(&image) }
        if style.noise > 0 {
            var state = style.seed &* 0x9E37_79B9_7F4A_7C15 | 1
            for i in image.pixels.indices {
                state ^= state >> 12; state ^= state << 25; state ^= state >> 27
                let r = Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
                let v = Double(image.pixels[i]) + (r * 2 - 1) * style.noise
                image.pixels[i] = UInt8(max(0, min(255, v)))
            }
        }
    }

    private static func boxBlur(_ image: inout GrayImage) {
        let W = image.width, H = image.height
        var out = image.pixels
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                var sum = 0
                for dy in -1...1 { for dx in -1...1 { sum += Int(image.pixels[(y + dy) * W + x + dx]) } }
                out[y * W + x] = UInt8(sum / 9)
            }
        }
        image.pixels = out
    }
}

enum BenchOutput {
    /// Set by CI: pictures land there and are uploaded with the run.
    static let folder: URL? = ProcessInfo.processInfo.environment["KOTOBA_BENCH_OUT"].map { URL(fileURLWithPath: $0) }

    static func save(_ image: CGImage?, _ name: String) {
        guard let folder, let image else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name + ".png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
