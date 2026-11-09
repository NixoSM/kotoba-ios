import KotobaCore

extension Reason {
    var italianLabel: String {
        switch self {
        case .negative: tr("negativo")
        case .past: tr("passato")
        case .te: tr("forma て")
        case .polite: tr("cortese")
        case .politePast: tr("cortese passato")
        case .politeNegative: tr("cortese negativo")
        case .politeNegativePast: tr("cortese negativo passato")
        case .politeVolitional: tr("cortese volitivo")
        case .conditional: tr("condizionale ば")
        case .tara: tr("condizionale たら")
        case .tari: tr("elenco たり")
        case .potential: tr("potenziale")
        case .passive: tr("passivo")
        case .causative: tr("causativo")
        case .volitional: tr("volitivo")
        case .imperative: tr("imperativo")
        case .want: tr("desiderativo たい")
        case .stem: tr("radice")
        case .progressive: tr("progressivo ている")
        case .completion: tr("completamento てしまう")
        case .preparation: tr("preparazione ておく")
        case .adverb: tr("avverbio")
        case .noun: tr("sostantivo さ")
        case .seemingness: tr("apparenza そう")
        case .excess: tr("eccesso すぎる")
        case .negativeTe: tr("negativo ないで")
        case .nakereba: tr("obbligo なきゃ")
        case .zu: tr("negativo ず")
        }
    }
}
