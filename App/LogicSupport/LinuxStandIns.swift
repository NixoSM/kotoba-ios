import Foundation

// Stand-ins for the pieces of the app that need an iPhone, so the rest of its
// logic (search, the results page, settings, imports) compiles and is tested
// on Linux by the package at the root of the repository. Never part of the app.

/// The app keeps its files in an App Group folder; the tests use a scratch folder.
enum SharedStorage {
    nonisolated(unsafe) static var folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-logic-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    nonisolated(unsafe) static var defaults: UserDefaults = UserDefaults(suiteName: "kotoba-logic-tests-\(UUID().uuidString)") ?? .standard

    static let databaseName = "dictionaries.sqlite"
    nonisolated(unsafe) static var groupID: String?

    static func migrateToSharedFolder() -> URL { folder }
}

/// The app opens AnkiMobile; the tests look at what would have been opened.
@MainActor
enum URLOpener {
    static var opened: [URL] = []
    static var succeeds = true

    static func open(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        opened.append(url)
        completion?(succeeds)
    }
}

/// The app keeps the screen on and asks iOS for background time; the tests
/// count the calls and can play the moment that time runs out.
@MainActor
enum LongWork {
    private(set) static var running = 0
    private(set) static var begun = 0
    private static var expiryHandlers: [@MainActor () -> Void] = []

    static func begin(onExpiry: @escaping @MainActor () -> Void) {
        running += 1
        begun += 1
        expiryHandlers.append(onExpiry)
    }

    static func end() {
        guard running > 0 else { return }
        running -= 1
        if running == 0 { expiryHandlers = [] }
    }

    /// iOS is about to suspend the app.
    static func simulateExpiry() {
        let handlers = expiryHandlers
        expiryHandlers = []
        for handler in handlers { handler() }
    }
}
