import XCTest
@testable import mmove

final class IdleAssertionTests: XCTestCase {

    func testStartsInactive() {
        let assertion = IdleAssertion()
        XCTAssertFalse(assertion.isActive)
        XCTAssertFalse(assertion.creationFailed)
    }

    func testStartHoldsDisplaySleepAssertion() {
        let assertion = IdleAssertion()
        assertion.start()
        XCTAssertTrue(assertion.isActive)
        XCTAssertFalse(assertion.creationFailed)
        assertion.stop()
    }

    func testStopReleasesAssertion() {
        let assertion = IdleAssertion()
        assertion.start()
        assertion.stop()
        XCTAssertFalse(assertion.isActive)
    }

    func testStartIsIdempotent() {
        let assertion = IdleAssertion()
        assertion.start()
        assertion.start()
        XCTAssertTrue(assertion.isActive)
        assertion.stop()
    }

    func testStopWithoutStartIsHarmless() {
        let assertion = IdleAssertion()
        assertion.stop()
        XCTAssertFalse(assertion.isActive)
    }

    func testSuccessfulStartClearsCreationFailed() {
        let assertion = IdleAssertion()
        assertion.markCreationFailedForTesting()
        assertion.start()
        XCTAssertTrue(assertion.isActive)
        XCTAssertFalse(assertion.creationFailed)
        assertion.stop()
    }
}
