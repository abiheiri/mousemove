import XCTest
@testable import mmove

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreEnabledAndSixtySeconds() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.frequencySeconds, 60)
    }

    func testChangesPersistAcrossInstances() {
        let first = SettingsStore(defaults: defaults)
        first.isEnabled = false
        first.frequencySeconds = 15

        let second = SettingsStore(defaults: defaults)
        XCTAssertFalse(second.isEnabled)
        XCTAssertEqual(second.frequencySeconds, 15)
    }

    func testInvalidStoredFrequencyFallsBackToDefault() {
        defaults.set(42, forKey: "frequencySeconds")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.frequencySeconds, 60)
    }

    func testRuntimeLimitDefaultsToNoLimit() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.runtimeLimitMinutes, 0)
    }

    func testRuntimeLimitPersistsAcrossInstances() {
        let first = SettingsStore(defaults: defaults)
        first.runtimeLimitMinutes = 240

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.runtimeLimitMinutes, 240)
    }

    func testInvalidStoredRuntimeLimitFallsBackToNoLimit() {
        defaults.set(-5, forKey: "runtimeLimitMinutes")
        XCTAssertEqual(SettingsStore(defaults: defaults).runtimeLimitMinutes, 0)

        defaults.set(5000, forKey: "runtimeLimitMinutes")
        XCTAssertEqual(SettingsStore(defaults: defaults).runtimeLimitMinutes, 0)
    }
}
