import Combine
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Periodically posts a synthetic mouseMoved event at the cursor's current
/// position to reset the system idle timer (keeps the screensaver off and
/// presence-aware apps like Slack active). Never posts while the user is
/// actively typing or moving the mouse. Event posting needs no Accessibility
/// permission. A held IdleAssertion guarantees display sleep stays off even
/// if security software blocks the synthetic events; a post-and-verify
/// self-check detects that case and exposes it as `injectionBlocked`.
@MainActor
final class JiggleEngine: ObservableObject {
    private let settings: SettingsStore
    private let assertion: IdleAssertion
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    /// Bumped on every lifecycle change (stop/reschedule) so a pending
    /// verifyInjection asyncAfter can tell it is stale and bail out.
    private var generation = 0

    /// True when the self-check proved synthetic events are not resetting the
    /// idle timer (e.g. blocked by EDR/policy). The power assertion still
    /// protects against display sleep in that state.
    @Published private(set) var injectionBlocked = false

    /// True when the runtime window elapsed and the engine paused itself.
    /// Cleared on the next resume, which starts a fresh window.
    @Published private(set) var timeLimitReached = false

    /// When the current runtime window expires (nil when stopped or no
    /// limit). Published so the menu bar label can render a countdown.
    @Published private(set) var windowEnd: Date?

    /// When the current window started (nil when stopped or no limit).
    /// Read by MenuView for the "Time left" line.
    private(set) var startedAt: Date?
    private var deadlineTimer: Timer?

    // Injectable seams for tests.
    var readIdle: () -> TimeInterval = JiggleEngine.secondsSinceLastInput
    var readCursor: () -> CGPoint? = { CGEvent(source: nil)?.location }
    var postEvent: (CGPoint) -> Void = JiggleEngine.postMouseMoved
    var verifyDelay: TimeInterval = 0.75

    /// The interval the current timer is scheduled with (0 when stopped).
    /// Exposed for tests.
    private(set) var currentInterval: TimeInterval = 0

    /// The interval the deadline timer is armed with (0 when no limit or
    /// stopped). Exposed for tests.
    private(set) var deadlineInterval: TimeInterval = 0

    /// Injectable seam for tests: minutes -> seconds until expiry.
    var limitInterval: (Int) -> TimeInterval = { TimeInterval($0 * 60) }

    init(settings: SettingsStore, assertion: IdleAssertion = IdleAssertion()) {
        self.settings = settings
        self.assertion = assertion
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
        generation += 1
        timer?.invalidate()
        timer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        startedAt = nil
        windowEnd = nil
        timeLimitReached = false
        currentInterval = 0
        injectionBlocked = false
        assertion.stop()
    }

    /// Pure decision: post only when enabled and the user has been idle
    /// at least one full frequency interval.
    nonisolated static func shouldJiggle(isEnabled: Bool, idleSeconds: TimeInterval, frequencySeconds: Int) -> Bool {
        isEnabled && idleSeconds >= TimeInterval(frequencySeconds)
    }

    /// Pure decision: did posting our synthetic event reset the idle timer?
    /// A reset drops idle time to near zero; anything above half the previous
    /// reading is treated as "kept counting" (i.e. injection was blocked or
    /// swallowed).
    nonisolated static func idleWasReset(idleBefore: TimeInterval, idleAfter: TimeInterval) -> Bool {
        idleAfter < idleBefore / 2
    }

    var statusText: String {
        if !settings.isEnabled && timeLimitReached { return "Paused — time limit reached" }
        if !settings.isEnabled { return "mmove is off" }
        if injectionBlocked && assertion.creationFailed { return "mmove is on (protection unavailable on this Mac)" }
        if injectionBlocked { return "mmove is on (input blocked — display-only mode)" }
        if assertion.creationFailed { return "mmove is on (display sleep not blocked)" }
        return "mmove is on"
    }

    /// Seconds left in the current runtime window; nil when there is no
    /// limit or the engine is paused.
    var remainingSeconds: TimeInterval? {
        guard settings.isEnabled, let startedAt, deadlineInterval > 0 else { return nil }
        return max(0, deadlineInterval - Date().timeIntervalSince(startedAt))
    }

