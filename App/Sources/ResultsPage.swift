import Foundation
import KotobaCore

/// Builds the HTML page that shows search results. Definitions are HTML so
/// that each dictionary's own structure and stylesheet survive.
enum ResultsPage {
    static func html(outcome: AppModel.SearchOutcome, query: String, stylesheets: [String: String], indexStatus: String?,
                     mined: Set<String>, canMine: Bool) -> String {
        var body = ""
        if let reading = outcome.romajiReading, !outcome.direct.isEmpty {
            body += section("Letto come \(reading)")
        }
        for (i, g) in outcome.direct.enumerated() {
            body += entry(g, link: canMine ? "kotoba://mine?s=direct&i=\(i)" : nil, mined: mined.contains(g.minedKey))
        }
        if !outcome.byMeaning.isEmpty {
            body += section("Parole che significano «\(query.trimmingCharacters(in: .whitespaces))»")
            if let indexStatus { body += "<p class=\"note\">\(GlossaryHTML.escape(indexStatus))</p>" }
            for (i, g) in outcome.byMeaning.enumerated() {
                body += entry(g, link: canMine ? "kotoba://mine?s=meaning&i=\(i)" : nil, mined: mined.contains(g.minedKey))
            }
        }
        let dictionaryCSS = stylesheets.map { title, css in
            GlossaryHTML.scopedCSS(css, scope: "[data-dict=\"\(scopeID(title))\"]")
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>\(baseCSS)</style>
        <style>\(dictionaryCSS)</style>
        </head><body>\(body)</body></html>
        """
    }

    private static func section(_ text: String) -> String {
        "<h2 class=\"section\">\(GlossaryHTML.escape(text))</h2>"
    }

    private static func entry(_ g: HeadwordGroup, link: String?, mined: Bool) -> String {
        var html = "<article class=\"entry\"><header>"
        if let link {
            html += mined
                ? "<a class=\"mine done\" href=\"\(link)\" aria-label=\"Già in Anki\">✓</a>"
                : "<a class=\"mine\" href=\"\(link)\" aria-label=\"Aggiungi ad Anki\">＋</a>"
        }
        html += "<h1 class=\"headword\" lang=\"ja\">\(Furigana.html(expression: g.expression, reading: g.reading))</h1>"
        if !g.reasons.isEmpty {
            let chain = g.reasons.map(\.italianLabel).joined(separator: " › ")
            html += "<div class=\"chain\">\(GlossaryHTML.escape(g.matchedText)) · \(GlossaryHTML.escape(chain))</div>"
        }
        html += metaRow(g)
        html += "</header>"
        for def in g.definitions {
            html += "<section class=\"dict\" data-dict=\"\(scopeID(def.dictionary))\">"
            html += "<div class=\"dict-name\">\(GlossaryHTML.escape(def.dictionary))</div>"
            if def.items.count == 1 {
                html += "<div class=\"gloss single\">\(def.items[0])</div>"
            } else {
                html += "<ol class=\"gloss\">" + def.items.map { "<li>\($0)</li>" }.joined() + "</ol>"
            }
            html += "</section>"
        }
        return html + "</article>"
    }

    /// Pitch accent drawing and frequency tags, Yomitan's "split tags" style.
    private static func metaRow(_ g: HeadwordGroup) -> String {
        var html = ""
        let pitch = PitchHTML.list(g.pitches, reading: g.reading)
        if !pitch.isEmpty { html += "<div class=\"pitches\" lang=\"ja\">\(pitch)</div>" }
        if !g.frequencies.isEmpty {
            html += "<div class=\"freqs\">" + g.frequencies.map {
                "<span class=\"freq\"><span class=\"freq-name\">\(GlossaryHTML.escape($0.dictionary))</span>\(GlossaryHTML.escape($0.display))</span>"
            }.joined() + "</div>"
        }
        return html
    }

    /// Short stable id for a dictionary title, safe inside a CSS selector.
    static func scopeID(_ title: String) -> String {
        var hash: UInt64 = 5381
        for b in title.utf8 { hash = (hash &* 33) ^ UInt64(b) }
        return "d" + String(hash, radix: 36)
    }

    private static let baseCSS = """
    :root { color-scheme: light dark; --fg:#1b1b1d; --muted:#7a7a80; --rule:#d9d9de; --accent:#c2410c; --bg:transparent; }
    @media (prefers-color-scheme: dark) { :root { --fg:#f2f2f4; --muted:#8e8e93; --rule:#3a3a3c; --accent:#fb923c; } }
    html { -webkit-text-size-adjust: 100%; }
    body { margin:0; padding:12px 20px 120px; background:var(--bg); color:var(--fg);
           font: 17px/1.45 -apple-system, "Hiragino Sans", sans-serif; }
    .section { font: 600 13px -apple-system; color:var(--muted); margin:18px 0 6px; text-transform:none; }
    .note { font-size:12px; color:var(--muted); margin:0 0 12px; }
    .entry { margin: 0 0 30px; }
    header { position:relative; }
    .headword { font: 600 40px/1.25 "Hiragino Mincho ProN", serif; margin:0 0 6px; padding-right:52px; }
    .headword rt { font: 400 13px "Hiragino Mincho ProN", serif; color:var(--muted); letter-spacing:.05em; }
    .mine { position:absolute; right:0; top:10px; width:40px; height:40px; border-radius:20px;
            display:flex; align-items:center; justify-content:center; font-size:22px;
            border:1px solid var(--rule); color:var(--accent); }
    .mine.done { color:var(--muted); }
    .pitches { font-size:15px; margin:2px 0 6px; }
    .pitches ol { margin:0; padding-left:1.3em; }
    .pitch { letter-spacing:.02em; }
    .freqs { display:flex; flex-wrap:wrap; gap:6px; margin:4px 0 8px; }
    .freq { font-size:12px; border:1px solid var(--rule); border-radius:6px; padding:1px 6px; }
    .freq-name { color:var(--muted); margin-right:6px; }
    .chain { font: 12px ui-monospace, Menlo, monospace; color:var(--accent); margin-bottom:10px; }
    .dict { border-left:2px solid var(--rule); padding-left:12px; margin:12px 0 0 2px; }
    .dict-name { font: 600 11px -apple-system; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); margin-bottom:4px; }
    ol.gloss { margin:0; padding-left:1.4em; }
    ol.gloss > li { margin:2px 0 6px; }
    ol.gloss > li::marker { color:var(--muted); font-size:.8em; }
    ul { padding-left:1.2em; margin:2px 0; }
    details { margin:4px 0; }
    summary { color:var(--accent); font-size:.9em; cursor:pointer; }
    table { border-collapse:collapse; margin:4px 0; }
    td, th { border:1px solid var(--rule); padding:2px 6px; }
    a { color:var(--accent); text-decoration:none; }
    .gloss rt { font-size:.55em; }
    .sc-image { color:var(--muted); font-size:.85em; }
    """
}
