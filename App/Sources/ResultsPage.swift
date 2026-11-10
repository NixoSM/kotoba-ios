import Foundation
import KotobaCore

/// Builds the HTML page that shows search results. Definitions are HTML so
/// that each dictionary's own structure and stylesheet survive.
enum ResultsPage {
    struct Options {
        var stylesheets: [String: String] = [:]
        /// `stylesheets` already scoped (AppModel keeps it ready): skips redoing it on every redraw.
        var dictionaryCSS: String?
        var indexStatus: String?
        var mined: Set<String> = []
        var canMine = false
        var collapsed: Set<String> = []
        var appearance = Appearance()
    }

    static func html(outcome: SearchResults, query: String, options o: Options) -> String {
        var direct = ""
        if let reading = outcome.romajiReading, !outcome.direct.isEmpty {
            direct += section(tr("Letto come {0}", reading))
        }
        for (i, g) in outcome.direct.enumerated() {
            direct += entry(g, link: o.canMine ? "kotoba://mine?s=direct&i=\(i)" : nil, options: o)
        }
        var meaning = ""
        if !outcome.byMeaning.isEmpty {
            meaning += section(tr("Parole che significano «{0}»", query.trimmingCharacters(in: .whitespaces)))
            if let status = o.indexStatus { meaning += "<p class=\"note\">\(GlossaryHTML.escape(status))</p>" }
            for (i, g) in outcome.byMeaning.enumerated() {
                meaning += entry(g, link: o.canMine ? "kotoba://mine?s=meaning&i=\(i)" : nil, options: o)
            }
        }
        let starting = suggestions(outcome)
        var body: String
        if outcome.suggestionsFirst {
            body = starting + (outcome.romajiFirst ? direct + meaning : meaning + direct)
        } else {
            body = outcome.romajiFirst ? direct + starting + meaning : meaning + direct + starting
        }
        body += kanji(outcome)
        let words = outcome.direct.count + outcome.byMeaning.count
        if let ms = outcome.milliseconds, words > 0 {
            body += "<p class=\"timing\">\(words == 1 ? tr("1 parola · {0} ms", ms) : tr("{0} parole · {1} ms", words, ms))</p>"
        }
        return page(body: body, options: o)
    }

    /// The page around the entries: fonts, theme, dictionary styles, your CSS.
    static func page(body: String, options o: Options) -> String {
        let a = o.appearance
        let bodyFont = FontCatalog.choice(a.bodyFont)
        let headFont = FontCatalog.choice(a.headwordFont)
        let dictionaryCSS = o.dictionaryCSS ?? scopedCSS(o.stylesheets)
        let variables = """
        :root { --body-font: \(bodyFont.css), 'Hiragino Sans', sans-serif; --head-font: \(headFont.css), 'Hiragino Mincho ProN', serif;
                --size: \(Int(a.fontSize))px; --leading: \(a.lineHeight); }
        """
        return """
        <!doctype html>
        <html lang="\(L10n.htmlLang)" class="\(a.layout.rawValue)"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>\(FontCatalog.fontFaceCSS([bodyFont, headFont]))</style>
        <style>\(ThemePalette.css(for: a.theme))\(variables)\(baseCSS)</style>
        <style>\(dictionaryCSS)</style>
        <style>\(ownCSS(a.customCSS))</style>
        </head><body>\(bodyOpen)\(body)\(bodyClose)\(tapScript)</script></body></html>
        """
    }

