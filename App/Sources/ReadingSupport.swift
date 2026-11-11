import SwiftUI
import KotobaCore
import KotobaOCR

/// Bridges `WordAim` to the dictionary. The lens asks about the same few
/// characters several times a second, so answers are cached.
final class WordFinder: @unchecked Sendable {
    static let shared = WordFinder()

    private let lock = NSLock()
    private var store: TermSource?
    private var cache: [String: Int] = [:]
    private let scanner = TextScanner(maxLength: 12)

    /// Uses this dictionary from now on (and forgets old answers: dictionaries may have changed).
    func attach(_ store: TermSource?) {
        lock.withLock {
            self.store = store
            cache.removeAll(keepingCapacity: true)
        }
    }

    /// Characters the longest dictionary word at the start of `chars` covers (0: none).
    func matchLength(_ chars: ArraySlice<Character>) -> Int {
        let key = String(chars.prefix(12))
        guard !key.isEmpty else { return 0 }
        if let known = lock.withLock({ cache[key] }) { return known }
        guard let store = lock.withLock({ store }) else { return 0 }
        let length = scanner.longestMatch(key, in: store)
        lock.withLock {
            if cache.count > 5000 { cache.removeAll(keepingCapacity: true) }
            cache[key] = length
        }
        return length
    }

    /// How much of a line reads as Japanese words: the share of its kana and kanji
    /// that a left-to-right pass of dictionary words covers. Real lines score high;
    /// "lines" made of characters from different columns score low.
    func coverage(_ text: [Character]) -> (score: Double, japanese: Int) {
        var japanese = 0, covered = 0.0, i = 0
        for c in text where Self.isJapanese(c) { japanese += 1 }
        guard japanese > 0 else { return (0, 0) }
        while i < text.count {
            guard Self.isJapanese(text[i]) else {
                i += 1
                continue
            }
            let length = matchLength(text[i...])
            if length >= 2 {
                covered += Double(text[i..<min(text.count, i + length)].filter(Self.isJapanese).count)
                i += length
            } else {
                // A lone kanji is often a word, but random neighbours are too: half a point.
                if length == 1, !Self.isKana(text[i]) { covered += 0.5 }
                i += 1
            }
        }
        return (min(1, covered / Double(japanese)), japanese)
    }

    static func isKana(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3041...0x30FF).contains(v)
    }

    static func isJapanese(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3041...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
    }

    /// The word around `position` (characters along the line).
    func pick(in line: OCRLine, at position: Double, favoring: String? = nil) -> WordAim.Pick? {
        WordAim.pick(in: line.text, at: position, favoring: favoring, matchLength: matchLength)
    }

    /// The word starting exactly at `start` (a tap on the strip).
    func pick(in text: [Character], start: Int) -> WordAim.Pick? {
        guard text.indices.contains(start) else { return nil }
        return WordAim.Pick(text: text, start: start, length: matchLength(text[start...]))
    }
}

/// The line the word was found in, as plain text you can tap: the camera's
/// reading laid out horizontally, so a wrong start is fixed with one touch.
struct ContextStrip: View {
    let pick: WordAim.Pick
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(pick.text.enumerated()), id: \.offset) { index, char in
                        let inWord = index >= pick.start && index < pick.start + pick.length
                        Text(String(char))
                            .font(.system(size: 22, weight: inWord ? .semibold : .regular))
                            .foregroundStyle(inWord ? Palette.shu : Palette.ink)
                            .frame(minWidth: 28, minHeight: 44)
                            .background(inWord ? Palette.shu.opacity(0.1) : .clear)
                            .overlay(alignment: .bottom) {
                                if inWord { Rectangle().fill(Palette.shu).frame(height: 2) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(index) }
                            .id(index)
                    }
                }
                .padding(.horizontal, 24) // clear of the faded edges at either end
            }
            .onAppear { proxy.scrollTo(pick.start, anchor: .center) }
            .onChange(of: pick) { _, new in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new.start, anchor: .center) }
            }
        }
        .frame(height: 46)
        // Faded edges: a character cut by the edge reads as "the line goes on, swipe".
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 28)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
            }
        }
        .background(Palette.raised)
    }
}

/// A tap on a photo the reader should act on (from the live camera, before the photo existed).
struct PendingTap: Equatable {
    let id = UUID()
    let point: CGPoint
}
