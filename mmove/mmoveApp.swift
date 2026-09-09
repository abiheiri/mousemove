import SwiftUI

@main
struct MMoveApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var engine: JiggleEngine

    init() {
        let store = SettingsStore()
        let engine = JiggleEngine(settings: store)
        _settings = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: engine)
        engine.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings, engine: engine)
        } label: {
            Image(systemName: "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}
