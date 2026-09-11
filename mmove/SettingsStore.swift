import Foundation

/// Persists user settings in UserDefaults and publishes changes.
final class SettingsStore: ObservableObject {
    /// Allowed jiggle frequencies, in seconds.
    static let frequencyPresets = [15, 30, 60, 120, 300]
    static let defaultFrequency = 60
    /// Allowed runtime-limit presets, in minutes (2/4/6/8 hours).
    static let runtimePresets = [120, 240, 360, 480]
    /// Longest accepted custom limit, in minutes (24 h).
    static let maxCustomMinutes = 1440

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let frequencySeconds = "frequencySeconds"
        static let runtimeLimitMinutes = "runtimeLimitMinutes"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var frequencySeconds: Int {
        didSet { defaults.set(frequencySeconds, forKey: Keys.frequencySeconds) }
    }

    /// Minutes mmove stays on before pausing itself. 0 = no limit.
    @Published var runtimeLimitMinutes: Int {
        didSet { defaults.set(runtimeLimitMinutes, forKey: Keys.runtimeLimitMinutes) }
    }

    /// Last custom entry, used to pre-fill the Custom… panel. Not persisted.
    @Published var customMinutes = 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.frequencySeconds: Self.defaultFrequency,
            Keys.runtimeLimitMinutes: 0,
        ])
        let stored = defaults.integer(forKey: Keys.frequencySeconds)
        self.frequencySeconds = Self.frequencyPresets.contains(stored) ? stored : Self.defaultFrequency
        let storedLimit = defaults.integer(forKey: Keys.runtimeLimitMinutes)
        self.runtimeLimitMinutes = Self.isValidLimit(storedLimit) ? storedLimit : 0
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
    }

    static func isValidLimit(_ minutes: Int) -> Bool {
        (0...maxCustomMinutes).contains(minutes)
    }
}
