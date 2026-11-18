import Foundation

/// Gathers lines that arrive close together so they reach the screen at once.
///
/// When the phone comes back after a while, Kotoba's Textractor extension sends
/// every line it missed, one WebSocket message each, a few milliseconds apart.
/// Handed over one by one, each would scroll the page with its own animation and
/// the newest line, the one you came back for, would show up last. With this,
/// a burst lands as one batch; a single live line waits only `quiet`.
public struct HookBurst<Item> {
    /// A batch goes out when nothing new came for this long…
    public var quiet: TimeInterval
    /// …or when the oldest item in it has waited this long, so a steady stream
    /// still shows up.
    public var maxWait: TimeInterval

    public private(set) var pending: [Item] = []
    private var firstAt: TimeInterval = 0
    private var lastAt: TimeInterval = 0

    public init(quiet: TimeInterval = 0.06, maxWait: TimeInterval = 0.2) {
        self.quiet = quiet
        self.maxWait = maxWait
    }

    /// Adds an item that arrived at `now` (seconds, any clock that only goes
    /// forward) and returns when the batch should go out.
    @discardableResult
    public mutating func add(_ item: Item, at now: TimeInterval) -> TimeInterval {
        if pending.isEmpty { firstAt = now }
        lastAt = now
        pending.append(item)
        return deadline!
    }

    /// When the batch should go out; nil when nothing waits.
    public var deadline: TimeInterval? {
        guard !pending.isEmpty else { return nil }
        return min(lastAt + quiet, firstAt + maxWait)
    }

    /// The batch, if its time has come at `now`, and empties it.
    public mutating func take(at now: TimeInterval) -> [Item]? {
        guard let deadline, now >= deadline else { return nil }
        return takeAll()
    }

    /// Everything waiting, whatever the time (the connection is closing).
    public mutating func takeAll() -> [Item] {
        defer { pending = [] }
        return pending
    }
}
