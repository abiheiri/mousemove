import SwiftUI

@main
struct MMoveApp: App {
    @StateObject private var settings: SettingsStore
    private let engine: JiggleEngine

    init() {
        let store = SettingsStore()
        _settings = StateObject(wrappedValue: store)
        let engine = JiggleEngine(settings: store)
        self.engine = engine
        engine.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings)
        } label: {
            Image(systemName: "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}
