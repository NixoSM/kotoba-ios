import CoreGraphics
import CoreVideo
import Foundation

/// An 8-bit grayscale copy of an image, origin top-left.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Renders an image, scaled down so its long side is at most `maxSide`.
    public init?(cgImage: CGImage, maxSide: Int = 2400) {
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

    /// From a camera frame in BGRA. `crop` (pixels, origin top-left) keeps only part of it.
    public init?(pixelBuffer: CVPixelBuffer, crop: CGRect? = nil) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let fullW = CVPixelBufferGetWidth(pixelBuffer), fullH = CVPixelBufferGetHeight(pixelBuffer)
        let area = (crop ?? CGRect(x: 0, y: 0, width: fullW, height: fullH))
            .integral.intersection(CGRect(x: 0, y: 0, width: fullW, height: fullH))
        guard !area.isNull, area.width >= 8, area.height >= 8 else { return nil }
        let x0 = Int(area.minX), y0 = Int(area.minY), w = Int(area.width), h = Int(area.height)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let source = base.assumingMemoryBound(to: UInt8.self)
        var buffer = [UInt8](repeating: 0, count: w * h)
        buffer.withUnsafeMutableBufferPointer { out in
            for y in 0..<h {
                let row = source + (y0 + y) * rowBytes + x0 * 4
                for x in 0..<w {
                    let p = row + x * 4
                    out[y * w + x] = UInt8((Int(p[2]) * 77 + Int(p[1]) * 150 + Int(p[0]) * 29) >> 8)
                }
            }
        }
        self.init(width: w, height: h, pixels: buffer)
    }

    @inline(__always) public func at(_ x: Int, _ y: Int) -> UInt8 { pixels[y * width + x] }

    /// A copy as a CGImage (for Vision, or to look at in a test).
    public func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A line of recognized text with a box for every character, in Vision's
/// normalized coordinates (0...1, origin bottom-left).
public struct OCRLine: Sendable, Equatable {
    public var text: [Character]
    public var boxes: [CGRect]
    /// Read top to bottom (縦書き).
    public var vertical: Bool

    public init(text: [Character], boxes: [CGRect], vertical: Bool = false) {
        self.text = text
        self.boxes = boxes
        self.vertical = vertical
    }

    /// Everything the line covers.
    public var frame: CGRect {
        boxes.filter { $0 != .zero }.reduce(CGRect.null) { $0.union($1) }
    }

    /// The same line with every box moved by `transform` (for example from a crop to the whole frame).
    public func mapped(_ transform: (CGRect) -> CGRect) -> OCRLine {
        OCRLine(text: text, boxes: boxes.map { $0 == .zero ? .zero : transform($0) }, vertical: vertical)
    }

    /// Where `point` falls along the line, in characters: 2.5 is the middle of the
    /// third character. `toView` turns a box into the space of `point`, with y going
    /// down (screen points, image pixels); `reach` is the farthest a character may be.
    public func position(of point: CGPoint, reach: CGFloat, toView: (CGRect) -> CGRect) -> Double? {
        var best: (index: Int, rect: CGRect, distance: CGFloat)?
        for (i, box) in boxes.enumerated() where box != .zero {
            let rect = toView(box)
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= reach, distance < (best?.distance ?? .infinity) { best = (i, rect, distance) }
        }
        guard let best else { return nil }
        let r = best.rect
        let along = vertical ? (point.y - r.minY) / max(r.height, 1e-6) : (point.x - r.minX) / max(r.width, 1e-6)
        return Double(best.index) + Double(min(max(along, 0), 0.999))
    }
}
