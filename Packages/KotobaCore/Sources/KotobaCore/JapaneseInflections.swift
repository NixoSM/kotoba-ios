import Foundation

/// Japanese inflection rules, written from the grammar itself (not ported from Yomitan).
public enum JapaneseInflections {
    public static let all: [InflectionRule] = godan + ichidan + suru + kuru + adjective + auxiliaries

    private typealias R = InflectionRule

    /// Godan rows: dictionary ending, a/i/e/o-stem, te-form, ta-form.
    private static let godanRows: [(u: String, a: String, i: String, e: String, o: String, te: String, ta: String)] = [
        ("う", "わ", "い", "え", "お", "って", "った"),
        ("く", "か", "き", "け", "こ", "いて", "いた"),
        ("ぐ", "が", "ぎ", "げ", "ご", "いで", "いだ"),
        ("す", "さ", "し", "せ", "そ", "して", "した"),
        ("つ", "た", "ち", "て", "と", "って", "った"),
        ("ぬ", "な", "に", "ね", "の", "んで", "んだ"),
        ("ぶ", "ば", "び", "べ", "ぼ", "んで", "んだ"),
        ("む", "ま", "み", "め", "も", "んで", "んだ"),
        ("る", "ら", "り", "れ", "ろ", "って", "った"),
    ]

    static let godan: [InflectionRule] = godanRows.flatMap { r -> [InflectionRule] in
        [
            R(r.a + "ない", r.u, from: .adjI, to: .v5, .negative),
            R(r.a + "ず", r.u, from: .surface, to: .v5, .zu),
            R(r.i + "ます", r.u, from: .masu, to: .v5, .polite),
            R(r.ta, r.u, from: .ta, to: .v5, .past),
            R(r.te, r.u, from: .te, to: .v5, .te),
            R(r.e + "ば", r.u, from: .surface, to: .v5, .conditional),
            R(r.e + "る", r.u, from: .v1, to: .v5, .potential),
            R(r.a + "れる", r.u, from: .v1, to: .v5, .passive),
            R(r.a + "せる", r.u, from: .v1, to: .v5, .causative),
            R(r.o + "う", r.u, from: .surface, to: .v5, .volitional),
            R(r.e, r.u, from: .surface, to: .v5, .imperative),
            R(r.i + "たい", r.u, from: .adjI, to: .v5, .want),
            R(r.i, r.u, from: .surface, to: .v5, .stem),
        ]
    } + [
        // 行く is the one godan verb with an irregular te/ta form.
        R("行って", "行く", from: .te, to: .v5, .te),
        R("行った", "行く", from: .ta, to: .v5, .past),
        R("いって", "いく", from: .te, to: .v5, .te),
        R("いった", "いく", from: .ta, to: .v5, .past),
    ]

    static let ichidan: [InflectionRule] = [
        R("ない", "る", from: .adjI, to: .v1, .negative),
        R("ず", "る", from: .surface, to: .v1, .zu),
        R("ます", "る", from: .masu, to: .v1, .polite),
        R("た", "る", from: .ta, to: .v1, .past),
        R("て", "る", from: .te, to: .v1, .te),
        R("れば", "る", from: .surface, to: .v1, .conditional),
        R("られる", "る", from: .v1, to: .v1, .potential),
        R("れる", "る", from: .v1, to: .v1, .potential), // ら抜き: 食べれる
        R("させる", "る", from: .v1, to: .v1, .causative),
        R("よう", "る", from: .surface, to: .v1, .volitional),
        R("ろ", "る", from: .surface, to: .v1, .imperative),
        R("よ", "る", from: .surface, to: .v1, .imperative),
        R("たい", "る", from: .adjI, to: .v1, .want),
    ]

