import SwiftUI

@main
struct KotobaApp: App {
    @State private var model = AppModel()
    @State private var hooker = HookerModel()
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
                TexthookerView(onSearch: { text in
                    model.pendingQuery = text
                    model.selectedTab = 0
                })
                    .tabItem { Label(tr("Dal PC"), systemImage: "desktopcomputer") }
                    .badge(hooker.unread)
                    .tag(4)
                WordsView()
                    .tabItem { Label(tr("Parole"), systemImage: "character.book.closed") }
                    .tag(5)
                SettingsView()
                    .tabItem { Label(tr("Impostazioni"), systemImage: "slider.horizontal.3") }
                    .tag(3)
            }
            .environment(model)
            .environment(hooker)
            .tint(Palette.shu)
            .preferredColorScheme(ThemePalette.colorScheme(for: model.settings.appearance.theme))
            // A new language rebuilds the screens so every word follows it. A new
            // theme does not need to: colours are read through ThemeStore, and the
            // screens that used one repaint in place, keeping what was open.
            .id(model.settings.language)
            .onOpenURL { url in
                model.handle(url: url)
            }
            .onAppear {
                QuickAction.handler = { [model] action in model.perform(action) }
                hooker.readings = { [store = model.store] kanji in
                    (store?.entryHeaders(matching: kanji) ?? []).map(\.reading).filter { !$0.isEmpty }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.becameActive() }
                // iOS stops the network in the background: let go, and reconnect on return.
                if phase == .active { hooker.setActive(true) }
                if phase == .background {
                    hooker.setActive(false)
                    hooker.saveNow()
                }
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
