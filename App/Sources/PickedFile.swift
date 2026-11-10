import Foundation

/// A file chosen in the Files app may only be read between `open` and `close`.
enum PickedFile {
    /// Returns whether `close` is owed.
    static func open(_ url: URL) -> Bool {
        #if canImport(Darwin)
        return url.startAccessingSecurityScopedResource()
        #else
        return false
        #endif
    }

    static func close(_ url: URL, opened: Bool) {
        #if canImport(Darwin)
        if opened { url.stopAccessingSecurityScopedResource() }
        #endif
    }
}

/// A switch one thread sets and another reads: "stop the import".
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}
