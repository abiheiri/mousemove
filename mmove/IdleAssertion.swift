import Foundation
import IOKit.pwr_mgt

/// Holds a `PreventUserIdleDisplaySleep` power assertion and an App Nap
/// activity token while mmove is enabled. This is the caffeinate(-d)
/// mechanism: even if synthetic input injection is blocked by security
/// software, the display cannot idle-sleep and the engine's timer is not
/// throttled.
final class IdleAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var activity: NSObjectProtocol?

    private(set) var isActive = false
    private(set) var creationFailed = false

    func start(reason: String = "mmove is keeping the display awake") {
        guard !isActive else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
            creationFailed = false
        } else {
            creationFailed = true
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: reason
        )
    }

    func stop() {
        if isActive {
            IOPMAssertionRelease(assertionID)
            isActive = false
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    deinit { stop() }

    /// Test hook to exercise the assertion-failed status text.
    func markCreationFailedForTesting() {
        creationFailed = true
    }
}