    static let suru: [InflectionRule] = [
        R("しない", "する", from: .adjI, to: .vs, .negative),
        R("せず", "する", from: .surface, to: .vs, .zu),
        R("します", "する", from: .masu, to: .vs, .polite),
        R("した", "する", from: .ta, to: .vs, .past),
        R("して", "する", from: .te, to: .vs, .te),
        R("すれば", "する", from: .surface, to: .vs, .conditional),
        R("できる", "する", from: .v1, to: .vs, .potential),
        R("される", "する", from: .v1, to: .vs, .passive),
        R("させる", "する", from: .v1, to: .vs, .causative),
        R("しよう", "する", from: .surface, to: .vs, .volitional),
        R("しろ", "する", from: .surface, to: .vs, .imperative),
        R("せよ", "する", from: .surface, to: .vs, .imperative),
        R("したい", "する", from: .adjI, to: .vs, .want),
    ]

    static let kuru: [InflectionRule] = ["来", ""].flatMap { k -> [InflectionRule] in
        // With kanji the stem is always 来; in kana it changes vowel (こ/き/く).
        let ko = k.isEmpty ? "こ" : k, ki = k.isEmpty ? "き" : k, ku = k.isEmpty ? "く" : k
        let base = k.isEmpty ? "くる" : "来る"
        return [
            R(ko + "ない", base, from: .adjI, to: .vk, .negative),
            R(ki + "ます", base, from: .masu, to: .vk, .polite),
            R(ki + "た", base, from: .ta, to: .vk, .past),
            R(ki + "て", base, from: .te, to: .vk, .te),
            R(ku + "れば", base, from: .surface, to: .vk, .conditional),
            R(ko + "られる", base, from: .v1, to: .vk, .potential),
            R(ko + "させる", base, from: .v1, to: .vk, .causative),
            R(ko + "よう", base, from: .surface, to: .vk, .volitional),
            R(ko + "い", base, from: .surface, to: .vk, .imperative),
            R(ki + "たい", base, from: .adjI, to: .vk, .want),
        ]
    }

    static let adjective: [InflectionRule] = [
        R("くない", "い", from: .adjI, to: .adjI, .negative),
        R("かった", "い", from: .ta, to: .adjI, .past),
        R("くて", "い", from: .te, to: .adjI, .te),
        R("ければ", "い", from: .surface, to: .adjI, .conditional),
        R("く", "い", from: .surface, to: .adjI, .adverb),
        R("さ", "い", from: .surface, to: .adjI, .noun),
        R("そう", "い", from: .surface, to: .adjI, .seemingness),
        R("すぎる", "い", from: .v1, to: .adjI, .excess),
    ]

    static let auxiliaries: [InflectionRule] = [
        // Polite forms all lead back to ます.
        R("ました", "ます", from: .ta, to: .masu, .politePast),
        R("まして", "ます", from: .te, to: .masu, .te),
        R("ません", "ます", from: .surface, to: .masu, .politeNegative),
        R("ませんでした", "ます", from: .surface, to: .masu, .politeNegativePast),
        R("ましょう", "ます", from: .surface, to: .masu, .politeVolitional),
        // Built on the ta-form.
        R("たら", "た", from: .surface, to: .ta, .tara),
        R("だら", "だ", from: .surface, to: .ta, .tara),
        R("たり", "た", from: .surface, to: .ta, .tari),
        R("だり", "だ", from: .surface, to: .ta, .tari),
        // Built on the te-form.
        R("ている", "て", from: .v1, to: .te, .progressive),
        R("でいる", "で", from: .v1, to: .te, .progressive),
        R("てる", "て", from: .v1, to: .te, .progressive),
        R("でる", "で", from: .v1, to: .te, .progressive),
        R("てしまう", "て", from: .v5, to: .te, .completion),
        R("でしまう", "で", from: .v5, to: .te, .completion),
        R("ちゃう", "て", from: .v5, to: .te, .completion),
        R("じゃう", "で", from: .v5, to: .te, .completion),
        R("ておく", "て", from: .v5, to: .te, .preparation),
        R("でおく", "で", from: .v5, to: .te, .preparation),
        R("とく", "て", from: .v5, to: .te, .preparation),
        R("どく", "で", from: .v5, to: .te, .preparation),
        // Built on ない.
        R("ないで", "ない", from: .surface, to: .adjI, .negativeTe),
        R("なきゃ", "ない", from: .surface, to: .adjI, .nakereba),
    ]
}
