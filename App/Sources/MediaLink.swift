import Foundation

/// Addresses of fonts and dictionary pictures inside the results page.
/// `MediaSchemeHandler` answers them; nothing here needs a screen.
enum MediaLink {
    static let scheme = "kotoba-media"

    /// A font file, bundled or added by the user.
    static func fontURL(_ file: String) -> String {
        scheme + "://font/" + (file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file)
    }

    /// A picture stored inside a dictionary.
    static func url(dictionary: String, path: String) -> String {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "m"
        c.queryItems = [URLQueryItem(name: "d", value: dictionary), URLQueryItem(name: "p", value: path)]
        return c.string ?? ""
    }
}
