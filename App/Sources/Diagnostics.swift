import Foundation

/// A short diary of what the app did and what went wrong, kept on the phone.
///
/// Kotoba is sideloaded: no crash reports reach anyone, and there is no Mac to
/// plug the phone into. When something misbehaves, this is what can be copied
/// from Impostazioni › Diagnostica and pasted into a message.
final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()

    static let limit = 300
    private let lock = NSLock()
    private var lines: [String] = []
    /// "app" or "share": two programs write the same diary.
    var source = "app"

    private var file: URL { SharedStorage.folder.appendingPathComponent("diagnostics.log") }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Call while holding the lock. The file is read every time: the share
    /// panel is another program writing the same diary, and a copy kept in
    /// memory here would write over its lines with this program's next one.
    private func load() {
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            lines = Array(text.split(separator: "\n").map(String.init).suffix(Self.limit))
        } else if !FileManager.default.fileExists(atPath: file.path) {
            lines = []
        }
    }

    /// What was already written in this launch by `logOnce`.
    private var saidOnce: Set<String> = []

    /// For what would otherwise repeat at every keystroke: written the first
    /// time only. Says whether this was the first time.
    @discardableResult
    func logOnce(_ message: String) -> Bool {
        lock.lock()
        let new = saidOnce.insert(message).inserted
        lock.unlock()
        if new { log(message) }
        return new
    }

    func log(_ message: String, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        load()
        // One line per event, so the diary stays a list.
        let flat = message.replacingOccurrences(of: "\n", with: " ⏎ ")
        lines.append("\(Self.stamp.string(from: date)) [\(source)] \(flat)")
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Oldest first.
    var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        load()
        return lines
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines = []
        try? FileManager.default.removeItem(at: file)
    }
}

/// Everything worth knowing about this install, as text to copy.
struct DiagnosticsReport {
    var facts: [(name: String, value: String)]
    var log: [String]

    var text: String {
        var out = "Kotoba\n"
        for fact in facts { out += "\(fact.name): \(fact.value)\n" }
        out += "\n" + (log.isEmpty ? "(log empty)" : log.joined(separator: "\n")) + "\n"
        return out
    }
}

/// When the app's signature runs out.
///
/// Signed with a free Apple ID, the app opens for seven days; after that iOS
/// refuses to launch it until it is installed again with Sideloadly (the
/// dictionaries stay). The date is written in the profile inside the app.
enum SigningInfo {
    /// The expiry date in an `embedded.mobileprovision` file: a signed
    /// envelope around a property list.
    static func expiry(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// This install's expiry; nil when the app carries no profile (the simulator, or a store build).
    static let current: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expiry(inProfile: data)
    }()

    enum Notice: Equatable {
        case none
        /// Whole days left, 0 meaning "today".
        case soon(days: Int)
        case expired
    }

    /// Worth a warning from two days before.
    static func notice(expiry: Date?, now: Date = Date()) -> Notice {
        guard let expiry else { return .none }
        let seconds = expiry.timeIntervalSince(now)
        if seconds <= 0 { return .expired }
        let days = Int(seconds / 86_400)
        return days <= 2 ? .soon(days: days) : .none
    }
}
