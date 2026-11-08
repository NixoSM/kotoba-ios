import SwiftUI
import WebKit

/// Shows the results HTML. Links to other entries run a new search;
/// web links open in Safari.
struct ResultsWebView: UIViewRepresentable {
    let html: String
    let onSearch: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSearch: onSearch) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.keyboardDismissMode = .onDrag
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onSearch = onSearch
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSearch: (String) -> Void
        var lastHTML = ""

        init(onSearch: @escaping (String) -> Void) { self.onSearch = onSearch }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, action.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "kotoba", url.host == "search",
               let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value {
                onSearch(q)
            } else if url.scheme == "https" || url.scheme == "http" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
