# Kotoba

Dizionario giapponese per iPhone ispirato a Yomitan: dizionari impilabili,
aspetto personalizzabile, import dei backup Yomitan, ricerca EN/IT→JP,
mining su Anki e fotocamera con OCR.

Stato: **0.4** — dizionari Yomitan, de-coniugazione, romaji, ricerca per significato, frequenze e accento, import delle impostazioni Yomitan, mining su AnkiMobile, fotocamera con Live Text.

## Visual novel sul PC

La scheda **Dal PC** mostra in diretta il testo che Textractor aggancia dal gioco:
tocchi una parola e la cerchi. Come prepararlo: [docs/texthooker.md](docs/texthooker.md).

## Struttura

- `Packages/KotobaCore` — il motore (formato Yomitan, de-coniugazione, scansione del testo). Swift puro, con test.
- `App/` — l'app iOS (SwiftUI).
- `project.yml` — descrizione del progetto Xcode, generato con XcodeGen.
- `.github/workflows/build.yml` — a ogni modifica su `main`, GitHub esegue i test e compila `Kotoba.ipa` (non firmata).

## Installare l'app sul tuo iPhone (Windows + Apple ID gratuito)

Una tantum:

1. Installa **iTunes** e **iCloud** nelle versioni non-Microsoft Store (se hai quelle dello Store, disinstallale prima), poi riavvia:
   - iTunes: https://www.apple.com/itunes/download/win64
   - iCloud: https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe
2. Installa **Sideloadly** da https://sideloadly.io.
3. Consigliato: crea un **Apple ID secondario** da usare solo per questo. Sideloadly è un programma di terzi e gli dai la password dell'Apple ID.

A ogni nuova build:

1. Su GitHub apri la scheda **Actions** del repository, scegli l'ultima esecuzione verde di *Build*, in fondo alla pagina scarica **Kotoba-ipa** ed estrai lo zip: dentro c'è `Kotoba.ipa`.
2. Collega l'iPhone al PC col cavo, sbloccalo e tocca **Autorizza** se chiede di fidarsi del computer.
3. Apri Sideloadly, trascina `Kotoba.ipa` nella finestra, scrivi l'Apple ID e premi **Start**. Potrebbe chiederti il codice di verifica a due fattori.
4. Solo la prima volta, sull'iPhone:
   - Impostazioni → Generali → **VPN e gestione dispositivi** → tocca il tuo Apple ID → **Autorizza**.
   - Impostazioni → Privacy e sicurezza → **Modalità sviluppatore** → attiva e riavvia.

Limiti dell'Apple ID gratuito: l'app smette di aprirsi dopo **7 giorni** e va reinstallata (Sideloadly può farlo da solo via Wi-Fi se il PC è acceso), e puoi avere al massimo 3 app installate così.
