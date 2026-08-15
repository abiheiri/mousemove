import SwiftUI

/// Content of the menu bar extra: status, pause/resume, frequency
/// settings submenu, version, and quit.
struct MenuView: View {
    @ObservedObject var settings: SettingsStore

    /// The running app's marketing version, e.g. "1.0.0".
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    var body: some View {
        Text(settings.isEnabled ? "mmove is on" : "mmove is off")

        Button(settings.isEnabled ? "Pause" : "Resume") {
            settings.isEnabled.toggle()
        }

        Menu("Settings") {
            ForEach(SettingsStore.frequencyPresets, id: \.self) { seconds in
                Button {
                    settings.frequencySeconds = seconds
                } label: {
                    if seconds == settings.frequencySeconds {
                        Label(label(for: seconds), systemImage: "checkmark")
                    } else {
                        Text(label(for: seconds))
                    }
                }
            }
        }

        Divider()

        Text("mmove \(Self.appVersion)")

        Divider()

        Button("Quit mmove") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func label(for seconds: Int) -> String {
        if seconds < 60 { return "Every \(seconds) seconds" }
        let minutes = seconds / 60
        return minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
    }
}
