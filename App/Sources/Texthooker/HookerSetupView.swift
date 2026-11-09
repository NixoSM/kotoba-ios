import SwiftUI
import KotobaCore

/// Where the PC is, what to do when it can't be reached, and how lines are cleaned.
struct HookerSetupView: View {
    @Environment(HookerModel.self) private var hooker
    @Environment(\.dismiss) private var dismiss
    @State private var notFound = false
    @State private var phoneAddress = LocalAddress.wifiIPv4()

    var body: some View {
        @Bindable var hooker = hooker
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Indirizzo del PC, es. 192.168.1.20"), text: $hooker.settings.address)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospacedDigit())
                    Button {
                        Task {
                            notFound = false
                            notFound = !(await hooker.findPC())
                        }
                    } label: {
                        HStack {
                            Label(tr("Trova il PC sulla Wi-Fi"), systemImage: "dot.radiowaves.left.and.right")
                            if hooker.searching {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(hooker.searching)
                    Toggle(tr("Ricevi dal PC"), isOn: $hooker.settings.enabled)
                        .disabled(hooker.address == nil)
                    if hooker.settings.enabled {
                        statusRow
                    }
                } header: {
                    Text(tr("Computer"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if notFound {
                            Text(tr("Non ho trovato Textractor sulla Wi-Fi. Fai avanzare una riga nel gioco (l'estensione si accende con la prima riga) e riprova, oppure scrivi l'indirizzo a mano."))
                                .foregroundStyle(Palette.shu)
                        }
                        Text(tr("Sul PC serve Textractor con l'estensione di Kotoba (o textractor_websocket), porta 6677. Quella di Kotoba tiene le righe arrivate mentre il telefono dorme. Telefono e PC devono essere sulla stessa rete di casa. La guida passo passo è qui sotto."))
                    }
                }

                Section {
                    Toggle(tr("Ricevi anche dal PC verso il telefono"), isOn: $hooker.settings.inbox)
                    if hooker.settings.inbox {
                        LabeledContent(tr("Indirizzo del telefono")) {
                            Text(phoneAddress.map { "http://\($0):\(HookInbox.port)" } ?? tr("Non sei su una Wi-Fi"))
                                .font(.callout.monospacedDigit())
                                .textSelection(.enabled)
                        }
                        if case .failed(let reason) = hooker.inboxState {
                            Text(tr("Non riesco ad ascoltare: {0}", reason))
                                .font(.footnote)
                                .foregroundStyle(Palette.shu)
                        }
                    }
                } header: {
                    Text(tr("Se il collegamento non funziona"))
                } footer: {
                    Text(tr("Il contrario: è il PC a mandare le righe al telefono, quindi il firewall di Windows non si mette in mezzo. Sul PC avvia kotoba-relay.bat (copia ogni riga che Textractor mette negli appunti), oppure apri l'indirizzo qui sopra nel browser e incolla le righe a mano. Funziona solo con Kotoba aperta."))
                }

                Section {
                    Toggle(tr("Unisci le righe di un riquadro"), isOn: $hooker.settings.rules.joinLines)
                    Toggle(tr("Togli le letture tra parentesi: 漢字《かんじ》"), isOn: $hooker.settings.rules.dropBracketReadings)
                    Toggle(isOn: $hooker.settings.rules.dropInlineFurigana) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Togli il furigana attaccato: 天気てんき → 天気"))
                            Text(tr("Sperimentale: usa i tuoi dizionari per riconoscere le letture."))
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Toggle(tr("Caratteri doppi: ここんんにに → こんに"), isOn: $hooker.settings.rules.collapseRepeatedCharacters)
                    Toggle(tr("Riga ripetuta due volte"), isOn: $hooker.settings.rules.collapseRepeatedLine)
                    Toggle(tr("Ignora una riga uguale alla precedente"), isOn: $hooker.settings.skipDuplicates)
                    NavigationLink {
                        ReplacementsView(replacements: $hooker.settings.rules.replacements)
                    } label: {
                        LabeledContent(tr("Regole personalizzate"), value: "\(hooker.settings.rules.replacements.filter(\.enabled).count)")
                    }
                } header: {
                    Text(tr("Pulizia automatica"))
                } footer: {
                    Text(tr("Vale per le righe nuove. Per correggere una riga già arrivata tienila premuta › Modifica."))
                }

                Section {
                    Toggle(tr("Schermo sempre acceso in questa scheda"), isOn: $hooker.settings.keepAwake)
                }

                Section(tr("Preparare il PC (una volta sola)")) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.mincho(17, bold: true))
                                .foregroundStyle(Palette.shu)
                                .frame(width: 18)
                            Text(step)
                                .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle(tr("Testo dal PC"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Fatto")) { dismiss() }
                }
            }
            .onAppear { phoneAddress = LocalAddress.wifiIPv4() }
        }
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hooker.socketState == .connected ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(hooker.socketState == .connected ? Palette.shu : Palette.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.explain(hooker.socketState))
                    .font(.callout)
                if hooker.socketState != .connected {
                    Button(tr("Riprova ora")) { hooker.reconnect() }
                        .font(.callout.weight(.medium))
                }
            }
        }
        .padding(.vertical, 2)
    }

    static func explain(_ state: HookSocket.State) -> String {
        switch state {
        case .off: return tr("Scrivi l'indirizzo del PC.")
        case .connecting: return tr("Mi collego…")
        case .connected: return tr("Collegato: le righe nuove arrivano da sole.")
        case .retrying(let problem):
            switch problem {
            case .refused:
                return tr("Il PC risponde, ma Textractor non trasmette ancora. Apri il gioco con Textractor e fai avanzare una riga: l'estensione si accende con la prima riga. Riprovo da solo.")
            case .unreachable:
                return tr("Il PC non risponde. Controlla l'indirizzo, che telefono e PC siano sulla stessa Wi-Fi e che il firewall di Windows lasci passare Textractor (vedi la guida). Riprovo da solo.")
            case .permission:
                return tr("iOS non lascia Kotoba usare la rete locale: Impostazioni › Privacy e sicurezza › Rete locale › Kotoba.")
            case .closed:
                return tr("Il PC ha chiuso il collegamento (Textractor chiuso?). Riprovo da solo.")
            case .other(let reason):
                return tr("Non riesco a collegarmi: {0}. Riprovo da solo.", reason)
            }
        }
    }

    static var steps: [String] { [
        tr("Scarica Textractor da github.com/Artikash/Textractor (Releases › Textractor-5.2.0-Zip-Version-English-Only.zip) ed estrailo: dentro ci sono le cartelle x86 e x64."),
        tr("Scarica l'estensione di Kotoba: su GitHub › Actions › l'ultima Build verde › Kotoba-Textractor. Metti kotoba_websocket_x86.dll nella cartella x86 di Textractor e kotoba_websocket_x64.dll in x64."),
        tr("Apri Textractor › Extensions › tasto destro › Add extension › scegli «*.dll» in basso › seleziona la .dll. Fallo sia in x86 sia in x64."),
        tr("Avvia il gioco, agganciati con Textractor e scegli la riga giusta nel menu in alto. Alla prima riga Windows chiede il permesso del firewall: spunta «Reti private» e consenti."),
        tr("Qui tocca «Trova il PC sulla Wi-Fi» (o scrivi l'indirizzo IPv4 che vedi con il comando ipconfig) e accendi «Ricevi dal PC»."),
    ] }
}

/// Your own find → replace rules (regular expressions), e.g. to drop a speaker's name.
private struct ReplacementsView: View {
    @Binding var replacements: [HookText.Replacement]

    var body: some View {
        Form {
            ForEach($replacements) { $rule in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(tr("Cerca (espressione regolare)"), text: $rule.find)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                    }
                    TextField(tr("Sostituisci con (vuoto: cancella)"), text: $rule.replace)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !rule.find.isEmpty, (try? NSRegularExpression(pattern: rule.find)) == nil {
                        Text(tr("Espressione non valida: questa regola viene saltata."))
                            .font(.caption)
                            .foregroundStyle(Palette.shu)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { replacements.remove(atOffsets: $0) }

            Section {
                Button(tr("Aggiungi una regola"), systemImage: "plus") {
                    replacements.append(HookText.Replacement(find: ""))
                }
                Button(tr("Esempio: togli il nome di chi parla 【…】"), systemImage: "text.badge.minus") {
                    replacements.append(HookText.Replacement(find: "^【[^】]*】"))
                }
            } footer: {
                Text(tr("Le regole si applicano in ordine, dopo la pulizia automatica."))
            }
        }
        .navigationTitle(tr("Regole personalizzate"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
