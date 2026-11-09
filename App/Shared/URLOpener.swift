import UIKit

/// Opens a URL from the app or from an extension. Extensions are not given
/// UIApplication.shared; there the application is found up the responder
/// chain and its open method is called through the Objective-C runtime.
@MainActor
enum URLOpener {
    /// Set by the extension's view controller.
    static weak var responder: UIResponder?

    static func open(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        #if KOTOBA_EXTENSION
        var current = responder
        while let r = current, !(r is UIApplication) { current = r.next }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        guard let app = current, let method = app.method(for: selector) else {
            completion?(false)
            return
        }
        typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
        let call = unsafeBitCast(method, to: Open.self)
        let done: @convention(block) (Bool) -> Void = { opened in completion?(opened) }
        call(app, selector, url as NSURL, NSDictionary(), done)
        #else
        UIApplication.shared.open(url) { completion?($0) }
        #endif
    }
}
