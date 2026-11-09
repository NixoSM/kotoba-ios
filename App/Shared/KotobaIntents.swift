import AppIntents
import Foundation

/// Hands actions from Shortcuts, Control Center and the Lock Screen to the app.
enum QuickAction: String {
    case clipboard, lens

    private static let key = "pendingQuickAction"

    /// Called by the intents. If the app is listening, it acts right away;
    /// otherwise (cold launch, or run from an extension) it is kept for later.
    @MainActor
    static func send(_ action: QuickAction) {
        if let handler {
            handler(action)
        } else {
            SharedStorage.defaults.set(action.rawValue, forKey: key)
        }
    }

    @MainActor static var handler: ((QuickAction) -> Void)?

    /// The app collects a kept action when it becomes active.
    static func takePending() -> QuickAction? {
        guard let raw = SharedStorage.defaults.string(forKey: key) else { return nil }
        SharedStorage.defaults.removeObject(forKey: key)
        return QuickAction(rawValue: raw)
    }
}

struct SearchClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Cerca negli appunti"
    static var description = IntentDescription("Apre Kotoba e cerca il testo giapponese che hai copiato.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.send(.clipboard)
        return .result()
    }
}

struct OpenLensIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri la lente"
    static var description = IntentDescription("Apre Kotoba con la fotocamera pronta a leggere.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.send(.lens)
        return .result()
    }
}