    /// Your own CSS, as typed. "</" is the only thing that could close the
    /// <style> element early and spill the rest onto the page; with the
    /// backslash it means the same to CSS and nothing to HTML.
    static func ownCSS(_ css: String) -> String {
        css.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// The page's only script carries this mark. It is made up afresh at every
    /// launch, so nothing written in a dictionary file can pass for it.
    static let scriptNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    /// What the page may load and run: its own fonts and the dictionaries'
    /// pictures, its own script, and nothing from the network. Definitions are
    /// already cleaned when they are turned into HTML; this is the second lock.
    static var contentSecurityPolicy: String {
        "default-src 'none'; img-src \(MediaLink.scheme): data:; font-src \(MediaLink.scheme):; "
            + "style-src 'unsafe-inline'; script-src 'nonce-\(scriptNonce)'"
    }

    /// Each dictionary's styles.css, limited to its own definitions.
    static func scopedCSS(_ stylesheets: [String: String]) -> String {
        stylesheets.sorted { $0.key < $1.key }.map { title, css in
            GlossaryHTML.scopedCSS(css, scope: "[data-dict=\"\(scopeID(title))\"]")
        }.joined(separator: "\n")
    }

    /// The results sit in this element, so a new search can replace just
    /// them and keep the page (and its multi-megabyte fonts) loaded.
    static let bodyOpen = "<main id=\"kotoba-results\">"
    static let bodyClose = "</main><script nonce=\"\(scriptNonce)\">"

    /// "Words that start with …": a column of headwords, as in the index of a
    /// printed dictionary. Tapping one searches it.
    private static func suggestions(_ outcome: SearchResults) -> String {
        guard !outcome.startingWith.isEmpty else { return "" }
        var html = section(tr("Parole che iniziano con «{0}»", outcome.startingWithText))
        html += "<nav class=\"starts\">"
        for word in outcome.startingWith {
            html += "<a class=\"start\" href=\"kotoba://search?q=\(percent(word.expression))\">"
            html += "<span class=\"start-word\" lang=\"ja\">\(GlossaryHTML.escape(word.expression))</span>"
            if !word.reading.isEmpty { html += "<span class=\"start-reading\" lang=\"ja\">\(GlossaryHTML.escape(word.reading))</span>" }
            html += "<span class=\"start-gloss\">\(GlossaryHTML.escape(word.gloss))</span></a>"
        }
        return html + "</nav>"
    }

    private static func section(_ text: String) -> String {
        "<h2 class=\"section\">\(GlossaryHTML.escape(text))</h2>"
    }

    /// The characters of the first word, each in a square of writing paper
    /// with its readings and meanings beside it. Tapping the square searches
    /// the character.
    private static func kanji(_ outcome: SearchResults) -> String {
        guard !outcome.kanji.isEmpty else { return "" }
        var html = section(tr("I kanji di «{0}»", outcome.kanjiSource))
        // More than one kanji dictionary: say whose words these are.
        let named = Set(outcome.kanji.map(\.dictionary)).count > 1
        var previous = ""
        for entry in outcome.kanji {
            let first = entry.character != previous
            previous = entry.character
            html += "<section class=\"kanji\(first ? "" : " more")\">"
            if first {
                html += "<a class=\"kanji-glyph\" lang=\"ja\" href=\"kotoba://search?q=\(percent(entry.character))\">\(GlossaryHTML.escape(entry.character))</a>"
            } else {
                html += "<span class=\"kanji-glyph blank\"></span>"
            }
            html += "<div class=\"kanji-body\">"
            if named { html += "<div class=\"dict-name\">\(GlossaryHTML.escape(entry.dictionary))</div>" }
            if !entry.onyomi.isEmpty || !entry.kunyomi.isEmpty {
                html += "<dl class=\"yomi\" lang=\"ja\">"
                if !entry.onyomi.isEmpty { html += "<dt>音</dt><dd>\(entry.onyomi.map(reading).joined(separator: "<i></i>"))</dd>" }
                if !entry.kunyomi.isEmpty { html += "<dt>訓</dt><dd>\(entry.kunyomi.map(reading).joined(separator: "<i></i>"))</dd>" }
                html += "</dl>"
            }
            if !entry.meanings.isEmpty {
                html += "<p class=\"kanji-meanings\">\(GlossaryHTML.escape(entry.meanings.joined(separator: "; ")))</p>"
            }
            let facts = kanjiFacts(entry)
            if !facts.isEmpty {
                html += "<div class=\"meta\">" + facts.map { "<span class=\"tag\">\(GlossaryHTML.escape($0))</span>" }.joined() + "</div>"
            }
            html += "</div></section>"
        }
        return html
    }

    /// た.べる: what follows the dot is written in kana after the kanji, and is shown paler.
    private static func reading(_ text: String) -> String {
        guard let dot = text.firstIndex(of: "."), dot != text.startIndex else { return "<span>\(GlossaryHTML.escape(text))</span>" }
        let stem = text[..<dot], rest = text[text.index(after: dot)...]
        return "<span>\(GlossaryHTML.escape(String(stem)))<span class=\"oku\">\(GlossaryHTML.escape(String(rest)))</span></span>"
    }

    /// Strokes, school year and JLPT level when the dictionary gives them; its other numbers are index entries of printed books.
    private static func kanjiFacts(_ entry: KanjiEntry) -> [String] {
        var out: [String] = []
        if let strokes = entry.stats["strokes"], !strokes.isEmpty { out.append(strokes == "1" ? tr("1 tratto") : tr("{0} tratti", strokes)) }
        if let grade = entry.stats["grade"], !grade.isEmpty { out.append(tr("classe {0}", grade)) }
        if let jlpt = entry.stats["jlpt"], !jlpt.isEmpty { out.append("JLPT \(jlpt)") }
        if let freq = entry.stats["freq"], !freq.isEmpty { out.append(tr("frequenza {0}", freq)) }
        // Frequency lists name themselves: two of them rarely count the same way.
        out += entry.frequencies.map { "\($0.dictionary) \($0.value)" }
        return out + entry.tags
    }

    static func entry(_ g: HeadwordGroup, link: String?, options o: Options) -> String {
        let a = o.appearance
        let mined = o.mined.contains(g.minedKey)
        var html = "<article class=\"entry\"><header><div class=\"actions\">"
        let audio = "kotoba://audio?e=\(percent(g.expression))&r=\(percent(g.reading))"
        html += "<a class=\"btn audio\" href=\"\(audio)\" aria-label=\"\(tr("Ascolta"))\">\(icon("play"))</a>"
        if let link {
            html += mined
                ? "<a class=\"btn mine done\" href=\"\(link)\" aria-label=\"\(tr("Già in Anki"))\">\(icon("check"))</a>"
                : "<a class=\"btn mine\" href=\"\(link)\" aria-label=\"\(tr("Aggiungi ad Anki"))\">\(icon("plus"))</a>"
        }
        html += "</div>"
        html += "<h1 class=\"headword\" lang=\"ja\">\(headword(g, a))</h1>"
        if !g.reasons.isEmpty {
            let chain = g.reasons.map(\.italianLabel).joined(separator: " › ")
            html += "<div class=\"chain\">\(GlossaryHTML.escape(g.matchedText)) ← \(GlossaryHTML.escape(chain))</div>"
        }
        html += metaRow(g, a)
        html += "</header>"

        let compact = a.layout == .compact
        if compact { html += "<ol class=\"defs\">" }
        for def in g.definitions {
            let id = scopeID(def.dictionary)
            let name = GlossaryHTML.escape(def.dictionary)
            let content: String
            if def.items.count > 1, def.items.allSatisfy({ !$0.contains("<") && $0.count <= 80 }) {
                // Short plain glosses read best on one line: barrier | obstacle | hurdle.
                // Each gloss is a unit: it moves to the next line whole instead of breaking after "to".
                content = "<div class=\"gloss inline\">" + def.items.map { "<span class=\"g\">\($0)</span>" }.joined(separator: " ") + "</div>"
            } else if def.items.count == 1 {
                content = "<div class=\"gloss\">\(def.items[0])</div>"
            } else {
                content = "<ol class=\"gloss\">" + def.items.map { "<li>\($0)</li>" }.joined() + "</ol>"
            }
            if o.collapsed.contains(def.dictionary) {
                let item = "<details class=\"dict closed\" data-dict=\"\(id)\"><summary class=\"dict-name\">\(name)</summary>\(content)</details>"
                html += compact ? "<li>\(item)</li>" : item
            } else if compact {
                let pill = a.showDictionaryNames ? "<span class=\"dict-pill\">\(name)</span>" : ""
                html += "<li class=\"dict\" data-dict=\"\(id)\">\(pill)\(content)</li>"
            } else {
                let label = a.showDictionaryNames ? "<div class=\"dict-name\">\(name)</div>" : ""
                html += "<section class=\"dict\" data-dict=\"\(id)\">\(label)\(content)</section>"
            }
        }
        if compact { html += "</ol>" }
        return html + "</article>"
    }

    private static func headword(_ g: HeadwordGroup, _ a: Appearance) -> String {
        let plain = GlossaryHTML.escape(g.expression)
        let hasReading = !g.reading.isEmpty && g.reading != g.expression
        switch a.termDisplay {
        case .ruby:
            return Furigana.html(expression: g.expression, reading: g.reading)
        case .rubyAndReading:
            return Furigana.html(expression: g.expression, reading: g.reading)
                + (hasReading ? "<span class=\"reading\">\(GlossaryHTML.escape(g.reading))</span>" : "")
        case .termAndReading:
            return plain + (hasReading ? "<span class=\"reading\">【\(GlossaryHTML.escape(g.reading))】</span>" : "")
        case .termOnly:
            return plain
        }
    }

    /// Pitch accent, tags and frequency, in Yomitan's order.
    private static func metaRow(_ g: HeadwordGroup, _ a: Appearance) -> String {
        var html = ""
        let pitch = pitchHTML(g, a)
        let tags = a.showTags ? g.partsOfSpeech.prefix(6).map { "<span class=\"tag\">\(GlossaryHTML.escape($0))</span>" }.joined() : ""
        var freq = ""
        switch a.frequency {
        case .hidden:
            break
        case .split:
            freq = g.frequencies.map(frequencyChip).joined()
        case .average:
            let values = g.frequencies.map(\.value).filter { $0 > 0 }
            if !values.isEmpty {
                let mean = Int((Double(values.count) / values.reduce(0) { $0 + 1 / $1 }).rounded())
                freq = "<details class=\"freqs\"><summary>\(frequencyChip(name: tr("Frequenza"), value: "\(mean)", accent: true))</summary><div class=\"freq-list\">"
                    + g.frequencies.map(frequencyChip).joined() + "</div></details>"
            }
        }
        if !pitch.isEmpty { html += "<div class=\"pitches\" lang=\"ja\">\(pitch)</div>" }
        if !tags.isEmpty || !freq.isEmpty { html += "<div class=\"meta\">\(tags)\(freq)</div>" }
        return html
    }

    private static func frequencyChip(_ f: FrequencyInfo) -> String {
        frequencyChip(name: f.dictionary, value: f.display, accent: false)
    }

    private static func frequencyChip(name: String, value: String, accent: Bool) -> String {
        "<span class=\"freq\(accent ? " avg" : "")\"><span class=\"freq-name\">\(GlossaryHTML.escape(name))</span><span class=\"freq-value\">\(GlossaryHTML.escape(value))</span></span>"
    }

    static func pitchHTML(_ g: HeadwordGroup, _ a: Appearance) -> String {
        guard a.pitchNotation || a.pitchNumber || a.pitchGraph else { return "" }
        let reading = g.reading.isEmpty ? g.expression : g.reading
        var seen: Set<Int> = []
        let positions = g.pitches.filter { Kana.toHiragana($0.reading) == Kana.toHiragana(reading) }
            .flatMap(\.positions).filter { seen.insert($0).inserted }
        return positions.map { downstep in
            var parts: [String] = []
            if a.pitchNotation { parts.append(overline(reading, downstep: downstep)) }
            if a.pitchGraph { parts.append(graph(reading, downstep: downstep)) }
            if a.pitchNumber { parts.append("<span class=\"downstep\">[\(downstep)]</span>") }
            return "<span class=\"pitch-item\">" + parts.joined(separator: " ") + "</span>"
        }.joined()
    }

    /// Kana with a line over the high morae and a tick where the pitch drops.
    private static func overline(_ reading: String, downstep: Int) -> String {
        let morae = Mora.split(reading)
        let highs = Mora.pattern(morae: morae.count, downstep: downstep)
        var html = "<span class=\"pitch\">"
        for (i, mora) in morae.enumerated() {
            let high = highs[i]
            let drop = high && i + 1 < highs.count && !highs[i + 1]
            let cls = [high ? "h" : nil, drop ? "d" : nil].compactMap { $0 }.joined(separator: " ")
            html += cls.isEmpty ? GlossaryHTML.escape(mora) : "<span class=\"\(cls)\">\(GlossaryHTML.escape(mora))</span>"
        }
        return html + "</span>"
    }

    /// The dot-and-line graph: filled dots for the word, a hollow one for the particle after it.
    private static func graph(_ reading: String, downstep: Int) -> String {
        let count = Mora.split(reading).count
        let highs = Mora.pattern(morae: count, downstep: downstep)
        let step = 14.0
        let points = highs.enumerated().map { (x: 7 + Double($0.offset) * step, y: $0.element ? 5.0 : 17.0) }
        let line = points.map { "\($0.x),\($0.y)" }.joined(separator: " ")
        var svg = "<svg class=\"pitch-graph\" width=\"\(Int(Double(highs.count) * step))\" height=\"22\" viewBox=\"0 0 \(Int(Double(highs.count) * step)) 22\">"
        svg += "<polyline points=\"\(line)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.4\"/>"
        for (i, p) in points.enumerated() {
            let particle = i == points.count - 1
            svg += "<circle cx=\"\(p.x)\" cy=\"\(p.y)\" r=\"3.2\" \(particle ? "style=\"fill:var(--paper)\" stroke=\"currentColor\" stroke-width=\"1.2\"" : "fill=\"currentColor\"")/>"
        }
        return svg + "</svg>"
    }

