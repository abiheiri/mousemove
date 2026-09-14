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

    // MARK: - Check result mapping

    /// Minimal GitHub /releases/latest response body.
    private func releaseJSON(tag: String, url: String? = nil) -> Data {
        let url = url ?? "https://github.com/abiheiri/mousemove/releases/tag/\(tag)"
        return Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)"}"#.utf8)
    }

    func testNewerReleaseYieldsUpdateAvailable() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in self.releaseJSON(tag: "v1.4.0") }
        let result = await checker.check()
        XCTAssertEqual(result, .updateAvailable(UpdateChecker.LatestRelease(
            version: "1.4.0",
            url: URL(string: "https://github.com/abiheiri/mousemove/releases/tag/v1.4.0")!
        )))
    }

    func testSameReleaseYieldsUpToDate() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in self.releaseJSON(tag: "v1.3.2") }
        let result = await checker.check()
        XCTAssertEqual(result, .upToDate)
    }

    func testOlderReleaseYieldsUpToDate() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in self.releaseJSON(tag: "v1.2.0") }
        let result = await checker.check()
        XCTAssertEqual(result, .upToDate)
    }

    func testFetchFailureYieldsFailed() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in throw URLError(.notConnectedToInternet) }
        guard case .failed(let reason) = await checker.check() else {
            return XCTFail("expected .failed")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testMalformedJSONYieldsFailed() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in Data("not json".utf8) }
        guard case .failed = await checker.check() else {
            return XCTFail("expected .failed")
        }
    }

    func testMissingFieldsYieldFailed() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in Data(#"{"name": "no tag or url"}"#.utf8) }
        guard case .failed = await checker.check() else {
            return XCTFail("expected .failed")
        }
    }
}
