import Foundation

/// Renders a Yomitan glossary as safe HTML, keeping the dictionary's own
/// structure: lists, tables, ruby, collapsible <details>, and the `data-sc-*`
/// attributes that dictionary stylesheets (styles.css) target.
public enum GlossaryHTML {
    /// One HTML fragment per glossary item.
    public static func items(fromJSON data: Data) -> [String] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return array.map { item in
            var out = ""
            render(item, into: &out)
            return out
        }.filter { !$0.isEmpty }
    }

    private static let allowedTags: Set<String> = [
        "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
        "span", "div", "ol", "ul", "li", "details", "summary", "br", "a", "img",
    ]

    private static func render(_ node: Any, into out: inout String) {
        switch node {
        case let s as String:
            out += escape(s).replacingOccurrences(of: "\n", with: "<br>")
        case let array as [Any]:
            array.forEach { render($0, into: &out) }
        case let object as [String: Any]:
            if let type = object["type"] as? String {
                switch type {
                case "text": out += escape(object["text"] as? String ?? ""); return
                case "structured-content": render(object["content"] ?? "", into: &out); return
                case "image": renderImage(object, into: &out); return
                default: break
                }
            }
            guard let tag = object["tag"] as? String, allowedTags.contains(tag) else {
                if let content = object["content"] { render(content, into: &out) }
                return
            }
            switch tag {
            case "br": out += "<br>"
            case "img": renderImage(object, into: &out)
            case "a": renderLink(object, into: &out)
            default:
                out += "<\(tag)\(attributes(object))>"
                if let content = object["content"] { render(content, into: &out) }
                out += "</\(tag)>"
            }
        default:
            break
        }
    }

    /// Images are stored in the dictionary zip; until media import exists we
    /// show their description instead of a broken picture.
    private static func renderImage(_ object: [String: Any], into out: inout String) {
        let label = (object["title"] as? String) ?? (object["alt"] as? String) ?? (object["description"] as? String) ?? "immagine"
        out += "<span class=\"sc-image\">[\(escape(label))]</span>"
    }

    private static func renderLink(_ object: [String: Any], into out: inout String) {
        let href = object["href"] as? String ?? ""
        // "?query=…" links point to another dictionary entry: route them to our own search.
        var target = href
        if href.hasPrefix("?"), let q = queryParameter(href) {
            target = "kotoba://search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)
        } else if !(href.hasPrefix("https://") || href.hasPrefix("http://")) {
            target = ""
        }
        out += target.isEmpty ? "<span>" : "<a href=\"\(escape(target))\">"
        if let content = object["content"] { render(content, into: &out) }
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
                attrs += " data-sc-\(escape(kebab(key)))=\"\(escape("\(value)"))\""
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
                guard !v.isEmpty, !v.contains("url(") else { return nil }
                return "\(kebab(key)):\(v)"
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
    public static func scopedCSS(_ css: String, scope: String) -> String {
        var out = ""
        var rest = Substring(stripComments(css))
        while let open = rest.firstIndex(of: "{") {
            let selector = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
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
                out += "\(selector){\(scopedCSS(String(body), scope: scope))}"
            } else if !selector.hasPrefix("@") {
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
