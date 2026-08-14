import Foundation

/// Persists user settings in UserDefaults and publishes changes.
final class SettingsStore: ObservableObject {
    /// Allowed jiggle frequencies, in seconds.
    static let frequencyPresets = [15, 30, 60, 120, 300]
    static let defaultFrequency = 60

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let frequencySeconds = "frequencySeconds"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var frequencySeconds: Int {
        didSet { defaults.set(frequencySeconds, forKey: Keys.frequencySeconds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.frequencySeconds: Self.defaultFrequency,
        ])
        let stored = defaults.integer(forKey: Keys.frequencySeconds)
        self.frequencySeconds = Self.frequencyPresets.contains(stored) ? stored : Self.defaultFrequency
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
    }
}
