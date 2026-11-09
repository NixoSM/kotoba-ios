import UIKit
import UniformTypeIdentifiers

/// "Kotoba" in the Share sheet: takes the selected text and opens it in the app's search.
/// It shows no screen of its own; it just hands the text over and closes.
final class ShareViewController: UIViewController {
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await forward() }
    }

    private func forward() async {
        guard let text = await sharedText(),
              var components = URLComponents(string: "kotoba://search") else { return finish() }
        components.queryItems = [URLQueryItem(name: "q", value: String(text.prefix(300)))]
        guard let url = components.url, openContainingApp(url) else { return finish() }
    }

    private func sharedText() async -> String? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    let text = (value as? String) ?? (value as? NSAttributedString)?.string
                    if let text = cleaned(text) { return text }
                }
            }
            if let text = cleaned(item.attributedContentText?.string) { return text }
        }
        return nil
    }

    private func cleaned(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// Extensions may not open apps directly, but the UIApplication further up
    /// the responder chain can (this is why the target allows non-extension APIs).
    private func openContainingApp(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in self?.finish() }
                return true
            }
            responder = current.next
        }
        return false
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
