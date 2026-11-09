import SwiftUI
import WebKit
import KotobaCore

/// Shows the results HTML. kotoba:// links (other entries, the mine button)
/// go to `onAction`; web links open in Safari.
struct ResultsWebView: UIViewRepresentable {
    let html: String
    let onAction: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onAction: onAction) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MediaSchemeHandler.shared, forURLScheme: MediaSchemeHandler.scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.keyboardDismissMode = .onDrag
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onAction = onAction
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onAction: (URL) -> Void
        var lastHTML = ""

        init(onAction: @escaping (URL) -> Void) { self.onAction = onAction }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            // kotoba:// comes from links and from the tap-to-look-up script.
            if url.scheme == "kotoba" {
                onAction(url)
                return decisionHandler(.cancel)
            }
            if action.navigationType == .linkActivated {
                if url.scheme == "https" || url.scheme == "http" { Task { @MainActor in URLOpener.open(url) } }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}

/// Serves images stored inside dictionaries to the results page.
final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = MediaSchemeHandler()
    static let scheme = "kotoba-media"
    /// Set once at launch.
    nonisolated(unsafe) static var store: DictionaryStore?

    /// A font file, bundled or added by the user.
    static func fontURL(_ file: String) -> String {
        scheme + "://font/" + (file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file)
    }

    static func url(dictionary: String, path: String) -> String {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "m"
        c.queryItems = [URLQueryItem(name: "d", value: dictionary), URLQueryItem(name: "p", value: path)]
        return c.string ?? ""
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        if let url = task.request.url, url.host == "font" {
            let file = url.lastPathComponent
            guard let fileURL = FontCatalog.fileURL(file), let data = try? Data(contentsOf: fileURL) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let mime = file.lowercased().hasSuffix(".otf") ? "font/otf" : "font/ttf"
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
            return
        }
        guard let url = task.request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let dictionary = items.first(where: { $0.name == "d" })?.value,
              let path = items.first(where: { $0.name == "p" })?.value,
              let data = Self.store?.media(dictionary: dictionary, path: path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = switch (path as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        case "avif": "image/avif"
        default: "application/octet-stream"
        }
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
