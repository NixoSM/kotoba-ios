import Foundation
import Observation
import UIKit
import KotobaCore

/// One line of the game's text, as it arrived and as you may have fixed it.
struct HookLine: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// What came from the PC before clean-up and edits.
    var original: String
    var date = Date()

    var edited: Bool { text != original }
}

/// What the texthooker remembers between launches.
struct HookerSettings: Codable, Equatable {
    /// The PC's address as typed (IP, or IP:port).
    var address = ""
    /// Off: the phone doesn't try to reach the PC.
    var enabled = false
    /// Listen for lines sent to the phone (clipboard script, browser page).
    var inbox = false
    var rules = HookText.Rules()
    /// Same line twice in a row (games often redraw a text box): keep one.
    var skipDuplicates = true
    /// The screen stays on while this tab is open.
    var keepAwake = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HookerSettings()
        address = (try? c.decodeIfPresent(String.self, forKey: .address)) ?? d.address
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        inbox = (try? c.decodeIfPresent(Bool.self, forKey: .inbox)) ?? d.inbox
        rules = (try? c.decodeIfPresent(HookText.Rules.self, forKey: .rules)) ?? d.rules
        skipDuplicates = (try? c.decodeIfPresent(Bool.self, forKey: .skipDuplicates)) ?? d.skipDuplicates
        keepAwake = (try? c.decodeIfPresent(Bool.self, forKey: .keepAwake)) ?? d.keepAwake
    }

    private static let key = "texthooker.v1"

    static func load() -> HookerSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(HookerSettings.self, from: data) else { return HookerSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Lines from the visual novel on the PC, live.
@MainActor
@Observable
final class HookerModel {
    private(set) var lines: [HookLine] = []
    private(set) var socketState = HookSocket.State.off
    private(set) var inboxState = HookInbox.State.off
    /// Lines that arrived while another tab was on screen.
    var unread = 0
    var isOnScreen = false { didSet { if isOnScreen { unread = 0 }; updateIdleTimer() } }
    private(set) var searching = false
    /// Failed tries in a row, to know when to suggest checking the setup.
    private(set) var failuresInARow = 0

    var settings = HookerSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.address != oldValue.address || settings.enabled != oldValue.enabled || settings.inbox != oldValue.inbox {
                applyConnections()
            }
            updateIdleTimer()
        }
    }

    /// Readings for the furigana clean-up, from the dictionaries.
    @ObservationIgnored var readings: (String) -> [String] = { _ in [] }

    private let socket = HookSocket()
    private let inbox = HookInbox()
    @ObservationIgnored private var active = true
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let maxLines = 1000

    init() {
        lines = Self.loadLines()
        socket.onState = { [weak self] state in
            guard let self else { return }
            self.socketState = state
            if case .retrying = state { self.failuresInARow += 1 }
            if state == .connected { self.failuresInARow = 0 }
        }
        socket.onText = { [weak self] raw in self?.receive(HookText.message(raw)) }
        inbox.onState = { [weak self] in self?.inboxState = $0 }
        inbox.onText = { [weak self] in self?.receive($0) }
        applyConnections()
    }

    var address: HookAddress? { HookAddress(settings.address) }

    // MARK: Connection

    /// Follows the app: nothing runs in the background, so on return it reconnects.
    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        applyConnections()
        updateIdleTimer()
    }

    private func applyConnections() {
        if active, settings.enabled, let address {
            socket.start(address)
        } else {
            socket.stop()
            failuresInARow = 0
        }
        if active, settings.inbox { inbox.start() } else { inbox.stop() }
    }

    func reconnect() {
        failuresInARow = 0
        if socketState == .off { applyConnections() } else { socket.reconnect() }
    }

    /// Scans the Wi-Fi for the PC and uses what it finds.
    func findPC() async -> Bool {
        searching = true
        defer { searching = false }
        let port = HookAddress(settings.address)?.port ?? HookAddress.defaultPort
        guard let host = await HookFinder.find(port: port) else { return false }
        settings.address = port == HookAddress.defaultPort ? host : "\(host):\(port)"
        settings.enabled = true
        return true
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = active && isOnScreen && settings.keepAwake
    }

    // MARK: Lines

    func receive(_ raw: String) {
        let text = HookText.clean(raw, rules: settings.rules, readings: readings)
        guard !text.isEmpty else { return }
        if settings.skipDuplicates, lines.last?.text == text { return }
        lines.append(HookLine(text: text, original: raw))
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        if !isOnScreen { unread += 1 }
        scheduleSave()
    }

    func update(_ line: HookLine, text: String) {
        guard let i = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { lines.remove(at: i) } else { lines[i].text = trimmed }
        scheduleSave()
    }

    func restore(_ line: HookLine) {
        guard let i = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[i].text = lines[i].original
        scheduleSave()
    }

    func delete(_ line: HookLine) {
        lines.removeAll { $0.id == line.id }
        scheduleSave()
    }

    func clear() {
        lines = []
        unread = 0
        scheduleSave()
    }

    /// The clean-up as it would treat this line now (for the edit screen).
    func cleaned(_ text: String) -> String {
        var rules = settings.rules
        rules.dropInlineFurigana = true
        rules.dropBracketReadings = true
        return HookText.clean(text, rules: rules, readings: readings)
    }

    // MARK: Saving

    nonisolated private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("texthooker-lines.json")
    }

    nonisolated private static func loadLines() -> [HookLine] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([HookLine].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = lines
        let url = Self.fileURL
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
            }.value
        }
    }

    /// Writes now (the app is leaving the screen).
    func saveNow() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(lines) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}
