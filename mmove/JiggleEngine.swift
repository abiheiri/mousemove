import Combine
import CoreGraphics
import Foundation

/// Periodically warps the cursor 1–2 px and back to reset the system idle
/// timer. Never jiggles while the user is actively typing or moving the
/// mouse. Uses CGWarpMouseCursorPosition, so no Accessibility permission
/// is required.
@MainActor
final class JiggleEngine {
    private let settings: SettingsStore
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?

    /// The interval the current timer is scheduled with (0 when stopped).
    /// Exposed for tests.
    private(set) var currentInterval: TimeInterval = 0

    init(settings: SettingsStore) {
        self.settings = settings
        // objectWillChange fires before the new value is stored; defer the
        // reschedule one runloop tick so we read the updated value.
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.reschedule() }
        }
    }

    func start() {
        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    /// Pure decision: jiggle only when enabled and the user has been idle
    /// at least one full frequency interval.
    nonisolated static func shouldJiggle(isEnabled: Bool, idleSeconds: TimeInterval, frequencySeconds: Int) -> Bool {
        isEnabled && idleSeconds >= TimeInterval(frequencySeconds)
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard settings.isEnabled else {
            currentInterval = 0
            return
        }
        let interval = TimeInterval(settings.frequencySeconds)
        currentInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // The closure is nonisolated; hop to the main actor for tick().
            Task { @MainActor in self?.tick() }
        }
        // Let macOS coalesce wakes; exact timing doesn't matter here.
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    private func tick() {
        guard Self.shouldJiggle(isEnabled: settings.isEnabled,
                                idleSeconds: Self.secondsSinceLastInput(),
                                frequencySeconds: settings.frequencySeconds) else { return }
        jiggle()
    }

    /// Seconds since the last keyboard/mouse/HID input system-wide.
    static func secondsSinceLastInput() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)! // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    private func jiggle() {
        guard let original = CGEvent(source: nil)?.location else { return }
        let dx = CGFloat(Int.random(in: 1...2) * (Bool.random() ? 1 : -1))
        let dy = CGFloat(Int.random(in: 1...2) * (Bool.random() ? 1 : -1))
        let target = CGPoint(x: original.x + dx, y: original.y + dy)
        // Keep the target at least 2 px inside the display bounds so the warp
        // can't fail/clamp at screen edges or trigger a hot corner — either
        // would break the warp-back guard and leave permanent drift. Stay in
        // Quartz display coordinates to match CGEvent.location.
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(original, 1, &display, &count) == .success, count > 0 else { return }
        let bounds = CGDisplayBounds(display).insetBy(dx: 2, dy: 2)
        let clamped = CGPoint(x: min(max(target.x, bounds.minX), bounds.maxX),
                              y: min(max(target.y, bounds.minY), bounds.maxY))
        CGWarpMouseCursorPosition(clamped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Warp back only if nothing else moved the cursor meanwhile.
            guard let now = CGEvent(source: nil)?.location, now == clamped else { return }
            CGWarpMouseCursorPosition(original)
        }
    }
}
