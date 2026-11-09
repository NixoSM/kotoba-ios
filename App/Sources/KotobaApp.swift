import SwiftUI

@main
struct KotobaApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            @Bindable var model = model
            TabView(selection: $model.selectedTab) {
                SearchView()
                    .tabItem { Label(tr("Cerca"), systemImage: "magnifyingglass") }
                    .tag(0)
                CameraView(onLookup: { text in
                    model.pendingQuery = text
                    model.selectedTab = 0
                })
                    .tabItem { Label(tr("Fotocamera"), systemImage: "text.viewfinder") }
                    .tag(1)
                DictionariesView()
                    .tabItem { Label(tr("Dizionari"), systemImage: "books.vertical") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label(tr("Impostazioni"), systemImage: "slider.horizontal.3") }
                    .tag(3)
            }
            .environment(model)
            .tint(Palette.shu)
            .preferredColorScheme(ThemePalette.colorScheme(for: model.settings.appearance.theme))
            // Rebuild the screens so every colour and word follows a new theme or language.
            .id("\(model.settings.appearance.theme)|\(model.settings.language.rawValue)")
            .onOpenURL { url in
                model.handle(url: url)
            }
            .onAppear {
                QuickAction.handler = { [model] action in model.perform(action) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.becameActive() }
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
