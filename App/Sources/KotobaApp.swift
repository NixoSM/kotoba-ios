import SwiftUI

@main
struct KotobaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                SearchView()
                    .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
                DictionariesView()
                    .tabItem { Label("Dizionari", systemImage: "square.stack.3d.up") }
            }
            .environment(model)
            .alert("Attenzione", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
