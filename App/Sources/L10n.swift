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
    ]
}
