import UIKit

/// Work that must not be cut half-way: an import, deleting a dictionary.
///
/// While any is running the screen stays on. If you leave the app anyway, iOS
/// grants about half a minute more; just before that runs out it calls
/// `onExpiry`, so the work can stop tidily instead of being killed by the
/// system while it holds the database (which iOS punishes by closing the app).
@MainActor
enum LongWork {
    private static var running = 0
    private static var expiryHandlers: [@MainActor () -> Void] = []
    #if !KOTOBA_EXTENSION
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func begin(onExpiry: @escaping @MainActor () -> Void) {
        running += 1
        expiryHandlers.append(onExpiry)
        #if !KOTOBA_EXTENSION
        guard running == 1 else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Kotoba dictionaries") {
            // On the main thread, a few seconds before iOS suspends the app.
            // The task itself is ended by `end()` once the work has really
            // stopped, which follows within moments of asking.
            let handlers = expiryHandlers
            expiryHandlers = []
            for handler in handlers { handler() }
        }
        #endif
    }

    static func end() {
        guard running > 0 else { return }
        running -= 1
        guard running == 0 else { return }
        expiryHandlers = []
        #if !KOTOBA_EXTENSION
        UIApplication.shared.isIdleTimerDisabled = false
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        #endif
    }
}
