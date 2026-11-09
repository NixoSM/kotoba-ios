import AppIntents
import SwiftUI
import WidgetKit

/// Buttons for Control Center and the Lock Screen.
@main
struct KotobaWidgets: WidgetBundle {
    var body: some Widget {
        ClipboardControl()
        LensControl()
    }
}

struct ClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nixosm.kotoba.control.clipboard") {
            ControlWidgetButton(action: SearchClipboardIntent()) {
                Label("Cerca appunti", systemImage: "character.book.closed.ja")
            }
        }
        .displayName("Kotoba: cerca appunti")
        .description("Cerca in Kotoba il testo che hai copiato.")
    }
}

struct LensControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nixosm.kotoba.control.lens") {
            ControlWidgetButton(action: OpenLensIntent()) {
                Label("Lente", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Kotoba: lente")
        .description("Apre la fotocamera di Kotoba pronta a leggere.")
    }
}
