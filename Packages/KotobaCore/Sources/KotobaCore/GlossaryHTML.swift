import Foundation

/// Renders a Yomitan glossary as safe HTML, keeping the dictionary's own
/// structure: lists, tables, ruby, collapsible <details>, and the `data-sc-*`
/// attributes that dictionary stylesheets (styles.css) target.
public enum GlossaryHTML {
    /// One HTML fragment per glossary item. `mediaURL` turns an image path
    /// from the dictionary into a URL the web view can load; without it,
    /// images show their description.
    public static func items(fromJSON data: Data, mediaURL: ((String) -> String)? = nil) -> [String] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return array.map { item in
            var r = Renderer(mediaURL: mediaURL)
            r.render(item)
            return r.out
        }.filter { !$0.isEmpty }
    }

    private struct Renderer {
        let mediaURL: ((String) -> String)?
        var out = ""

        mutating func render(_ node: Any) {
            GlossaryHTML.render(node, into: &out, media: mediaURL)
        }
    }

    private static let allowedTags: Set<String> = [
        "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
        "span", "div", "ol", "ul", "li", "details", "summary", "br", "a", "img",
    ]

    fileprivate static func render(_ node: Any, into out: inout String, media: ((String) -> String)?) {
        switch node {
        case let s as String:
            out += escape(s).replacingOccurrences(of: "\n", with: "<br>")
        case let array as [Any]:
            array.forEach { render($0, into: &out, media: media) }
        case let object as [String: Any]:
            if let type = object["type"] as? String {
                switch type {
                case "text": out += escape(object["text"] as? String ?? ""); return
                case "structured-content": render(object["content"] ?? "", into: &out, media: media); return
                case "image": renderImage(object, into: &out, media: media); return
                default: break
                }
            }
            guard let tag = object["tag"] as? String, allowedTags.contains(tag) else {
                if let content = object["content"] { render(content, into: &out, media: media) }
                return
            }
            switch tag {
            case "br": out += "<br>"
            case "img": renderImage(object, into: &out, media: media)
            case "a": renderLink(object, into: &out, media: media)
            default:
                out += "<\(tag)\(attributes(object))>"
                if let content = object["content"] { render(content, into: &out, media: media) }
                out += "</\(tag)>"
            }
        default:
            break
        }
    }

    /// Images are stored in the dictionary zip; until media import exists we
    /// show their description instead of a broken picture.
    private static func renderImage(_ object: [String: Any], into out: inout String, media: ((String) -> String)?) {
        let label = (object["title"] as? String) ?? (object["alt"] as? String) ?? (object["description"] as? String) ?? "immagine"
        guard let media, let path = object["path"] as? String else {
            out += "<span class=\"sc-image\">[\(escape(label))]</span>"
            return
        }
        let units = (object["sizeUnits"] as? String) == "em" ? "em" : "px"
        var style = ""
        if let w = (object["preferredWidth"] ?? object["width"]) as? NSNumber { style += "width:\(w)\(units);" }
        if let h = (object["preferredHeight"] ?? object["height"]) as? NSNumber, style.isEmpty { style += "height:\(h)\(units);" }
        if (object["verticalAlign"] as? String) != nil || units == "em" { style += "vertical-align:middle;" }
        out += "<img class=\"sc-img\" src=\"\(escape(media(path)))\" alt=\"\(escape(label))\" style=\"\(style)max-width:100%\">"
    }

    private static func renderLink(_ object: [String: Any], into out: inout String, media: ((String) -> String)?) {
        let href = object["href"] as? String ?? ""
        // "?query=…" links point to another dictionary entry: route them to our own search.
        var target = href
        if href.hasPrefix("?"), let q = queryParameter(href) {
            target = "kotoba://search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)
        } else if !(href.hasPrefix("https://") || href.hasPrefix("http://")) {
            target = ""
        }
        out += target.isEmpty ? "<span>" : "<a href=\"\(escape(target))\">"
        if let content = object["content"] { render(content, into: &out, media: media) }
        out += target.isEmpty ? "</span>" : "</a>"
    }

    private static func queryParameter(_ href: String) -> String? {
        for pair in href.dropFirst().split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "query" {
                let raw = String(parts[1])
                return raw.removingPercentEncoding ?? raw
            }
        }
        return nil
    }

    private static func attributes(_ object: [String: Any]) -> String {
        var attrs = ""
        if let data = object["data"] as? [String: Any] {
            for (key, value) in data.sorted(by: { $0.key < $1.key }) {
                // The name goes into the page as written, so it must be a plain
                // name: "x onclick=…" would otherwise become a second attribute.
                let name = kebab(key)
                guard isPlainName(name) else { continue }
                attrs += " data-sc-\(name)=\"\(escape("\(value)"))\""
            }
        }
        if let lang = object["lang"] as? String { attrs += " lang=\"\(escape(lang))\"" }
        if let title = object["title"] as? String { attrs += " title=\"\(escape(title))\"" }
        if let open = object["open"] as? Bool, open { attrs += " open" }
        for key in ["colSpan", "rowSpan"] {
            if let n = object[key] as? NSNumber { attrs += " \(key.lowercased())=\"\(n.intValue)\"" }
        }
        if let style = object["style"] as? [String: Any] {
            let css = style.sorted(by: { $0.key < $1.key }).compactMap { key, value -> String? in
                let v = cssValue(value)
                let name = kebab(key)
                guard !v.isEmpty, isPlainName(name), !loadsRemoteContent(v) else { return nil }
                return "\(name):\(v)"
            }.joined(separator: ";")
            if !css.isEmpty { attrs += " style=\"\(escape(css))\"" }
        }
        return attrs
    }

    private static func cssValue(_ value: Any) -> String {
        switch value {
        case let s as String: return s.replacingOccurrences(of: ";", with: "")
        case let n as NSNumber: return "\(n)em" // Yomitan numeric sizes are in em
        case let a as [Any]: return a.map(cssValue).joined(separator: " ")
        default: return ""
        }
    }

    /// Letters, digits, "-" and "_" only: safe as an attribute or CSS property name.
    static func isPlainName(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "-" || $0 == "_"
        }
    }

    /// True when a piece of CSS would fetch something from outside the app:
    /// `url(…)` to anything but an embedded `data:` picture, or `image-set(…)`.
    /// A dictionary has no reason to, and a request per entry shown would tell
    /// a server which words are being looked up.
    static func loadsRemoteContent(_ css: String) -> Bool {
        let text = unescapedCSS(css).lowercased()
        if text.contains("image-set(") || text.contains("@import") { return true }
        var rest = Substring(text)
        while let found = rest.range(of: "url(") {
            let argument = rest[found.upperBound...].drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\"" || $0 == "'" }
            if !argument.hasPrefix("data:") { return true }
            rest = rest[found.upperBound...]
        }
        return false
    }

    /// CSS with its backslash escapes resolved ("\75 rl(" is "url(" to a browser).
    private static func unescapedCSS(_ css: String) -> String {
        guard css.contains("\\") else { return css }
        var out = ""
        var i = css.startIndex
        while i < css.endIndex {
            let c = css[i]
            i = css.index(after: i)
            guard c == "\\", i < css.endIndex else { out.append(c); continue }
            var hex = ""
            while i < css.endIndex, hex.count < 6, css[i].isHexDigit {
                hex.append(css[i])
                i = css.index(after: i)
            }
            if hex.isEmpty {
                out.append(css[i]) // "\(" is just "("
                i = css.index(after: i)
            } else {
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) }
                if i < css.endIndex, css[i] == " " { i = css.index(after: i) } // one space ends the escape
            }
        }
        return out
    }

    static func kebab(_ s: String) -> String {
        var out = ""
        for c in s {
            if c.isUppercase { out += "-" + c.lowercased() } else { out.append(c) }
        }
        return out
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Prefixes every selector of a dictionary stylesheet so it only applies
    /// inside that dictionary's block, the same isolation Yomitan provides.
    ///
    /// The result is safe to put inside a `<style>` element: it cannot close
    /// the element (no "<" survives) and rules that would fetch something from
    /// the network are left out.
    public static func scopedCSS(_ css: String, scope: String) -> String {
        scoped(stripComments(css), scope: scope).replacingOccurrences(of: "<", with: "\\3c ")
    }

    private static func scoped(_ css: String, scope: String) -> String {
        var out = ""
        var rest = Substring(css)
        while let open = rest.firstIndex(of: "{") {
            var selector = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            // "@import …;" and "@charset …;" have no block: drop them, keep the rule after.
            if let statementEnd = selector.lastIndex(of: ";") {
                selector = selector[selector.index(after: statementEnd)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Find the matching close brace (handles one level of nesting, e.g. @media).
            var depth = 0
            var close = open
            var i = open
            while i < rest.endIndex {
                if rest[i] == "{" { depth += 1 }
                if rest[i] == "}" { depth -= 1; if depth == 0 { close = i; break } }
                i = rest.index(after: i)
            }
            guard close > open else { break }
            let body = rest[rest.index(after: open)..<close]
            if selector.hasPrefix("@media") || selector.hasPrefix("@supports") {
                out += "\(selector){\(scoped(String(body), scope: scope))}"
            } else if !selector.hasPrefix("@"), !selector.isEmpty, !loadsRemoteContent(String(body)) {
                let scoped = selector.split(separator: ",")
                    .map { "\(scope) \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
                    .joined(separator: ",")
                out += "\(scoped){\(body)}"
            }
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    private static func stripComments(_ css: String) -> String {
        var s = css
        while let a = s.range(of: "/*") {
            let end = s.range(of: "*/", range: a.upperBound..<s.endIndex)?.upperBound ?? s.endIndex
            s.removeSubrange(a.lowerBound..<end)
        }
        return s
    }
}
