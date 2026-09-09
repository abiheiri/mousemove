import XCTest
@testable import mmove

final class JiggleEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "JiggleEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Pure decision logic

    func testJigglesWhenIdleLongerThanFrequency() {
        XCTAssertTrue(JiggleEngine.shouldJiggle(isEnabled: true, idleSeconds: 61, frequencySeconds: 60))
    }

    func testSkipsWhenUserRecentlyActive() {
        XCTAssertFalse(JiggleEngine.shouldJiggle(isEnabled: true, idleSeconds: 5, frequencySeconds: 60))
    }

    func testNeverJigglesWhenDisabled() {
        XCTAssertFalse(JiggleEngine.shouldJiggle(isEnabled: false, idleSeconds: 9999, frequencySeconds: 60))
    }

    // MARK: - Idle-reset classification

    func testIdleWasResetWhenTimerDropsToNearZero() {
        XCTAssertTrue(JiggleEngine.idleWasReset(idleBefore: 60, idleAfter: 0.2))
    }

    func testIdleWasResetFalseWhenTimerKeepsCounting() {
        XCTAssertFalse(JiggleEngine.idleWasReset(idleBefore: 60, idleAfter: 65))
    }

    func testIdleWasResetRequiresSubstantialDrop() {
        // A read 0.75 s later during continuous activity is not a reset.
        XCTAssertFalse(JiggleEngine.idleWasReset(idleBefore: 40, idleAfter: 39.2))
    }

    // MARK: - Timer scheduling

    @MainActor
    func testStartSchedulesTimerWithFrequency() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertEqual(engine.currentInterval, 60)
        engine.stop()
    }

    @MainActor
    func testFrequencyChangeReschedulesTimer() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        store.frequencySeconds = 15
        // objectWillChange is observed and rescheduling is deferred one runloop tick.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(engine.currentInterval, 15)
        engine.stop()
    }

    @MainActor
    func testDisabledEngineSchedulesNothing() {
        defaults.set(false, forKey: "isEnabled")
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertEqual(engine.currentInterval, 0)
    }

    @MainActor
    func testStopClearsInterval() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.stop()
        XCTAssertEqual(engine.currentInterval, 0)
    }

    // MARK: - Synthetic input self-check

    @MainActor
    func testTickPostsZeroDeltaEventAndConfirmsInjection() async throws {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        var posted: [CGPoint] = []
        var idleValues: [TimeInterval] = [100, 0.1]
        engine.postEvent = { posted.append($0) }
        engine.readCursor = { CGPoint(x: 100, y: 100) }
        engine.readIdle = { idleValues.count > 1 ? idleValues.removeFirst() : idleValues[0] }
        engine.verifyDelay = 0.01
        engine.tick()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(posted, [CGPoint(x: 100, y: 100)])
        XCTAssertFalse(engine.injectionBlocked)
    }

    @MainActor
    func testTickRetriesWithOffsetPairThenConfirms() async throws {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        var posted: [CGPoint] = []
        // idle: 100 at tick, 100 at first verify (not reset), 0.1 at second verify.
        var idleValues: [TimeInterval] = [100, 100, 0.1]
        engine.postEvent = { posted.append($0) }
        engine.readCursor = { CGPoint(x: 100, y: 100) }
        engine.readIdle = { idleValues.count > 1 ? idleValues.removeFirst() : idleValues[0] }
        engine.verifyDelay = 0.01
        engine.tick()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(posted, [CGPoint(x: 100, y: 100), CGPoint(x: 101, y: 100), CGPoint(x: 100, y: 100)])
        XCTAssertFalse(engine.injectionBlocked)
    }

    @MainActor
    func testTickMarksInjectionBlockedWhenIdleNeverResets() async throws {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        var posted: [CGPoint] = []
        var idleValues: [TimeInterval] = [100, 100, 100]
        engine.postEvent = { posted.append($0) }
        engine.readCursor = { CGPoint(x: 100, y: 100) }
        engine.readIdle = { idleValues.count > 1 ? idleValues.removeFirst() : idleValues[0] }
        engine.verifyDelay = 0.01
        engine.tick()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(engine.injectionBlocked)
    }

    @MainActor
    func testTickSkipsWhenUserRecentlyActive() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        var posted: [CGPoint] = []
        engine.postEvent = { posted.append($0) }
        engine.readCursor = { CGPoint(x: 100, y: 100) }
        engine.readIdle = { 5 } // < frequency (60)
        engine.tick()
        XCTAssertTrue(posted.isEmpty)
    }

    @MainActor
    func testStartHoldsAssertionAndStopReleasesIt() {
        let store = SettingsStore(defaults: defaults)
        let assertion = IdleAssertion()
        let engine = JiggleEngine(settings: store, assertion: assertion)
        engine.start()
        XCTAssertTrue(assertion.isActive)
        engine.stop()
        XCTAssertFalse(assertion.isActive)
    }

    @MainActor
    func testDisabledEngineHoldsNoAssertion() {
        defaults.set(false, forKey: "isEnabled")
        let store = SettingsStore(defaults: defaults)
        let assertion = IdleAssertion()
        let engine = JiggleEngine(settings: store, assertion: assertion)
        engine.start()
        XCTAssertFalse(assertion.isActive)
    }

    @MainActor
    func testStatusText() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        XCTAssertEqual(engine.statusText, "mmove is on")
        store.isEnabled = false
        XCTAssertEqual(engine.statusText, "mmove is off")
        store.isEnabled = true
        engine.markInjectionBlockedForTesting()
        XCTAssertEqual(engine.statusText, "mmove is on (input blocked — display-only mode)")
    }

    @MainActor
    func testStatusTextShowsAssertionFailure() {
        let store = SettingsStore(defaults: defaults)
        let assertion = IdleAssertion()
        assertion.markCreationFailedForTesting()
        let engine = JiggleEngine(settings: store, assertion: assertion)
        XCTAssertEqual(engine.statusText, "mmove is on (display sleep not blocked)")
        engine.markInjectionBlockedForTesting()
        XCTAssertEqual(engine.statusText, "mmove is on (protection unavailable on this Mac)")
    }
}
