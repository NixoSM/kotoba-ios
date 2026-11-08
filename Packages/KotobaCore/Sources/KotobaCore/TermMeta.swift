import Foundation

/// A frequency value from one frequency dictionary.
public struct FrequencyInfo: Hashable, Sendable {
    public var dictionary: String
    /// Set when the dictionary gives a frequency for one specific reading.
    public var reading: String?
    public var value: Double
    public var display: String
}

/// Pitch accent of one reading: each position is the mora after which the
/// pitch drops (0 = heiban, no drop).
public struct PitchInfo: Hashable, Sendable {
    public var dictionary: String
    public var reading: String
    public var positions: [Int]
}

public enum TermMetaParser {
    public static func frequency(_ json: Any, dictionary: String) -> FrequencyInfo? {
        if let o = json as? [String: Any], let inner = o["frequency"] {
            guard var info = frequency(inner, dictionary: dictionary) else { return nil }
            info.reading = o["reading"] as? String
            return info
        }
        guard let value = ReverseSearch.frequencyValue(json) else { return nil }
        var display = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
        if let o = json as? [String: Any], let d = o["displayValue"] as? String { display = d }
        if let s = json as? String { display = s }
        return FrequencyInfo(dictionary: dictionary, reading: nil, value: value, display: display)
    }

    public static func pitch(_ json: Any, dictionary: String) -> PitchInfo? {
        guard let o = json as? [String: Any], let reading = o["reading"] as? String,
              let pitches = o["pitches"] as? [[String: Any]] else { return nil }
        let positions = pitches.compactMap { p -> Int? in
            if let n = p["position"] as? NSNumber { return n.intValue }
            // Some dictionaries give an explicit H/L pattern instead: find the drop.
            if let pattern = p["position"] as? String, pattern.allSatisfy({ $0 == "H" || $0 == "L" }) {
                let chars = Array(pattern)
                if chars.first == "H" { return 1 }
                for i in 1..<chars.count where chars[i] == "L" && chars[i - 1] == "H" { return i }
                return 0
            }
            return nil
        }
        guard !positions.isEmpty else { return nil }
        return PitchInfo(dictionary: dictionary, reading: reading, positions: positions)
    }
}

/// Splits kana into morae: small ゃゅょ etc. belong to the previous kana.
public enum Mora {
    private static let small: Set<Character> = ["ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ",
                                                "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ", "ヮ"]

    public static func split(_ kana: String) -> [String] {
        var out: [String] = []
        for c in kana {
            if small.contains(c), !out.isEmpty { out[out.count - 1].append(c) } else { out.append(String(c)) }
        }
        return out
    }

    /// High (true) or low (false) for each mora, plus the particle after the word.
    public static func pattern(morae count: Int, downstep: Int) -> [Bool] {
        (0...count).map { i in
            // i is the 0-based mora index; index == count is the following particle.
            switch downstep {
            case 0: return i != 0
            case 1: return i == 0
            default: return i != 0 && i < downstep
            }
        }
    }
}
