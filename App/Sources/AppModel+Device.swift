#if !KOTOBA_EXTENSION
import UIKit
import Photos
import KotobaCore

/// The parts of the model that need the phone itself: the clipboard and the
/// photo library. Kept out of AppModel.swift so that file stays testable.
extension AppModel {
    /// Called every time Kotoba comes to the front.
    func becameActive() {
        // The share panel may have changed settings (words sent to Anki).
        // Settings that cannot be read leave the ones in use alone.
        if let saved = AppSettings.saved(), saved != settings { settings = saved }
        if let action = QuickAction.takePending() {
            perform(action)
            return
        }
        if settings.clipboardLookup, searchClipboard(force: false) { return }
        if settings.screenshotLookup { openRecentScreenshot() }
    }

    func perform(_ action: QuickAction) {
        switch action {
        case .clipboard:
            searchClipboard(force: true)
        case .lens:
            cameraRequest = .lens
            selectedTab = 1
        }
    }

    private static let clipboardKey = "lastClipboardChange"

    /// Searches the clipboard if it holds Japanese text copied since last time
    /// (or always, when asked by a shortcut). Returns whether it searched.
    @discardableResult
    func searchClipboard(force: Bool) -> Bool {
        let board = UIPasteboard.general
        let defaults = UserDefaults.standard
        // changeCount can be read without the paste permission prompt.
        guard force || board.changeCount != defaults.integer(forKey: Self.clipboardKey) else { return false }
        defaults.set(board.changeCount, forKey: Self.clipboardKey)
        guard board.hasStrings else {
            if force { toast = tr("Negli appunti non c'è testo") }
            return false
        }
        let text = (board.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= (force ? 300 : 80), force || Kana.containsJapanese(text) else {
            if force { toast = tr("Negli appunti non c'è testo") }
            return false
        }
        pendingQuery = text
        selectedTab = 0
        toast = tr("Dagli appunti")
        return true
    }

    private static let screenshotKey = "lastScreenshotSeen"

    /// Opens a screenshot taken in the last two minutes that you haven't seen in Kotoba yet.
    func openRecentScreenshot() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited, let asset = Self.latestScreenshot(),
              let date = asset.creationDate, Date().timeIntervalSince(date) < 120,
              UserDefaults.standard.string(forKey: Self.screenshotKey) != asset.localIdentifier else { return }
        UserDefaults.standard.set(asset.localIdentifier, forKey: Self.screenshotKey)
        cameraRequest = .screenshot(asset.localIdentifier)
        selectedTab = 1
    }

    nonisolated static func latestScreenshot() -> PHAsset? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: options).firstObject
    }

    /// What only the phone knows, for the diagnostics page.
    static var deviceFacts: [(name: String, value: String)] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
        return [
            ("Device", model),
            ("iOS", UIDevice.current.systemVersion),
        ]
    }
}
#endif
