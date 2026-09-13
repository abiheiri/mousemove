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
            if let countdown = engine.countdownText {
                // A static string updated by the engine's own 1s timer —
                // a live-updating Text(timerInterval:) here sends the
                // MenuBarExtra into a runaway update loop (100% CPU).
                Label {
                    Text(countdown)
                } icon: {
                    Image(systemName: "computermouse")
                }
            } else if settings.isEnabled {
                Label("On", systemImage: "computermouse")
            } else {
                Image(systemName: "computermouse")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
