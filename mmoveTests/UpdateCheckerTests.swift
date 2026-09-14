import XCTest
@testable import mmove

final class UpdateCheckerTests: XCTestCase {
    // MARK: - Version comparison

    func testEqualVersions() {
        XCTAssertEqual(UpdateChecker.compare("1.3.2", "1.3.2"), .orderedSame)
    }

    func testVPrefixIsIgnored() {
        XCTAssertEqual(UpdateChecker.compare("v1.4.0", "1.4.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compare("V1.4.0", "1.4.0"), .orderedSame)
    }

    func testPatchOrdering() {
        XCTAssertEqual(UpdateChecker.compare("1.3.3", "1.3.2"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compare("1.3.2", "1.3.3"), .orderedAscending)
    }

    func testNumericNotLexicographic() {
        // Lexicographic comparison would wrongly say "1.10.0" < "1.3.2".
        XCTAssertEqual(UpdateChecker.compare("1.10.0", "1.3.2"), .orderedDescending)
    }

    func testMajorOrdering() {
        XCTAssertEqual(UpdateChecker.compare("2.0.0", "1.9.9"), .orderedDescending)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(UpdateChecker.compare("1.4", "1.4.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compare("1.4.1", "1.4"), .orderedDescending)
    }
}
