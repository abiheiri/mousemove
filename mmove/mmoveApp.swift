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
                // MenuBarExtra shows only one label element: a Label with a
                // systemImage drops its title. An inline symbol inside a
                // single Text is the reliable way to get icon + text.
                // The string itself comes from the engine's 1s timer — a
                // live-updating Text(timerInterval:) here sends the
                // MenuBarExtra into a runaway update loop (100% CPU).
                Text("\(Image(systemName: "computermouse")) \(countdown)")
            } else if settings.isEnabled {
                Text("\(Image(systemName: "computermouse")) On")
            } else {
                Image(systemName: "computermouse")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
