import SwiftUI
import WebKit

/// Shows the results HTML. kotoba:// links (other entries, the mine button)
/// go to `onAction`; web links open in Safari.
struct ResultsWebView: UIViewRepresentable {
    let html: String
    let onAction: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onAction: onAction) }

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
            guard let url = action.request.url, action.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "kotoba" {
                onAction(url)
            } else if url.scheme == "https" || url.scheme == "http" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
