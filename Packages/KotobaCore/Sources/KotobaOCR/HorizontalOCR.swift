import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Horizontal text through Apple's recognizer, with a box for every character.
public enum HorizontalOCR {
    /// - Parameters:
    ///   - region: only read this part (normalized, origin bottom-left); boxes still come back for the whole image.
    ///   - languageCorrection: better words, slower; worth it on a still photo, not on every camera frame.
    public static func lines(in image: CGImage, region: CGRect? = nil, languageCorrection: Bool = true) -> [OCRLine] {
        lines(VNImageRequestHandler(cgImage: image, options: [:]), region: region, languageCorrection: languageCorrection)
    }

    public static func lines(in buffer: CVPixelBuffer, region: CGRect? = nil, languageCorrection: Bool = false) -> [OCRLine] {
        lines(VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]), region: region, languageCorrection: languageCorrection)
    }

    private static func lines(_ handler: VNImageRequestHandler, region: CGRect?, languageCorrection: Bool) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = languageCorrection
        if let region { request.regionOfInterest = region }
        try? handler.perform([request])
        let roi = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let string = candidate.string
            var chars: [Character] = []
            var boxes: [CGRect] = []
            var index = string.startIndex
            while index < string.endIndex {
                let next = string.index(after: index)
                var box = (try? candidate.boundingBox(for: index..<next))?.boundingBox ?? .zero
                if box != .zero {
                    // With a region of interest, Vision answers relative to it.
                    box = CGRect(x: roi.minX + box.minX * roi.width, y: roi.minY + box.minY * roi.height,
                                 width: box.width * roi.width, height: box.height * roi.height)
                }
                chars.append(string[index])
                boxes.append(box)
                index = next
            }
            return chars.isEmpty ? nil : OCRLine(text: chars, boxes: boxes)
        }
    }
}
