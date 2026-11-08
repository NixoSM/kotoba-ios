import Foundation

/// Turns a Yomitan glossary (plain strings, `text` objects, `structured-content`
/// trees, images) into plain text. Used for the simple list view and for
/// indexing definitions so they can be searched in reverse (IT/EN → JP).
public enum GlossaryText {
    /// One string per glossary item.
    public static func items(fromJSON data: Data) -> [String] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return array.map { item in
            var out = ""
            flatten(item, into: &out)
            return tidy(out)
        }.filter { !$0.isEmpty }
    }

    private static let blockTags: Set<String> = ["div", "li", "ol", "ul", "tr", "table", "details", "summary", "p"]

    private static func flatten(_ node: Any, into out: inout String) {
        switch node {
        case let s as String:
            out += s
        case let array as [Any]:
            array.forEach { flatten($0, into: &out) }
        case let object as [String: Any]:
            if let type = object["type"] as? String {
                switch type {
                case "text": out += object["text"] as? String ?? ""; return
                case "image": return
                case "structured-content": flatten(object["content"] ?? "", into: &out); return
                default: break
                }
            }
            let tag = object["tag"] as? String ?? ""
            if tag == "br" { out += "\n"; return }
            if tag == "img" || tag == "rt" || tag == "rp" { return } // ruby readings would duplicate the text
            let isBlock = blockTags.contains(tag)
            if isBlock, !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
            if let content = object["content"] { flatten(content, into: &out) }
            if isBlock, !out.hasSuffix("\n") { out += "\n" }
        default:
            break
        }
    }

    private static func tidy(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
