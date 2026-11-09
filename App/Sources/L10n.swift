import Foundation

/// The language of the app's own words (dictionary content is never translated).
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, it, en, ja
    var id: Self { self }

    /// Each language names itself, so you can always find your way back.
    var label: String {
        switch self {
        case .system: tr("Come il sistema")
        case .it: "Italiano"
        case .en: "English"
        case .ja: "日本語"
        }
    }
}

/// Translates the app's Italian strings. Italian is the source text and the
/// key; English and Japanese live in `table`. Placeholders are {0}, {1}…
func tr(_ italian: String, _ args: Any...) -> String {
    var text = italian
    switch L10n.current {
    case .en: text = L10n.table[italian]?.en ?? italian
    case .ja: text = L10n.table[italian]?.ja ?? italian
    default: break
    }
    for (i, arg) in args.enumerated() {
        text = text.replacingOccurrences(of: "{\(i)}", with: "\(arg)")
    }
    return text
}

enum L10n {
    /// The language in use: never `.system`, which is resolved by `apply`.
    nonisolated(unsafe) private(set) static var current: AppLanguage = .it

    static func apply(_ setting: AppLanguage) {
        if setting != .system {
            current = setting
        } else {
            let preferred = Locale.preferredLanguages.lazy
                .compactMap { AppLanguage(rawValue: String($0.prefix(2))) }.first
            // Anyone whose phone speaks none of the three gets English.
            current = preferred ?? .en
        }
        // System parts (Cancel, Edit, the file picker) follow at the next launch.
        if setting == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([setting.rawValue], forKey: "AppleLanguages")
        }
    }

    /// `lang` attribute for the results page.
    static var htmlLang: String { current.rawValue }

    static let table: [String: (en: String, ja: String)] = [
        // Tabs
        "Cerca": ("Search", "検索"),
        "Fotocamera": ("Camera", "カメラ"),
        "Dizionari": ("Dictionaries", "辞書"),
        "Impostazioni": ("Settings", "設定"),

        // Search
        "日本語 · italiano · English · romaji": ("日本語 · English · italiano · romaji", "日本語・英語・イタリア語・ローマ字"),
        "{0} dizionari · {1} voci": ("{0} dictionaries · {1} entries", "辞書 {0} 冊 · {1} 項目"),
        "Prova a cercare": ("Try searching", "検索してみよう"),
        "Recenti": ("Recent", "最近の検索"),
        "Cancella": ("Clear", "消去"),
        "Rimuovi": ("Remove", "削除"),
        "forme coniugate": ("conjugated forms", "活用形"),
        "dall'italiano": ("from Italian", "イタリア語から"),
        "dall'inglese": ("from English", "英語から"),
        "Nessun risultato per «{0}»": ("No results for “{0}”", "「{0}」は見つかりませんでした"),
        "Controlla di aver attivato i dizionari giusti, o prova la forma base della parola.":
            ("Check that the right dictionaries are on, or try the dictionary form of the word.",
             "辞書が有効になっているか確認するか、辞書形で検索してみてください。"),
        "Nessun dizionario": ("No dictionaries", "辞書がありません"),
        "Importa un dizionario Yomitan (.zip) dalla scheda Dizionari.":
            ("Import a Yomitan dictionary (.zip) from the Dictionaries tab.",
             "「辞書」タブからYomitan形式の辞書（.zip）を読み込んでください。"),

        // Results
        "Letto come {0}": ("Read as {0}", "{0} として"),
        "Parole che significano «{0}»": ("Words meaning “{0}”", "「{0}」を意味する語"),
        "{0} parole · {1} ms": ("{0} words · {1} ms", "{0} 語 · {1} ms"),
        "Ascolta": ("Listen", "再生"),
        "Già in Anki": ("Already in Anki", "Anki に追加済み"),
        "Aggiungi ad Anki": ("Add to Anki", "Anki に追加"),
        "Frequenza": ("Frequency", "頻度"),
        "Nessuna registrazione per {0}": ("No recording for {0}", "{0} の音声はありません"),
        "Audio non disponibile (sei online?)": ("Audio unavailable (are you online?)", "音声を再生できません（オフラインかもしれません）"),

        // Camera
        "Leggi dal mondo reale": ("Read the real world", "身の回りの文字を読む"),
        "Scatta una foto o scegline una. Poi tieni premuto sul testo giapponese, anche verticale, e trascina per selezionare la parola: la definizione appare qui sotto.":
            ("Take or pick a photo. Then press and hold on the Japanese text, vertical too, and drag to select a word: its definition appears below.",
             "写真を撮るか選んでください。日本語の文字（縦書きも可）を長押しして単語を選択すると、下に意味が表示されます。"),
        "Scatta foto": ("Take photo", "撮影"),
        "Dalla libreria": ("From library", "ライブラリから"),

        // Dictionaries
        "{0} voci · {1} frequenze/accenti · rev. {2}": ("{0} entries · {1} frequencies/accents · rev. {2}", "{0} 項目 · 頻度/アクセント {1} · rev. {2}"),
        "Chiuso nei risultati": ("Collapsed in results", "検索結果で折りたたみ"),
        "Apri": ("Expand", "展開"),
        "Chiudi": ("Collapse", "折りたたむ"),
        "Elimina": ("Delete", "削除"),
        "Ordine dei risultati": ("Result order", "表示順"),
        "Trascina per cambiare l'ordine in cui i dizionari compaiono nei risultati. Scorri verso destra per mostrare un dizionario chiuso nei risultati (si apre toccandone il nome), verso sinistra per eliminarlo.":
            ("Drag to change the order dictionaries appear in results. Swipe right to show a dictionary collapsed (tap its name to open it), left to delete it.",
             "ドラッグで検索結果に表示される辞書の順番を変更できます。右にスワイプすると折りたたみ表示（名前をタップで展開）、左にスワイプすると削除します。"),
        "Importa": ("Import", "読み込む"),
        "Importo {0}…": ("Importing {0}…", "{0} を読み込み中…"),
        "Puoi lasciare l'app aperta: i dizionari grandi richiedono qualche minuto.":
            ("Keep the app open: large dictionaries take a few minutes.",
             "アプリを開いたままにしてください。大きな辞書は数分かかります。"),
        "{0}: {1} voci importate": ("{0}: {1} entries imported", "{0}：{1} 項目を読み込みました"),

        // Settings
        "Aspetto": ("Appearance", "表示"),
        "Lingua": ("Language", "言語"),
        "Lingua dell'app": ("App language", "アプリの言語"),
        "Come il sistema": ("Same as system", "システムと同じ"),
        "Menu e pulsanti di sistema (Annulla, Modifica, la scelta dei file) cambiano lingua alla prossima apertura dell'app.":
            ("System menus and buttons (Cancel, Edit, the file picker) switch language the next time you open the app.",
             "システムのメニューやボタン（キャンセル、編集、ファイル選択）は次回の起動時に切り替わります。"),
        "Importa impostazioni di Yomitan": ("Import Yomitan settings", "Yomitan の設定を読み込む"),
        "Il file yomitan-settings-….json: applica ordine e attivazione dei dizionari, il dizionario di frequenza, l'aspetto (font, dimensioni, layout) e la nota Anki.":
            ("The yomitan-settings-….json file: applies dictionary order and activation, the frequency dictionary, appearance (font, size, layout) and the Anki note.",
             "yomitan-settings-….json ファイルから、辞書の順番と有効・無効、頻度辞書、表示（フォント、サイズ、レイアウト）、Anki のノートを適用します。"),
        "Ordinamento dei risultati": ("Result sorting", "検索結果の並び順"),
        "Dizionario di frequenza": ("Frequency dictionary", "頻度辞書"),
        "Il primo disponibile": ("First available", "最初に見つかったもの"),
        "Dimentica le parole già minate": ("Forget words already mined", "追加済みの単語をリセット"),
        "AnkiMobile non permette di controllare i duplicati: Kotoba ricorda da solo le {0} parole che hai già inviato.":
            ("AnkiMobile can't check for duplicates, so Kotoba remembers the {0} words you've already sent.",
             "AnkiMobile では重複を確認できないため、Kotoba が送信済みの {0} 語を記憶しています。"),
        "Configura una nota Anki a mano": ("Set up an Anki note manually", "Anki のノートを手動で設定"),
        "Oppure importa le impostazioni di Yomitan qui sopra: la tua nota viene configurata da sola.":
            ("Or import your Yomitan settings above: your note is set up automatically.",
             "または上で Yomitan の設定を読み込むと、ノートが自動で設定されます。"),
        "Mazzo": ("Deck", "デッキ"),
        "Tipo di nota": ("Note type", "ノートタイプ"),
        "Etichette": ("Tags", "タグ"),
        "Nota Anki (AnkiMobile)": ("Anki note (AnkiMobile)", "Anki ノート（AnkiMobile）"),
        "I nomi devono essere identici a quelli in AnkiMobile, maiuscole comprese.":
            ("Names must match AnkiMobile exactly, including capitals.",
             "名前は大文字・小文字も含めて AnkiMobile と完全に一致させてください。"),
        "vuoto": ("empty", "空欄"),
        "Campi": ("Fields", "フィールド"),
        "Segnaposto disponibili:": ("Available markers:", "使用できるマーカー："),
        "Per ora restano vuoti:": ("Left empty for now:", "現在は空欄になるもの："),
        "Audio e immagini non passano tramite il collegamento di AnkiMobile.":
            ("Audio and images can't be sent through the AnkiMobile link.",
             "音声と画像は AnkiMobile へのリンクでは送れません。"),

        // Appearance
        "Tema": ("Theme", "テーマ"),
        "Auto": ("Auto", "自動"),
        "Testo": ("Text", "本文"),
        "Lemma": ("Headword", "見出し語"),
        "Dimensione": ("Size", "サイズ"),
        "Interlinea": ("Line spacing", "行間"),
        "Aggiungi un font (.ttf, .otf)…": ("Add a font (.ttf, .otf)…", "フォントを追加（.ttf, .otf）…"),
        "Caratteri": ("Fonts", "フォント"),
        "Klee One, Shippori Mincho e Zen Maru Gothic sono inclusi nell'app. Puoi aggiungere qualsiasi font giapponese che hai in File.":
            ("Klee One, Shippori Mincho and Zen Maru Gothic come with the app. You can add any Japanese font you have in Files.",
             "Klee One、しっぽり明朝、Zen Maru Gothic を内蔵しています。「ファイル」にある日本語フォントも追加できます。"),
        "Disposizione": ("Layout", "レイアウト"),
        "Layout": ("Layout", "レイアウト"),
        "Nomi dei dizionari": ("Dictionary names", "辞書名"),
        "Categorie grammaticali": ("Part-of-speech tags", "品詞タグ"),
        "Mostra": ("Show", "表示"),
        "Linea sopra la lettura": ("Line over the reading", "読みの上に線"),
        "Grafico a punti": ("Dot graph", "ドットグラフ"),
        "Numero [n]": ("Number [n]", "数字 [n]"),
        "Accento": ("Pitch accent", "アクセント"),
        "CSS personalizzato": ("Custom CSS", "カスタム CSS"),
        "Come il «Custom CSS» di Yomitan. Esempio: .headword { color: var(--shu); }":
            ("Like Yomitan's Custom CSS. Example: .headword { color: var(--shu); }",
             "Yomitan の「カスタム CSS」と同じです。例：.headword { color: var(--shu); }"),
        "Ripristina l'aspetto predefinito": ("Reset appearance", "表示を初期設定に戻す"),
        "Non riesco a copiare il font: {0}": ("Couldn't copy the font: {0}", "フォントをコピーできませんでした：{0}"),
        "Arioso": ("Comfortable", "ゆったり"),
        "Compatto": ("Compact", "コンパクト"),
        "Furigana sopra": ("Furigana above", "ふりがな"),
        "Furigana e lettura": ("Furigana and reading", "ふりがなと読み"),
        "Parola【lettura】": ("Word【reading】", "単語【読み】"),
        "Solo la parola": ("Word only", "単語のみ"),
        "Media": ("Average", "平均"),
        "Ogni elenco": ("Each list", "すべて"),
        "Nascosta": ("Hidden", "非表示"),
        "Sistema": ("System", "システム"),

        // Messages
        "Impossibile aprire il database: {0}": ("Couldn't open the database: {0}", "データベースを開けません：{0}"),
        "Prima configura la nota Anki in Impostazioni (puoi importarla dal backup di Yomitan).":
            ("First set up the Anki note in Settings (you can import it from your Yomitan backup).",
             "先に「設定」で Anki のノートを設定してください（Yomitan のバックアップから読み込めます）。"),
        "Non riesco a creare il collegamento per AnkiMobile.": ("Couldn't build the AnkiMobile link.", "AnkiMobile へのリンクを作成できません。"),
        "AnkiMobile non risulta installato.": ("AnkiMobile doesn't seem to be installed.", "AnkiMobile がインストールされていないようです。"),
        "Aggiunta ad Anki": ("Added to Anki", "Anki に追加しました"),
        "Ordine e attivazione applicati a {0} dizionari.": ("Order and activation applied to {0} dictionaries.", "{0} 冊の辞書に順番と有効・無効を適用しました。"),
        "Non ancora importati: {0}.": ("Not imported yet: {0}.", "未読み込み：{0}。"),
        "Ordinamento per frequenza: {0}.": ("Sorting by frequency: {0}.", "頻度順の基準：{0}。"),
        "Aspetto: carattere {0}, {1} pt, layout {2}.": ("Appearance: font {0}, {1} pt, {2} layout.", "表示：フォント {0}、{1} pt、レイアウト {2}。"),
        "Nota Anki: {0} → {1}.": ("Anki note: {0} → {1}.", "Anki ノート：{0} → {1}。"),
        "Questi campi per ora restano vuoti: {0}.": ("These fields are left empty for now: {0}.", "次のフィールドは現在空欄になります：{0}。"),
        "Non riesco a leggere questo backup di Yomitan: {0}": ("Couldn't read this Yomitan backup: {0}", "この Yomitan のバックアップを読み込めません：{0}"),
        "Preparo la ricerca per significato in {0}: {1}%": ("Preparing search by meaning in {0}: {1}%", "{0} の意味検索を準備中：{1}%"),
        "Preparo la ricerca in kana…": ("Preparing kana search…", "かな検索を準備中…"),
        "Preparo la ricerca in kana (イタリアご = いたりあご) in {0}: {1}%": ("Preparing kana search (イタリアご = いたりあご) in {0}: {1}%", "{0} のかな検索（イタリアご = いたりあご）を準備中：{1}%"),
        "「{0}」 è già installato.": ("“{0}” is already installed.", "「{0}」はすでにインストールされています。"),
        "Questo file non sembra un dizionario Yomitan (manca index.json).": ("This file doesn't look like a Yomitan dictionary (index.json is missing).", "Yomitan 形式の辞書ではないようです（index.json がありません）。"),
        "Formato di dizionario {0} non supportato.": ("Dictionary format {0} isn't supported.", "辞書の形式 {0} には対応していません。"),
        "Import fallito: {0}": ("Import failed: {0}", "読み込みに失敗しました：{0}"),

        // Quick lookup
        "Ricerca rapida": ("Quick lookup", "クイック検索"),
        "Cerca quello che copi": ("Look up what you copy", "コピーした語を検索"),
        "Apri gli screenshot appena fatti": ("Open fresh screenshots", "撮ったばかりのスクショを開く"),
        "Scorciatoie e doppio tocco sul retro": ("Shortcuts and Back Tap", "ショートカットと背面タップ"),
        "Copia una parola in qualsiasi app e torna su Kotoba: la cerca da sola. Perché iOS non lo chieda ogni volta: Impostazioni › App › Kotoba › Incolla da altre app › Consenti.":
            ("Copy a word in any app and come back to Kotoba: it looks it up by itself. So iOS stops asking every time: Settings › Apps › Kotoba › Paste from Other Apps › Allow.",
             "どのアプリでも単語をコピーして Kotoba に戻ると、自動で検索します。毎回確認されないようにするには：設定 › アプリ › Kotoba › ほかのAppからペースト › 許可。"),
        "Dal menu Condividi": ("From the Share menu", "共有メニューから"),
        "Seleziona del testo in qualsiasi app, tocca Condividi e poi Kotoba: la definizione appare in un pannello, senza lasciare l'app in cui leggi.":
            ("Select text in any app, tap Share, then Kotoba: the definition appears in a panel without leaving the app you're reading.",
             "どのアプリでも文字を選択して「共有」→「Kotoba」をタップすると、読んでいるアプリを離れずにパネルで意味が表示されます。"),
        "Centro di Controllo": ("Control Center", "コントロールセンター"),
        "Apri il Centro di Controllo, tieni premuto su uno spazio vuoto, tocca «Aggiungi un controllo» e cerca Kotoba: «Cerca appunti» e «Lente».":
            ("Open Control Center, press and hold an empty space, tap “Add a Control” and search for Kotoba: “Cerca appunti” and “Lente”.",
             "コントロールセンターを開き、空いた場所を長押しして「コントロールを追加」から Kotoba を検索：「Cerca appunti」と「Lente」。"),
        "Schermata di blocco": ("Lock Screen", "ロック画面"),
        "Tieni premuto sulla schermata di blocco, tocca Personalizza › Schermata di blocco e sostituisci la torcia o la fotocamera con un controllo di Kotoba.":
            ("Press and hold the Lock Screen, tap Customize › Lock Screen and replace the flashlight or camera with a Kotoba control.",
             "ロック画面を長押しして「カスタマイズ」›「ロック画面」をタップし、ライトやカメラを Kotoba のコントロールに置き換えます。"),
        "Doppio tocco sul retro": ("Back Tap", "背面タップ"),
        "1. Nell'app Comandi Rapidi crea un comando con l'azione Kotoba «Cerca negli appunti». 2. Impostazioni › Accessibilità › Tocco › Tocca il retro › Doppio tocco: scegli quel comando. Poi copia una parola e tocca due volte il retro dell'iPhone.":
            ("1. In the Shortcuts app, create a shortcut with the Kotoba action “Cerca negli appunti”. 2. Settings › Accessibility › Touch › Back Tap › Double Tap: choose that shortcut. Then copy a word and double-tap the back of the iPhone.",
             "1. ショートカットアプリで Kotoba のアクション「Cerca negli appunti」を使ったショートカットを作成。2. 設定 › アクセシビリティ › タッチ › 背面タップ › ダブルタップでそのショートカットを選択。あとは単語をコピーして iPhone の背面を2回タップ。"),
        "«Cerca gli appunti in Kotoba» oppure «Apri la lente di Kotoba».":
            ("“Search clipboard in Kotoba” or “Open Kotoba lens”.", "「Search clipboard in Kotoba」または「Open Kotoba lens」。"),
        "Dagli appunti": ("From the clipboard", "クリップボードから"),
        "Negli appunti non c'è testo": ("There's no text on the clipboard", "クリップボードに文字がありません"),
        "Apri in Kotoba": ("Open in Kotoba", "Kotoba で開く"),

        // Camera
        "Lente": ("Lens", "レンズ"),
        "Foto": ("Photo", "写真"),
        "Tocca": ("Tap", "タップ"),
        "Seleziona": ("Select", "選択"),
        "Ultimo screenshot": ("Latest screenshot", "最新のスクショ"),
        "Scatta una foto, scegline una o apri il tuo ultimo screenshot. Poi tocca una parola giapponese: la definizione appare qui sotto.":
            ("Take a photo, pick one or open your latest screenshot. Then tap a Japanese word: its definition appears below.",
             "写真を撮るか選ぶか、最新のスクショを開いてください。日本語の単語をタップすると、下に意味が表示されます。"),
        "Kotoba non può vedere le foto: Impostazioni › App › Kotoba › Foto.":
            ("Kotoba can't see your photos: Settings › Apps › Kotoba › Photos.", "Kotoba が写真にアクセスできません：設定 › アプリ › Kotoba › 写真。"),
        "Non trovo screenshot.": ("No screenshots found.", "スクショが見つかりません。"),
        "La lente non è disponibile": ("The lens isn't available", "レンズは利用できません"),
        "Questo iPhone non riconosce il giapponese dal vivo. Usa la modalità Foto.":
            ("This iPhone can't read Japanese live. Use Photo mode.", "この iPhone はライブで日本語を認識できません。「写真」モードを使ってください。"),
        "Serve la fotocamera": ("Camera access needed", "カメラへのアクセスが必要です"),
        "Consenti l'accesso in Impostazioni › App › Kotoba › Fotocamera.":
            ("Allow access in Settings › Apps › Kotoba › Camera.", "設定 › アプリ › Kotoba › カメラ で許可してください。"),
        "Inquadra una parola con il mirino. Tocca ⏸ per fermare l'immagine e leggere con calma.":
            ("Aim the crosshair at a word. Tap ⏸ to freeze the picture and read calmly.", "照準を単語に合わせてください。⏸ で画面を止めてゆっくり読めます。"),

        "Metti il punto rosso sul primo carattere della parola. Con ⏸ fermi l'immagine: poi tocchi le parole, o usi Seleziona per il testo verticale.":
            ("Put the red dot on the first character of the word. ⏸ freezes the picture: then tap words, or use Select for vertical text.",
             "赤い点を単語の最初の文字に合わせてください。⏸ で画面を止めると、単語をタップしたり、縦書きは「選択」で選べます。"),
        "Tocca una parola. Per il testo verticale usa Seleziona.":
            ("Tap a word. For vertical text use Select.", "単語をタップしてください。縦書きは「選択」を使ってください。"),
        "縦: punta il punto rosso sul primo carattere della parola, tenendo le colonne dritte.":
            ("縦: put the red dot on the first character of the word, keeping the columns straight.", "縦：赤い点を単語の最初の文字に合わせ、行をまっすぐに保ってください。"),
        "Metti il punto rosso sul primo carattere della parola. Per i libri in verticale scegli 縦 in alto.":
            ("Put the red dot on the first character of the word. For vertical books choose 縦 at the top.", "赤い点を単語の最初の文字に合わせてください。縦書きの本は上の「縦」を選んでください。"),
        "Tocca una parola. Per il testo verticale usa Seleziona: tieni premuto sulla parola.":
            ("Tap a word. For vertical text use Select: press and hold the word.", "単語をタップしてください。縦書きは「選択」で単語を長押ししてください。"),
        "縦: metti il punto rosso sul primo carattere della parola, con le colonne dritte sullo schermo.":
            ("縦: put the red dot on the first character of the word, with the columns straight on screen.", "縦：赤い点を単語の最初の文字に合わせ、行を画面に対してまっすぐにしてください。"),
        "Tocca una parola, anche nel testo verticale. Seleziona usa invece Live Text.":
            ("Tap a word, vertical text too. Select uses Live Text instead.", "単語をタップしてください（縦書きも可）。「選択」は Live Text を使います。"),
        "Punta il punto rosso su una parola: si aggancia quando è ferma. Tocca lo schermo per fermare l'immagine e scegliere col dito.":
            ("Point the red dot at a word: it locks on when the phone is still. Touch the screen to freeze the picture and choose with your finger.",
             "赤い点を単語に向けてください。止まると単語を捉えます。画面に触れると画像が止まり、指で選べます。"),
        "縦: punta una parola con le colonne dritte. Per leggere la pagina intera allontanati, metti 1× e tocca lo schermo.":
            ("縦: point at a word with the columns straight. To read the whole page, move back, set 1× and touch the screen.",
             "縦：行をまっすぐにして単語に向けてください。ページ全体を読むには少し離れて 1× にし、画面に触れてください。"),
        "Tocca una parola. Le colonne già lette hanno il bordo tratteggiato; Seleziona usa Live Text.":
            ("Tap a word. Columns already read have a dashed outline; Select uses Live Text.",
             "単語をタップしてください。読み取り済みの行は点線で囲まれます。「選択」は Live Text を使います。"),
        "Leggo la pagina…": ("Reading the page…", "ページを読み取り中…"),
        "Torcia": ("Torch", "ライト"),
        "Zoom": ("Zoom", "ズーム"),
        "Direzione del testo": ("Text direction", "文字の向き"),
        "Automatica": ("Automatic", "自動"),
        "横 orizzontale": ("横 horizontal", "横書き"),
        "縦 verticale": ("縦 vertical", "縦書き"),
        "Nessuna parola qui. Tocca un altro carattere nella riga sopra.":
            ("No word here. Tap another character in the line above.", "ここに単語はありません。上の行の別の文字をタップしてください。"),
        // Grammar
        "negativo": ("negative", "否定"),
        "passato": ("past", "過去"),
        "forma て": ("て-form", "て形"),
        "cortese": ("polite", "丁寧"),
        "cortese passato": ("polite past", "丁寧・過去"),
        "cortese negativo": ("polite negative", "丁寧・否定"),
        "cortese negativo passato": ("polite past negative", "丁寧・否定・過去"),
        "cortese volitivo": ("polite volitional", "丁寧・意向"),
        "condizionale ば": ("ば conditional", "仮定 ば"),
        "condizionale たら": ("たら conditional", "仮定 たら"),
        "elenco たり": ("たり list", "列挙 たり"),
        "potenziale": ("potential", "可能"),
        "passivo": ("passive", "受身"),
        "causativo": ("causative", "使役"),
        "volitivo": ("volitional", "意向"),
        "imperativo": ("imperative", "命令"),
        "desiderativo たい": ("desire たい", "希望 たい"),
        "radice": ("stem", "連用形"),
        "progressivo ている": ("progressive ている", "進行 ている"),
        "completamento てしまう": ("completion てしまう", "完了 てしまう"),
        "preparazione ておく": ("preparation ておく", "準備 ておく"),
        "avverbio": ("adverb", "副詞"),
        "sostantivo さ": ("さ noun", "名詞化 さ"),
        "apparenza そう": ("appearance そう", "様態 そう"),
        "eccesso すぎる": ("excess すぎる", "過度 すぎる"),
        "negativo ないで": ("negative ないで", "否定 ないで"),
        "obbligo なきゃ": ("obligation なきゃ", "義務 なきゃ"),
        "negativo ず": ("negative ず", "否定 ず"),

        // From PC (texthooker)
        "Dal PC": ("From PC", "PCから"),
        "Testo dal PC": ("Text from PC", "PCのテキスト"),
        "Incolla una riga e premi Invio: appare sull'iPhone.": ("Paste a line and press Enter: it appears on the iPhone.", "行を貼り付けてEnterを押すと、iPhoneに表示されます。"),
        "Invia": ("Send", "送信"),
        "Indirizzo del PC, es. 192.168.1.20": ("PC address, e.g. 192.168.1.20", "PCのアドレス(例: 192.168.1.20)"),
        "Trova il PC sulla Wi-Fi": ("Find the PC on Wi-Fi", "Wi-FiでPCを探す"),
        "Ricevi dal PC": ("Receive from PC", "PCから受信"),
        "Computer": ("Computer", "パソコン"),
        "Non ho trovato Textractor sulla Wi-Fi. Fai avanzare una riga nel gioco (l'estensione si accende con la prima riga) e riprova, oppure scrivi l'indirizzo a mano.":
            ("Textractor wasn't found on the Wi-Fi. Advance one line in the game (the extension starts with the first line) and try again, or type the address yourself.",
             "Wi-FiでTextractorが見つかりません。ゲームのテキストを1行進めてから(拡張機能は最初の行で起動します)もう一度試すか、アドレスを手で入力してください。"),
        "Sul PC serve Textractor con l'estensione textractor_websocket (porta 6677). Telefono e PC devono essere sulla stessa Wi-Fi. La guida passo passo è qui sotto.":
            ("The PC needs Textractor with the textractor_websocket extension (port 6677). Phone and PC must be on the same Wi-Fi. Step-by-step guide below.",
             "PCにはTextractorとtextractor_websocket拡張機能(ポート6677)が必要です。iPhoneとPCは同じWi-Fiにつないでください。手順は下にあります。"),
        "Ricevi anche dal PC verso il telefono": ("Also let the PC send to the phone", "PCからiPhoneへの送信も受け付ける"),
        "Indirizzo del telefono": ("Phone address", "iPhoneのアドレス"),
        "Non sei su una Wi-Fi": ("Not on Wi-Fi", "Wi-Fiに接続されていません"),
        "Non riesco ad ascoltare: {0}": ("Can't listen: {0}", "受信を開始できません: {0}"),
        "Se il collegamento non funziona": ("If the connection doesn't work", "接続できないとき"),
        "Il contrario: è il PC a mandare le righe al telefono, quindi il firewall di Windows non si mette in mezzo. Sul PC avvia kotoba-relay.bat (copia ogni riga che Textractor mette negli appunti), oppure apri l'indirizzo qui sopra nel browser e incolla le righe a mano. Funziona solo con Kotoba aperta.":
            ("The other way round: the PC sends lines to the phone, so the Windows firewall doesn't get in the way. On the PC run kotoba-relay.bat (it sends every line Textractor copies to the clipboard), or open the address above in a browser and paste lines by hand. Works only while Kotoba is open.",
             "逆方向の接続です。PCからiPhoneへ送るので、Windowsのファイアウォールに邪魔されません。PCでkotoba-relay.batを起動する(Textractorがクリップボードにコピーした行を送ります)か、上のアドレスをブラウザで開いて行を貼り付けてください。Kotobaを開いている間だけ使えます。"),
        "Unisci le righe di un riquadro": ("Join the lines of one text box", "テキストボックス内の改行をつなげる"),
        "Togli le letture tra parentesi: 漢字《かんじ》": ("Remove readings in brackets: 漢字《かんじ》", "括弧内の読みを消す: 漢字《かんじ》"),
        "Togli il furigana attaccato: 天気てんき → 天気": ("Remove hooked furigana: 天気てんき → 天気", "混ざったふりがなを消す: 天気てんき → 天気"),
        "Sperimentale: usa i tuoi dizionari per riconoscere le letture.": ("Experimental: uses your dictionaries to recognize readings.", "試験的: 辞書を使って読みを見分けます。"),
        "Caratteri doppi: ここんんにに → こんに": ("Doubled characters: ここんんにに → こんに", "重複した文字: ここんんにに → こんに"),
        "Riga ripetuta due volte": ("Line repeated twice", "2回繰り返された行"),
        "Ignora una riga uguale alla precedente": ("Skip a line identical to the previous one", "直前と同じ行は無視する"),
        "Regole personalizzate": ("Custom rules", "カスタムルール"),
        "Pulizia automatica": ("Automatic clean-up", "自動クリーンアップ"),
        "Vale per le righe nuove. Per correggere una riga già arrivata tienila premuta › Modifica.":
            ("Applies to new lines. To fix a line that already arrived, long-press it › Edit.",
             "新しい行に適用されます。受信済みの行は長押し › 編集で直せます。"),
        "Schermo sempre acceso in questa scheda": ("Keep the screen on in this tab", "このタブでは画面を消さない"),
        "Preparare il PC (una volta sola)": ("Set up the PC (once)", "PCの準備(最初の1回だけ)"),
        "Fatto": ("Done", "完了"),
        "Riprova ora": ("Try again now", "今すぐ再試行"),
        "Scrivi l'indirizzo del PC.": ("Type the PC's address.", "PCのアドレスを入力してください。"),
        "Mi collego…": ("Connecting…", "接続中…"),
        "Collegato: le righe nuove arrivano da sole.": ("Connected: new lines arrive on their own.", "接続しました。新しい行が自動で届きます。"),
        "Il PC risponde, ma Textractor non trasmette ancora. Apri il gioco con Textractor e fai avanzare una riga: l'estensione si accende con la prima riga. Riprovo da solo.":
            ("The PC answers, but Textractor isn't sending yet. Open the game with Textractor and advance one line: the extension starts with the first line. Retrying on my own.",
             "PCは応答していますが、Textractorがまだ送信していません。Textractorでゲームを開き、テキストを1行進めてください(拡張機能は最初の行で起動します)。自動で再試行します。"),
        "Il PC non risponde. Controlla l'indirizzo, che telefono e PC siano sulla stessa Wi-Fi e che il firewall di Windows lasci passare Textractor (vedi la guida). Riprovo da solo.":
            ("The PC doesn't answer. Check the address, that phone and PC are on the same Wi-Fi, and that the Windows firewall lets Textractor through (see the guide). Retrying on my own.",
             "PCが応答しません。アドレス、iPhoneとPCが同じWi-Fiにあるか、WindowsのファイアウォールがTextractorを許可しているか(手順を参照)を確認してください。自動で再試行します。"),
        "iOS non lascia Kotoba usare la rete locale: Impostazioni › Privacy e sicurezza › Rete locale › Kotoba.":
            ("iOS doesn't let Kotoba use the local network: Settings › Privacy & Security › Local Network › Kotoba.",
             "iOSがローカルネットワークの使用を許可していません: 設定 › プライバシーとセキュリティ › ローカルネットワーク › Kotoba。"),
        "Il PC ha chiuso il collegamento (Textractor chiuso?). Riprovo da solo.": ("The PC closed the connection (Textractor closed?). Retrying on my own.", "PCが接続を切りました(Textractorを閉じましたか?)。自動で再試行します。"),
        "Non riesco a collegarmi: {0}. Riprovo da solo.": ("Can't connect: {0}. Retrying on my own.", "接続できません: {0}。自動で再試行します。"),
        "Scarica Textractor da github.com/Artikash/Textractor (Releases › Textractor-5.2.0-Zip-Version-English-Only.zip) ed estrailo: dentro ci sono le cartelle x86 e x64.":
            ("Download Textractor from github.com/Artikash/Textractor (Releases › Textractor-5.2.0-Zip-Version-English-Only.zip) and extract it: it holds an x86 and an x64 folder.",
             "github.com/Artikash/Textractor(Releases › Textractor-5.2.0-Zip-Version-English-Only.zip)からTextractorをダウンロードして展開します。中にx86とx64のフォルダがあります。"),
        "Scarica textractor_websocket_x86.zip e textractor_websocket_x64.zip da github.com/kuroahna/textractor_websocket (Releases). Metti ogni .dll nella cartella x86 o x64 di Textractor.":
            ("Download textractor_websocket_x86.zip and textractor_websocket_x64.zip from github.com/kuroahna/textractor_websocket (Releases). Put each .dll in Textractor's x86 or x64 folder.",
             "github.com/kuroahna/textractor_websocket(Releases)からtextractor_websocket_x86.zipとtextractor_websocket_x64.zipをダウンロードし、それぞれの.dllをTextractorのx86とx64フォルダに入れます。"),
        "Apri Textractor › Extensions › tasto destro › Add extension › scegli «*.dll» in basso › seleziona la .dll. Fallo sia in x86 sia in x64.":
            ("Open Textractor › Extensions › right-click › Add extension › pick “*.dll” at the bottom › select the .dll. Do it in both x86 and x64.",
             "Textractor › Extensions › 右クリック › Add extension › 下で「*.dll」を選び › .dllを選択。x86とx64の両方で行います。"),
        "Avvia il gioco, agganciati con Textractor e scegli la riga giusta nel menu in alto. Alla prima riga Windows chiede il permesso del firewall: spunta «Reti private» e consenti.":
            ("Start the game, attach Textractor and choose the right text thread in the menu at the top. At the first line Windows asks for firewall permission: tick “Private networks” and allow.",
             "ゲームを起動してTextractorでフックし、上のメニューで正しいテキストスレッドを選びます。最初の行でWindowsがファイアウォールの許可を求めるので、「プライベートネットワーク」にチェックして許可します。"),
        "Qui tocca «Trova il PC sulla Wi-Fi» (o scrivi l'indirizzo IPv4 che vedi con il comando ipconfig) e accendi «Ricevi dal PC».":
            ("Here, tap “Find the PC on Wi-Fi” (or type the IPv4 address shown by the ipconfig command) and turn on “Receive from PC”.",
             "ここで「Wi-FiでPCを探す」をタップし(またはipconfigコマンドで表示されるIPv4アドレスを入力し)、「PCから受信」をオンにします。"),
        "Cerca (espressione regolare)": ("Find (regular expression)", "検索(正規表現)"),
        "Sostituisci con (vuoto: cancella)": ("Replace with (empty: delete)", "置換後(空欄で削除)"),
        "Espressione non valida: questa regola viene saltata.": ("Invalid expression: this rule is skipped.", "正規表現が無効です。このルールはスキップされます。"),
        "Aggiungi una regola": ("Add a rule", "ルールを追加"),
        "Esempio: togli il nome di chi parla 【…】": ("Example: remove the speaker's name 【…】", "例: 話者名【…】を消す"),
        "Le regole si applicano in ordine, dopo la pulizia automatica.": ("Rules apply in order, after the automatic clean-up.", "ルールは自動クリーンアップの後、上から順に適用されます。"),
        "Collegamento e pulizia": ("Connection and clean-up", "接続とクリーンアップ"),
        "Ricollegati ora": ("Reconnect now", "今すぐ再接続"),
        "Cancella tutte le righe": ("Delete all lines", "すべての行を削除"),
        "Cancellare tutte le righe ricevute?": ("Delete all received lines?", "受信したすべての行を削除しますか?"),
        "Modifica": ("Edit", "編集"),
        "Copia": ("Copy", "コピー"),
        "Cerca la riga intera": ("Search the whole line", "行全体を検索"),
        "Ripristina l'originale": ("Restore the original", "元に戻す"),
        "Cancella le letture rimaste attaccate al testo (furigana), i nomi o i simboli in più. Una riga vuota viene eliminata.":
            ("Delete readings stuck to the text (furigana), extra names or symbols. An empty line is deleted.",
             "本文に混ざった読み(ふりがな)や余分な名前・記号を消してください。空にした行は削除されます。"),
        "Togli le letture (furigana)": ("Remove readings (furigana)", "読み(ふりがな)を消す"),
        "Arrivata dal PC": ("As it came from the PC", "PCから届いた元の行"),
        "Modifica la riga": ("Edit line", "行を編集"),
        "Annulla": ("Cancel", "キャンセル"),
        "Salva": ("Save", "保存"),
        "In diretta dal PC": ("Live from PC", "PCからライブ"),
        "Mi collego al PC…": ("Connecting to PC…", "PCに接続中…"),
        "Aspetto Textractor…": ("Waiting for Textractor…", "Textractorを待っています…"),
        "Il PC non risponde": ("PC not answering", "PCが応答しません"),
        "In ascolto sul telefono": ("Listening on the phone", "iPhoneで受信待ち"),
        "Manca l'indirizzo del PC": ("PC address missing", "PCのアドレスがありません"),
        "Non collegato": ("Not connected", "未接続"),
        "Collegato. Fai avanzare il testo nel gioco: ogni riga che Textractor aggancia appare qui.":
            ("Connected. Advance the text in the game: every line Textractor hooks appears here.",
             "接続しました。ゲームのテキストを進めると、Textractorがフックした行がここに表示されます。"),
        "Leggi una visual novel sul PC: Textractor manda qui ogni riga, e tocchi le parole per cercarle senza staccare gli occhi dal gioco.":
            ("Read a visual novel on the PC: Textractor sends every line here, and you tap words to look them up without leaving the game.",
             "PCでビジュアルノベルを読みながら、Textractorが送る各行をここで受け取り、単語をタップして調べられます。"),
        "Collega il PC": ("Connect the PC", "PCを接続"),
    ]
}
