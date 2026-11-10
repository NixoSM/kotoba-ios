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
        let c = context.coordinator
        c.onAction = onAction
        guard c.lastHTML != html else { return }
        c.lastHTML = html
        // Same page, new results: swap them in place. Reloading the page would
        // make WebKit fetch and decode the fonts (up to 8 MB each) every search.
        if let parts = Self.split(html), parts.shell == c.loadedShell,
           let json = try? JSONSerialization.data(withJSONObject: parts.body, options: .fragmentsAllowed),
           let literal = String(data: json, encoding: .utf8) {
            let script = "(function(h){var m=document.getElementById('kotoba-results');if(!m)return false;m.innerHTML=h;window.scrollTo(0,0);return true;})(\(literal))"
            view.evaluateJavaScript(script) { [weak view] result, _ in
                guard (result as? Bool) != true, let view, c.lastHTML == html else { return }
                c.load(html, in: view)
            }
            return
        }
        c.load(html, in: view)
    }

    /// The page without its results, and the results.
    static func split(_ html: String) -> (shell: String, body: String)? {
        guard let open = html.range(of: ResultsPage.bodyOpen),
              let close = html.range(of: ResultsPage.bodyClose, options: .backwards),
              open.upperBound <= close.lowerBound else { return nil }
        return (String(html[..<open.upperBound]) + String(html[close.lowerBound...]),
                String(html[open.upperBound..<close.lowerBound]))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onAction: (URL) -> Void
        var lastHTML = ""
        /// The page around the results that is on screen, once it has loaded.
        var loadedShell: String?
        private var loadingShell: String?

        init(onAction: @escaping (URL) -> Void) { self.onAction = onAction }

        func load(_ html: String, in view: WKWebView) {
            loadedShell = nil
            loadingShell = ResultsWebView.split(html)?.shell
            view.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadedShell = loadingShell
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS reclaimed the page's memory: draw it again instead of staying blank.
            loadedShell = nil
            load(lastHTML, in: webView)
        }

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
    static let scheme = MediaLink.scheme

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        if let url = task.request.url, url.host == "font" {
            let file = url.lastPathComponent
            // Mapped, not copied: the file stays on disk and only the pages WebKit reads come in.
            guard let fileURL = FontCatalog.fileURL(file), let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
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
              let data = MediaLink.store?.media(dictionary: dictionary, path: path) else {
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
