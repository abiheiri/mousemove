import SwiftUI

/// Content of the menu bar extra: status, pause/resume, frequency
/// settings submenu, and quit.
struct MenuView: View {
    @ObservedObject var settings: SettingsStore

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
