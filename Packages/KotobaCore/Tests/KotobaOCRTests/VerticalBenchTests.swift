#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import XCTest
import KotobaCore
@testable import KotobaOCR

/// Runs the vertical reader, with Apple's real recognizer, on pages rendered
/// here and on a photo of a light novel, and prints how well it does.
/// The numbers are for tuning: the asserts only catch a reader that broke.
/// Bench lines go to standard error: XCTest's standard output is buffered and
/// gets lost when the log is piped.
private func say(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

final class VerticalBenchTests: XCTestCase {
    // Original text in the style of a light novel (no copyright to worry about).
    static let columns = [
        "放課後の図書室は、いつも静かだった。",
        "窓際の席で本を読んでいた彼女は、僕に",
        "気づくと小さく微笑んだ。「また来たの？」",
        "と彼女は言った。僕は答えられずに、ただ",
        "頷いた。外では雨が降り始めていて、ガラ",
        "スの向こうの景色がぼんやりと滲んでいく。",
        "「ねえ、この本、もう読んだ？」彼女はそう",
        "言って、一冊の文庫本をテーブルに置いた。",
    ]
    static let ruby = [
        PageRenderer.Ruby(column: 0, start: 4, count: 3, text: "としょしつ"),
        PageRenderer.Ruby(column: 2, start: 7, count: 2, text: "ほほえ"),
        PageRenderer.Ruby(column: 4, start: 0, count: 1, text: "うなず"),
        PageRenderer.Ruby(column: 5, start: 14, count: 1, text: "にじ"),
    ]
    static let styles = [
        PageRenderer.Style(name: "clean", em: 40),
        PageRenderer.Style(name: "camera", em: 28, angle: 1.0, blurPasses: 1, noise: 8, shade: 0.3),
        PageRenderer.Style(name: "small", em: 20, angle: -0.6, blurPasses: 1, noise: 8, shade: 0.2),
        PageRenderer.Style(name: "tilted", em: 32, angle: 2.5, blurPasses: 0, noise: 4, shade: 0.15),
    ]

    static let dictionary: MemoryTermSource = {
        let words: [(String, String)] = [
            ("放課後", ""), ("図書室", ""), ("いつも", ""), ("静か", "adj-na"), ("窓際", ""), ("席", ""), ("本", ""),
            ("読む", "v5"), ("彼女", ""), ("僕", ""), ("気づく", "v5"), ("小さい", "adj-i"), ("微笑む", "v5"), ("また", ""),
            ("来る", "vk"), ("言う", "v5"), ("答える", "v1"), ("ただ", ""), ("頷く", "v5"), ("外", ""), ("雨", ""),
            ("降る", "v5"), ("始める", "v1"), ("降り始める", "v1"), ("ガラス", ""), ("向こう", ""), ("景色", ""),
            ("ぼんやり", ""), ("滲む", "v5"), ("ねえ", ""), ("この", ""), ("もう", ""), ("そう", ""), ("一冊", ""),
            ("文庫本", ""), ("文庫", ""), ("テーブル", ""), ("置く", "v5"), ("は", ""), ("の", ""), ("で", ""), ("を", ""),
            ("に", ""), ("と", ""), ("が", ""), ("も", ""), ("では", ""),
        ]
        let rows = words.enumerated().map { i, w in
            "[\"\(w.0)\", \"\(w.0)\", \"\", \"\(w.1)\", 1, [\"x\"], \(i), \"\"]"
        }
        return MemoryTermSource(try! YomitanParser.termBank(from: "[\(rows.joined(separator: ","))]".data(using: .utf8)!))
    }()

    func testSyntheticPages() throws {
        var totalReads = 0, totalFound = 0
        for style in Self.styles {
            let page = PageRenderer.render(Self.columns, ruby: Self.ruby, style: style)
            BenchOutput.save(page.image.cgImage(), "page-\(style.name)")
            var found = 0, hits = 0, reads = 0
            var errors = 0, length = 0
            var seconds = 0.0
            var report: [String] = []
            for (c, column) in page.columns.enumerated() {
                let truth = String(column.map(\.char))
                for i in [2, 9, 15] where i < column.count {
                    reads += 1
                    let started = Date()
                    let result = VerticalOCR.read(page.image, at: column[i].center)
                    seconds += Date().timeIntervalSince(started)
                    guard let result else {
                        errors += truth.count; length += truth.count
                        report.append("  c\(c) @\(i): nothing")
                        continue
                    }
                    found += 1
                    let read = String(result.line.text)
                    let distance = Self.editDistance(Self.normalize(read), Self.normalize(truth))
                    errors += distance; length += truth.count
                    let got = result.line.text.indices.contains(result.hit) ? result.line.text[result.hit] : "∅"
                    if Self.normalize(String(got)) == Self.normalize(String(column[i].char)) { hits += 1 }
                    if i == 9 || distance > 0 {
                        report.append("  c\(c) @\(i) [\(got)≟\(column[i].char)] em \(Int(result.em)) err \(distance): \(read)")
                    }
                }
                if c == 1, let col = VerticalOCR.findColumn(page.image, at: column[9].center),
                   let tile = VerticalOCR.makeTile(page.image, column: col) {
                    BenchOutput.save(tile.image, "tile-\(style.name)")
                }
            }
            totalReads += reads; totalFound += found
            say(String(format: "BENCH synthetic %@ (em %.0f): found %d/%d, aim char %d/%d, CER %.1f%%, %.0f ms/read",
                         style.name, style.em, found, reads, hits, reads, 100 * Double(errors) / Double(max(1, length)), 1000 * seconds / Double(max(1, reads))))
            report.forEach { say($0) }
        }
        XCTAssertGreaterThan(totalFound, totalReads / 2, "The vertical reader stopped finding text")
    }

    /// Aim at a word from many nearby points, as a shaking hand would, and count
    /// how often the word chosen is the right one. One frame, no voting.
    func testAimLandsOnTheWord() throws {
        let targets: [(column: Int, start: Int, length: Int, word: String)] = [
            (0, 4, 3, "図書室"), (1, 0, 2, "窓際"), (1, 12, 2, "彼女"), (2, 7, 4, "微笑んだ"),
            (4, 7, 1, "雨"), (5, 6, 2, "景色"), (7, 11, 4, "テーブル"), (7, 7, 3, "文庫本"),
        ]
        let scanner = TextScanner()
        for style in [Self.styles[1], Self.styles[2]] {
            let page = PageRenderer.render(Self.columns, ruby: Self.ruby, style: style)
            var right = 0, total = 0
            var lines: [String] = []
            for target in targets {
                let column = page.columns[target.column]
                var ok = 0, tries = 0
                var wrong: [String] = []
                // Along the word from just before its first character to inside its last, and a bit off the column centre.
                let along = stride(from: -0.3, through: Double(target.length) - 0.3, by: 0.35)
                for (k, t) in along.enumerated() {
                    let index = min(column.count - 1, max(0, target.start + Int(floor(t))))
                    let frac = t - floor(t)
                    let base = column[index].center
                    let point = CGPoint(x: base.x + (k % 2 == 0 ? 0.2 : -0.2) * page.em, y: base.y + (frac - 0.5) * page.em)
                    tries += 1
                    guard let result = VerticalOCR.read(page.image, at: point),
                          let pick = WordAim.pick(in: result.line.text, at: result.position, matchLength: {
                              scanner.longestMatch(String($0), in: Self.dictionary)
                          }) else {
                        wrong.append("∅")
                        continue
                    }
                    if pick.word == target.word { ok += 1 } else { wrong.append(pick.word) }
                }
                right += ok; total += tries
                lines.append("  \(target.word): \(ok)/\(tries)" + (wrong.isEmpty ? "" : "  wrong: \(wrong.joined(separator: " "))"))
            }
            say("BENCH aim \(style.name): \(right)/\(total) on the right word")
            lines.forEach { say($0) }
        }
    }

    /// A sentence that runs from one column into the next: the reader finds
    /// the columns on both sides, so the Anki sentence can be whole.
    func testNeighbouringColumns() throws {
        for style in [Self.styles[0], Self.styles[1]] {
            let page = PageRenderer.render(Self.columns, ruby: Self.ruby, style: style)
            // Column 1 ("窓際の席で…僕に") ends mid-sentence, which goes on in column 2.
            let middle = try XCTUnwrap(VerticalOCR.read(page.image, at: page.columns[1][4].center), style.name)
            let next = VerticalOCR.neighbours(page.image, of: middle)
            let before = try XCTUnwrap(next.before, "\(style.name): the column to the right")
            let after = try XCTUnwrap(next.after, "\(style.name): the column to the left")
            say("BENCH neighbours \(style.name): \(String(before.line.text)) | \(String(middle.line.text)) | \(String(after.line.text))")
            XCTAssertGreaterThan(Double(before.frame.midX), Double(middle.frame.maxX), style.name)
            XCTAssertLessThan(Double(after.frame.midX), Double(middle.frame.minX), style.name)
            // The next column on the left is column 2, which starts with 気づく (read exactly on the clean page).
            if style.name == "clean" {
                XCTAssertTrue(String(after.line.text).hasPrefix("気"), String(after.line.text))
            }
        }
    }

    /// The back cover of a light novel, photographed in the lens (from the user's screenshot).
    func testRealPhoto() throws {
        guard let url = Bundle.module.url(forResource: "back-cover", withExtension: "png", subdirectory: "Fixtures"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return XCTFail("fixture missing") }
        let truth = [
            "十七歳の宝は、転校先で二つの人格を持つ",
            "少女と出会う。社交的な碧と内向的な碧。",
            "彼女たちは天気によって人格が入れ替わっ",
            "ていた。宝は雨の日にだけ現れるあおいと",
            "惹かれ合う。しかしある日、「ごめんなさい",
            "1645」という謎のメッセージを残し、",
            "あおいの人格が消えてしまう。宝とみどり",
            "はあおいを取り戻す旅に出るが、その先に",
        ]
        // Column centres and text top/bottom, measured on the 720×930 picture.
        let centres: [CGFloat] = [610, 538, 466, 394, 321, 250, 175, 104]
        let top: CGFloat = 25, bottom: CGFloat = 900
        for (label, maxSide) in [("full", 2400), ("frame", 560)] {
            guard let gray = GrayImage(cgImage: cg, maxSide: maxSide) else { return XCTFail() }
            let scale = CGFloat(gray.width) / CGFloat(cg.width)
            var errors = 0, length = 0, found = 0, reads = 0
            var report: [String] = []
            for (c, x) in centres.enumerated() {
                for f in [0.2, 0.5, 0.8] {
                    reads += 1
                    let point = CGPoint(x: x * scale, y: (top + (bottom - top) * f) * scale)
                    guard let result = VerticalOCR.read(gray, at: point) else {
                        errors += truth[c].count; length += truth[c].count
                        report.append("  c\(c) @\(f): nothing")
                        continue
                    }
                    found += 1
                    let read = String(result.line.text)
                    let distance = Self.editDistance(Self.normalize(read), Self.normalize(truth[c]))
                    errors += distance; length += truth[c].count
                    if f == 0.5 || distance > 1 { report.append("  c\(c) @\(f) em \(Int(result.em)) err \(distance): \(read)") }
                }
            }
            say(String(format: "BENCH real %@ (%dpx wide): found %d/%d, CER %.1f%%", label, gray.width, found, reads, 100 * Double(errors) / Double(max(1, length))))
            report.forEach { say($0) }
            if label == "full", let col = VerticalOCR.findColumn(gray, at: CGPoint(x: 466 * scale, y: 450 * scale)),
               let tile = VerticalOCR.makeTile(gray, column: col) {
                BenchOutput.save(tile.image, "tile-real")
            }
        }
    }

    // MARK: Helpers

    static func normalize(_ s: String) -> [Character] {
        let folded = s.precomposedStringWithCompatibilityMapping
        return folded.compactMap { c -> Character? in
            if c.isWhitespace { return nil }
            if "—―‐-|｜丨ー".contains(c) { return "ー" }
            return c
        }
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
#endif
