import Foundation

/// Small kana helpers used by search and scanning.
public enum Kana {
    private static let katakanaRange: ClosedRange<UInt32> = 0x30A1...0x30F6
    private static let hiraganaRange: ClosedRange<UInt32> = 0x3041...0x3096
    private static let offset: UInt32 = 0x60

    /// ア → あ. Leaves everything else (including ー) untouched.
    public static func toHiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { s in
            katakanaRange.contains(s.value) ? Unicode.Scalar(s.value - offset)! : s
        }))
    }

    /// あ → ア.
    public static func toKatakana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { s in
            hiraganaRange.contains(s.value) ? Unicode.Scalar(s.value + offset)! : s
        }))
    }

    /// True if the text contains any Japanese script (kana or CJK ideographs).
    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            switch s.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F:
                return true
            default:
                return false
            }
        }
    }
}
