import KotobaCore

extension Reason {
    var italianLabel: String {
        switch self {
        case .negative: "negativo"
        case .past: "passato"
        case .te: "forma て"
        case .polite: "cortese"
        case .politePast: "cortese passato"
        case .politeNegative: "cortese negativo"
        case .politeNegativePast: "cortese negativo passato"
        case .politeVolitional: "cortese volitivo"
        case .conditional: "condizionale ば"
        case .tara: "condizionale たら"
        case .tari: "elenco たり"
        case .potential: "potenziale"
        case .passive: "passivo"
        case .causative: "causativo"
        case .volitional: "volitivo"
        case .imperative: "imperativo"
        case .want: "desiderativo たい"
        case .stem: "radice"
        case .progressive: "progressivo ている"
        case .completion: "completamento てしまう"
        case .preparation: "preparazione ておく"
        case .adverb: "avverbio"
        case .noun: "sostantivo さ"
        case .seemingness: "apparenza そう"
        case .excess: "eccesso すぎる"
        case .negativeTe: "negativo ないで"
        case .nakereba: "obbligo なきゃ"
        case .zu: "negativo ず"
        }
    }
}
