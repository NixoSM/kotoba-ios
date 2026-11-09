# Testo dal PC: leggere una visual novel con Kotoba

Giochi sul PC, il testo di ogni riquadro appare sull'iPhone nella scheda **Dal PC**,
e tocchi una parola per cercarla (con mining su Anki, la frase è la riga del gioco).

Come funziona: **Textractor** sul PC aggancia il testo del gioco. L'estensione
**textractor_websocket** lo trasmette sulla rete di casa (porta 6677), come fa per
siti come kizuna-texthooker-ui. Kotoba si collega a quella porta.

## Preparare il PC (una volta sola)

1. **Textractor.** Scarica `Textractor-5.2.0-Zip-Version-English-Only.zip` da
   <https://github.com/Artikash/Textractor/releases> ed estrailo dove vuoi
   (per esempio in `Documenti`). Dentro ci sono due cartelle, `x86` e `x64`:
   si usa `x86` per i giochi a 32 bit (quasi tutte le VN) e `x64` per quelli a 64 bit.
2. **L'estensione.** Scarica
   [textractor_websocket_x86.zip](https://github.com/kuroahna/textractor_websocket/releases/latest/download/textractor_websocket_x86.zip) e
   [textractor_websocket_x64.zip](https://github.com/kuroahna/textractor_websocket/releases/latest/download/textractor_websocket_x64.zip).
   Estrai `textractor_websocket_x86.dll` nella cartella `Textractor\x86` e
   `textractor_websocket_x64.dll` in `Textractor\x64`.
3. **Attivala.** Apri `Textractor\x86\Textractor.exe` › pulsante **Extensions** ›
   tasto destro dentro la finestra › **Add extension** › in basso a destra cambia
   il tipo di file da `*.xdll` a `*.dll` › scegli `textractor_websocket_x86.dll`.
   Ripeti con `Textractor\x64\Textractor.exe` e la dll x64.

## Ogni volta che giochi

1. Avvia il gioco, poi Textractor (x86 o x64), **Attach to game** e scegli il gioco.
2. Fai avanzare il testo e, nel menu a tendina in alto, scegli la riga
   (il "thread") che mostra il testo giusto. Solo quella viene mandata all'iPhone.
3. **La prima volta** Windows chiede se Textractor può usare la rete: spunta
   **Reti private** e premi **Consenti accesso**. (Se l'hai chiuso senza
   consentire, vedi "Se non si collega".)
4. Sull'iPhone apri Kotoba › **Dal PC** › tocca la pillola in alto ›
   **Trova il PC sulla Wi-Fi**. Kotoba prova tutti gli indirizzi della rete e
   trova il PC da sé. La prima volta iOS chiede il permesso per la **rete locale**: consenti.
   In alternativa scrivi l'indirizzo: sul PC apri il **Prompt dei comandi**,
   scrivi `ipconfig` e copia l'**Indirizzo IPv4** (es. `192.168.1.20`).
5. Accendi **Ricevi dal PC**. La pillola diventa **In diretta dal PC**.

Nota: l'estensione accende il suo server solo dopo la **prima riga** agganciata.
Prima di allora Kotoba scrive "Aspetto Textractor…" e riprova da sola.

## Usare la scheda Dal PC

- **Tocca un carattere**: cerca la parola che lo contiene. Tocca di nuovo dentro
  la stessa parola per cercare a partire da quel carattere preciso.
- I risultati si aprono a metà schermo: puoi continuare a toccare altre parole.
  Il pulsante Anki usa la frase della riga come frase d'esempio.
- **Tieni premuta una riga**: Modifica (per togliere furigana o nomi rimasti
  attaccati), Copia, Cerca la riga intera, Ripristina l'originale, Elimina.
- Le righe restano salvate anche se chiudi l'app (le ultime 1000).
- Con lo schermo acceso nella scheda, l'iPhone non si spegne mentre giochi
  (si può disattivare).
- Kotoba deve essere **aperta**: iOS ferma la rete delle app in sottofondo. Quando
  torni su Kotoba si ricollega da sola; le righe arrivate nel frattempo non ci sono.

### Pulizia automatica (Collegamento e pulizia)

- **Unisci le righe di un riquadro**: toglie gli a capo.
- **Letture tra parentesi**: `漢字《かんじ》`, `｜漢字《かんじ》`, `漢字(かんじ)` → `漢字`.
- **Furigana attaccato** (sperimentale): `今日きょうは天気てんき` → `今日は天気`.
  Usa i tuoi dizionari: toglie le kana dopo i kanji solo se sono la loro lettura
  e kanji + kana non formano già una parola (日にち resta).
- **Caratteri doppi**: `ここんんににちちはは` → `こんにちは`.
- **Riga ripetuta**: la stessa frase agganciata due volte di fila.
- **Regole personalizzate**: cerca/sostituisci con espressioni regolari.
  Esempio già pronto: togliere il nome di chi parla, `【美咲】` all'inizio.

Textractor ha anche estensioni sue per questo (Remove Repeated Characters,
Regex Filter…): funzionano anche loro, perché agiscono prima di mandare il testo.

## Se non si collega

| Kotoba dice | Cosa fare |
|---|---|
| Aspetto Textractor… | Il PC risponde ma il server non c'è ancora: controlla che l'estensione sia nella lista Extensions e fai avanzare una riga nel gioco. |
| Il PC non risponde | Indirizzo sbagliato, Wi-Fi diverse (il PC via cavo va bene, purché sia lo stesso router), o il firewall di Windows. |
| iOS non lascia Kotoba usare la rete locale | iPhone: Impostazioni › Privacy e sicurezza › Rete locale › Kotoba: accendi. |

**Firewall di Windows.** Start › scrivi "Consenti app tramite Windows Firewall" ›
**Modifica impostazioni** › cerca **Textractor** (può comparire due volte, x86 e x64)
e spunta **Privata**. Se la rete di casa è impostata come **Pubblica**
(Impostazioni › Rete e Internet › proprietà della Wi-Fi/Ethernet), mettila su **Privata**.

**Reti ospiti** e alcuni router con "isolamento AP" impediscono ai dispositivi
di vedersi: usa la Wi-Fi principale.

### Il piano B: il PC manda al telefono

Se il collegamento proprio non va, si può fare al contrario. Il firewall di Windows
non blocca quello che il PC *manda*.

1. In Kotoba › Collegamento e pulizia, accendi **Ricevi anche dal PC verso il telefono**.
   Compare l'indirizzo del telefono, es. `http://192.168.1.34:6678`.
2. In Textractor › Extensions controlla che ci sia **Copy to Clipboard**
   (c'è di serie; se manca: Add extension › `Copy to Clipboard.xdll`).
3. Sul PC fai doppio clic su `tools\texthooker\kotoba-relay.bat` e scrivi l'indirizzo
   del telefono (solo i numeri, es. `192.168.1.34`). Ogni riga copiata arriva sull'iPhone.

Oppure, senza script: apri l'indirizzo del telefono nel browser del PC e incolla le
righe a mano (utile per provare che telefono e PC si vedono).

## Per chi sviluppa

- Protocollo: WebSocket in chiaro, un messaggio di testo per riga. Se il messaggio
  è JSON con un campo `sentence` (TextractorSender, alcune configurazioni di
  LunaTranslator) si usa quello, come fa texthooker-ui. Quindi va bene qualsiasi
  programma compatibile con texthooker-ui/kizuna, anche su un'altra porta
  (`192.168.1.20:9001`).
- textractor_websocket ascolta su `0.0.0.0:6677` e manda solo il thread scelto in Textractor.
- Il piano B è un piccolo server HTTP sull'iPhone (porta 6678): `POST /text` con il
  testo in UTF-8; `GET /` dà la pagina per incollare.
- Codice: `App/Sources/Texthooker/`, pulizia del testo in
  `Packages/KotobaCore/Sources/KotobaCore/HookText.swift` (con test).
