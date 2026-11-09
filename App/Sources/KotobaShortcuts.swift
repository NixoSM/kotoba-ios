import AppIntents

/// Kotoba's actions in the Shortcuts app and Siri, with no setup needed.
struct KotobaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SearchClipboardIntent(),
                    phrases: ["Cerca gli appunti in \(.applicationName)", "Search clipboard in \(.applicationName)"],
                    shortTitle: "Cerca appunti",
                    systemImageName: "doc.on.clipboard")
        AppShortcut(intent: OpenLensIntent(),
                    phrases: ["Apri la lente di \(.applicationName)", "Open \(.applicationName) lens"],
                    shortTitle: "Lente",
                    systemImageName: "camera.viewfinder")
    }
}