    /// Test hook to exercise the degraded status without faking the timer.
    func markInjectionBlockedForTesting() {
        injectionBlocked = true
    }

    private func reschedule() {
        generation += 1
        timer?.invalidate()
        timer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        startedAt = nil
        windowEnd = nil
        guard settings.isEnabled else {
            currentInterval = 0
            assertion.stop()
            return
        }
        timeLimitReached = false
        assertion.start()
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
        armDeadline()
    }

    /// Arms the one-shot deadline timer when a runtime limit is set.
    private func armDeadline() {
        let limit = settings.runtimeLimitMinutes
        guard limit > 0 else { return }
        let startedAt = Date()
        self.startedAt = startedAt
        let deadline = limitInterval(limit)
        deadlineInterval = deadline
        windowEnd = startedAt.addingTimeInterval(deadline)
        let generation = self.generation
        let timer = Timer(timeInterval: deadline, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Bail if the engine stopped or rescheduled since this
                // deadline was armed.
                guard let self, self.generation == generation else { return }
                self.expireWindow()
            }
        }
        // Allow coalescing, but never more than a minute late.
        timer.tolerance = min(deadline * 0.05, 60)
        RunLoop.main.add(timer, forMode: .default)
        deadlineTimer = timer
    }

    /// Ends the runtime window: pause via the normal isEnabled path (stops
    /// the jiggle timer and releases the power assertion so the Mac idles
    /// naturally) and flag the expiry for the status text. Internal (not
    /// private) so tests can drive it directly.
    func expireWindow() {
        guard settings.isEnabled else { return }
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        windowEnd = nil
        timeLimitReached = true
        settings.isEnabled = false
    }

    /// Internal (not private) so tests can drive a tick directly.
    func tick() {
        let idleBefore = readIdle()
        guard Self.shouldJiggle(isEnabled: settings.isEnabled,
                                idleSeconds: idleBefore,
                                frequencySeconds: settings.frequencySeconds) else { return }
        // caffeinate -u equivalent: declare user activity to the power system.
        Self.declareUserActivity()
        guard let cursor = readCursor() else { return }
        // Zero-delta post: cursor does not move, but the HID system sees input.
        postEvent(cursor)
        verifyInjection(idleBefore: idleBefore, isRetry: false, cursor: cursor)
    }

    private func verifyInjection(idleBefore: TimeInterval, isRetry: Bool, cursor: CGPoint) {
        let generation = self.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + verifyDelay) { [weak self] in
            Task { @MainActor in
                // Bail if the engine stopped or rescheduled since this verify
                // was queued — a stale verify must not post or mutate state.
                guard let self, self.generation == generation else { return }
                // A real user input event landing inside the verify window
                // also resets the idle timer and classifies as "working" —
                // an acceptable false negative, since user activity means
                // the machine isn't idle anyway.
                let idleAfter = self.readIdle()
                if Self.idleWasReset(idleBefore: idleBefore, idleAfter: idleAfter) {
                    self.injectionBlocked = false
                } else if !isRetry {
                    // Zero-delta posts are dropped by some environments; retry
                    // once with a +1 px then back pair.
                    self.postEvent(CGPoint(x: cursor.x + 1, y: cursor.y))
                    self.postEvent(cursor)
                    self.verifyInjection(idleBefore: idleBefore, isRetry: true, cursor: cursor)
                } else {
                    self.injectionBlocked = true
                }
            }
        }
    }

    /// Seconds since the last keyboard/mouse/HID input system-wide.
    static func secondsSinceLastInput() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)! // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    /// Post a synthetic mouseMoved at `point` to the HID and session taps.
    /// No Accessibility permission required.
    static func postMouseMoved(at point: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
        event.post(tap: .cgSessionEventTap)
    }

    static func declareUserActivity() {
        var assertionID = IOPMAssertionID(0)
        IOPMAssertionDeclareUserActivity("mmove user activity" as CFString,
                                         kIOPMUserActiveLocal,
                                         &assertionID)
    }
}
