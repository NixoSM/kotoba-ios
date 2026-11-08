import SwiftUI

@main
struct KotobaApp: App {
    @State private var model = AppModel()
    @State private var tab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                SearchView()
                    .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
                    .tag(0)
                CameraView(onLookup: { text in
                    model.pendingQuery = text
                    tab = 0
                })
                    .tabItem { Label("Fotocamera", systemImage: "viewfinder") }
                    .tag(1)
                DictionariesView()
                    .tabItem { Label("Dizionari", systemImage: "square.stack.3d.up") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("Impostazioni", systemImage: "slider.horizontal.3") }
                    .tag(3)
            }
            .environment(model)
            .onOpenURL { url in
                model.handle(url: url)
                if url.host == "search" { tab = 0 }
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { model.toast = nil }
                        }
                }
            }
            .animation(.snappy, value: model.toast)
            .alert("Kotoba", isPresented: Binding(
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