    private static func icon(_ name: String) -> String {
        let path: String
        switch name {
        case "play": path = "<path d=\"M8 5.5v13l10.5-6.5z\" fill=\"currentColor\"/>"
        case "check": path = "<path d=\"M5 12.5l4.5 4.5L19 7.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        default: path = "<path d=\"M12 5v14M5 12h14\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"/>"
        }
        return "<svg width=\"18\" height=\"18\" viewBox=\"0 0 24 24\">\(path)</svg>"
    }

    private static func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }

    /// Short stable id for a dictionary title, safe inside a CSS selector.
    static func scopeID(_ title: String) -> String {
        var hash: UInt64 = 5381
        for b in title.utf8 { hash = (hash &* 33) ^ UInt64(b) }
        return "d" + String(hash, radix: 36)
    }

    /// Tap any Japanese character to look up the text starting there,
    /// like hovering with Yomitan. Readings in <rt> are skipped.
    private static let tapScript = """
    (function(){
      const jp = /^[\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff々〆ヶ]/;
      function charAt(x, y) {
        const r = document.caretRangeFromPoint(x, y);
        if (!r || r.startContainer.nodeType !== 3) return null;
        let node = r.startContainer, off = r.startOffset;
        if (off > 0) {
          const t = document.createRange(); t.setStart(node, off - 1); t.setEnd(node, off);
          const b = t.getBoundingClientRect();
          if (x >= b.left && x <= b.right && y >= b.top && y <= b.bottom) off -= 1;
        }
        if (off >= node.data.length) return null;
        return {node, off};
      }
      // The recording takes a moment to arrive: show that the tap was felt.
      document.addEventListener('click', function(e){
        const b = e.target.closest('.btn.audio');
        if (!b) return;
        b.classList.add('playing');
        setTimeout(function(){ b.classList.remove('playing'); }, 1600);
      }, true);
      document.addEventListener('click', function(e){
        if (e.target.closest('a, summary, .mine, rt')) return;
        const hit = charAt(e.clientX, e.clientY);
        if (!hit || hit.node.parentElement.closest('rt')) return;
        let text = hit.node.data.slice(hit.off);
        if (!jp.test(text)) return;
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        walker.currentNode = hit.node;
        while (text.length < 24 && walker.nextNode()) {
          if (walker.currentNode.parentElement.closest('rt, script, style')) continue;
          text += walker.currentNode.data;
        }
        const block = hit.node.parentElement.closest('li, p, td, summary, div');
        const sentence = block ? block.innerText.replace(/\\s+/g, ' ').slice(0, 200) : '';
        document.querySelectorAll('.tapped').forEach(n => n.classList.remove('tapped'));
        hit.node.parentElement.classList.add('tapped');
        location.href = 'kotoba://lookup?t=' + encodeURIComponent(text.slice(0, 24)) + '&s=' + encodeURIComponent(sentence);
      });
    })();
    """

    private static let baseCSS = """
    html { -webkit-text-size-adjust:100%; }
    body { margin:0; padding:6px 20px 130px; background:var(--paper); color:var(--ink);
           font-family:var(--body-font); font-size:var(--size); line-height:var(--leading);
           -webkit-font-smoothing:antialiased; }
    a { color:var(--shu); text-decoration:none; }

    .section { font:600 12px/1.2 -apple-system; letter-spacing:.14em; text-transform:uppercase; color:var(--shu);
               margin:22px 0 4px; display:flex; align-items:center; gap:10px; }
    .section::after { content:""; flex:1; height:1px; background:var(--rule); }
    .note { font-size:12px; color:var(--muted); margin:0 0 12px; }
    .timing { font:11px ui-monospace, Menlo, monospace; color:var(--muted); text-align:center; margin:22px 0 8px; opacity:.7; }

    /* One entry: the shu square marks the headword, as in printed dictionaries. */
    .entry { padding:22px 0 26px; border-bottom:1px solid var(--rule); }
    .entry:last-of-type { border-bottom:none; }
    header { position:relative; }
    .headword { font-family:var(--head-font); font-weight:700; font-size:calc(var(--size) * 2.35); line-height:1.25;
                margin:0 0 4px; padding-right:100px; letter-spacing:.02em; }
    .headword::before { content:""; display:inline-block; width:.22em; height:.22em; background:var(--shu);
                        vertical-align:.3em; margin-right:.3em; }
    .headword rt { font-family:var(--body-font); font-weight:400; font-size:.3em; color:var(--muted); letter-spacing:.08em; }
    .headword .reading { font-family:var(--body-font); font-weight:400; font-size:.42em; color:var(--muted); margin-left:.4em; }
    /* 44 points: the smallest target a thumb hits without aiming. */
    .actions { position:absolute; right:0; top:0; display:flex; gap:4px; }
    .btn { width:44px; height:44px; border-radius:22px; display:flex; align-items:center; justify-content:center;
           color:var(--ink); background:var(--chip); -webkit-tap-highlight-color:transparent; }
    .btn svg { width:20px; height:20px; }
    .btn.mine { color:var(--shu); }
    /* Already in Anki: a filled seal, not a paler copy of the plus. */
    .btn.mine.done { color:var(--paper); background:var(--shu); }
    .btn.playing { color:var(--paper); background:var(--shu); animation:kotoba-pulse .8s ease-in-out 2; }
    @keyframes kotoba-pulse { 50% { transform:scale(.88); opacity:.75; } }
    @media (prefers-reduced-motion: reduce) { .btn.playing { animation:none; } }
    .chain { font:12px ui-monospace, Menlo, monospace; color:var(--shu); margin:2px 0 8px; }

    .pitches { display:flex; flex-wrap:wrap; gap:4px 16px; align-items:center; font-size:.92em; margin:2px 0 6px; }
    .pitch-item { display:inline-flex; align-items:center; gap:6px; }
    .pitch .h { box-shadow:inset 0 1.5px 0 currentColor; }
    .pitch .d { box-shadow:inset 0 1.5px 0 currentColor, inset -1.5px 0 0 currentColor; }
    .downstep { color:var(--muted); font-size:.85em; }
    .pitch-graph { color:var(--ink); vertical-align:middle; }

    .meta { display:flex; flex-wrap:wrap; align-items:center; gap:6px; margin:4px 0 10px; }
    .tag { font:500 11px/1 -apple-system; padding:4px 7px; border-radius:5px; background:var(--chip); color:var(--muted); }
    .freqs { display:inline; }
    .freqs > summary { list-style:none; display:inline; cursor:pointer; }
    .freqs > summary::-webkit-details-marker { display:none; }
    .freq-list { display:flex; flex-wrap:wrap; gap:6px; margin-top:6px; }
    .freq { display:inline-flex; font:500 11px/1 -apple-system; border-radius:5px; overflow:hidden; box-shadow:inset 0 0 0 1px var(--rule); }
    .freq-name { padding:4px 6px; color:var(--muted); }
    .freq-value { padding:4px 7px; background:var(--chip); font-variant-numeric:tabular-nums; }
    .freq.avg { box-shadow:inset 0 0 0 1px color-mix(in srgb, var(--shu) 55%, transparent); }
    .freq.avg .freq-name { color:var(--shu); }

    .dict { margin:14px 0 0; }
    .dict-name { font:600 10.5px/1.3 -apple-system; letter-spacing:.12em; text-transform:uppercase; color:var(--muted);
                 margin-bottom:5px; display:flex; align-items:center; gap:7px; }
    .dict-name::before { content:""; width:10px; height:1.5px; background:var(--shu); flex:none; }
    ol.gloss { margin:0; padding-left:1.4em; }
    ol.gloss > li { margin:1px 0 5px; }
    ol.gloss > li::marker { color:var(--muted); font-size:.8em; font-variant-numeric:tabular-nums; }
    .gloss.inline .g { display:inline-block; max-width:100%; vertical-align:top; }
    .gloss.inline .g:not(:last-child)::after { content:"|"; color:var(--muted); opacity:.55; margin-left:.45em; margin-right:.1em; }

    /* Words that start with what was typed: one line each, word · reading · meaning. */
    .starts { margin:2px 0 10px; }
    .start { display:flex; align-items:baseline; gap:10px; min-height:44px; padding:7px 0; box-sizing:border-box;
             border-bottom:1px solid var(--rule); color:var(--ink); }
    .start:last-child { border-bottom:none; }
    .start-word { font-family:var(--head-font); font-weight:700; font-size:1.25em; flex:none; }
    .start-reading { color:var(--muted); font-size:.82em; flex:none; }
    .start-gloss { color:var(--muted); font-size:.88em; flex:1; min-width:0; text-align:right;
                   white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }

    /* A kanji in its square of manuscript paper, readings and meanings beside it. */
    .kanji { display:flex; gap:16px; padding:14px 0 16px; border-bottom:1px solid var(--rule); }
    .kanji.more { padding-top:0; margin-top:-4px; }
    .kanji:last-of-type { border-bottom:none; }
    .kanji-glyph { flex:none; width:76px; height:76px; box-sizing:border-box; display:flex; align-items:center; justify-content:center;
                   font-family:var(--head-font); font-weight:700; font-size:52px; line-height:1; color:var(--ink);
                   border:1px solid var(--rule);
                   background:linear-gradient(var(--rule), var(--rule)) 50% 0 / 1px 100% no-repeat,
                              linear-gradient(var(--rule), var(--rule)) 0 50% / 100% 1px no-repeat;
                   -webkit-tap-highlight-color:transparent; }
    .kanji-glyph.blank { border-color:transparent; background:none; height:0; }
    .kanji-body { flex:1; min-width:0; }
    .yomi { display:grid; grid-template-columns:auto 1fr; gap:3px 10px; margin:0 0 6px; align-items:baseline; }
    .yomi dt { font:600 10.5px/1 -apple-system; color:var(--shu); border:1px solid color-mix(in srgb, var(--shu) 55%, transparent);
               border-radius:3px; padding:3px 3px 2px; }
    .yomi dd { margin:0; }
    .yomi dd > span { white-space:nowrap; }
    .yomi dd > i { display:inline-block; width:.9em; }
    .yomi .oku { color:var(--muted); }
    .kanji-meanings { margin:0 0 6px; }
    .kanji .meta { margin:0; }

    details.dict.closed > summary { list-style:none; cursor:pointer; }
    details.dict.closed > summary::-webkit-details-marker { display:none; }
    details.dict.closed > summary::after { content:"＋"; color:var(--shu); margin-left:2px; }
    details.dict.closed[open] > summary::after { content:"－"; }

    /* Compact: Yomitan's one numbered list, dictionary as a small label. */
    html.compact .entry { padding:14px 0 16px; }
    html.compact .headword { font-size:calc(var(--size) * 1.8); }
    html.compact ol.defs { margin:4px 0 0; padding-left:1.5em; }
    html.compact ol.defs > li { margin:0 0 6px; }
    html.compact ol.defs > li::marker { color:var(--muted); font-size:.8em; }
    html.compact .dict { margin:0; }
    html.compact .dict-pill { font:600 10px/1 -apple-system; padding:3px 6px; border-radius:4px; margin-right:6px;
                              color:var(--shu); background:color-mix(in srgb, var(--shu) 12%, transparent); vertical-align:2px; }
    html.compact .dict > .gloss { display:inline; }
    html.compact .dict > div.gloss { display:inline; }

    ul { padding-left:1.2em; margin:2px 0; }
    details { margin:3px 0; }
    summary { color:var(--shu); font-size:.92em; cursor:pointer; }
    table { border-collapse:collapse; margin:4px 0; }
    td, th { border:1px solid var(--rule); padding:2px 6px; }
    .gloss rt { font-size:.55em; }
    .sc-image { color:var(--muted); font-size:.85em; }
    .tapped { background:color-mix(in srgb, var(--shu) 20%, transparent); border-radius:3px; }
    """
}
