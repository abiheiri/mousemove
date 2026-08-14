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
}
