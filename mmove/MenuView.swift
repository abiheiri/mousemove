import SwiftUI

/// Content of the menu bar extra: status, time-left line, pause/resume,
/// settings submenu (frequency and runtime limit), version, and quit.
struct MenuView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: JiggleEngine

    /// The running app's marketing version, e.g. "1.0.0".
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    var body: some View {
        Text(engine.statusText)
        if let remaining = engine.remainingSeconds {
            Text("Time left: \(Self.formatRemaining(remaining))")
        }

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

            Divider()

            Menu("Run for") {
                Button {
                    settings.runtimeLimitMinutes = 0
                } label: {
                    if settings.runtimeLimitMinutes == 0 {
                        Label("No limit", systemImage: "checkmark")
                    } else {
                        Text("No limit")
                    }
                }
                ForEach(SettingsStore.runtimePresets, id: \.self) { minutes in
                    Button {
                        settings.runtimeLimitMinutes = minutes
                    } label: {
                        if minutes == settings.runtimeLimitMinutes {
                            Label(runtimeLabel(for: minutes), systemImage: "checkmark")
                        } else {
                            Text(runtimeLabel(for: minutes))
                        }
                    }
                }
                Button {
                    showCustomLimitPanel()
                } label: {
                    if isCustomLimitActive {
                        Label("Custom (\(settings.runtimeLimitMinutes) min)", systemImage: "checkmark")
                    } else {
                        Text("Custom…")
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

    private var isCustomLimitActive: Bool {
        settings.runtimeLimitMinutes != 0
            && !SettingsStore.runtimePresets.contains(settings.runtimeLimitMinutes)
    }

    private func runtimeLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    /// MenuBarExtra menus can't host a live text field, so the custom entry
    /// is collected in a modal panel. Invalid input (non-numeric, out of
    /// 1...1440) leaves the setting unchanged.
    private func showCustomLimitPanel() {
        let alert = NSAlert()
        alert.messageText = "Custom runtime limit"
        alert.informativeText = "Minutes mmove stays on before pausing (1–\(SettingsStore.maxCustomMinutes))."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(settings.customMinutes)
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(trimmed), SettingsStore.isValidLimit(minutes), minutes > 0 else { return }
        settings.customMinutes = minutes
        settings.runtimeLimitMinutes = minutes
    }

    /// "2 h 5 min" / "42 min"; rounds up so the line never reads "0 min".
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 1)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}
