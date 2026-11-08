import SwiftUI
import KotobaCore

/// First build: no dictionaries yet. Type any inflected Japanese and see how
/// the engine takes it apart. Its job is to prove the build reaches the phone.
struct ScanPlaygroundView: View {
    @State private var text = "食べなかった"
    private let deinflector = Deinflector()

    private var candidates: [Deinflection] {
        deinflector.deinflect(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .filter { !$0.reasons.isEmpty && !$0.wordClass.intersection(.partsOfSpeech).isEmpty }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Scrivi una parola coniugata", text: $text)
                        .font(.system(size: 28, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Nessun dizionario è ancora caricato: qui vedi solo le possibili forme base. Quelle vere vengono scelte confrontandole con il dizionario.")
                }
                Section("Possibili forme base") {
                    ForEach(candidates, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.term).font(.title3.weight(.semibold))
                            Text(c.reasons.map(\.italianLabel).joined(separator: " → "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Kotoba 0.1")
        }
    }
}

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
