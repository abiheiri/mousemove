# Update Checker + macOS Support Range Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual "Check for Updates…" menu item that queries the GitHub Releases API and offers to download a newer release, and document the supported macOS range (13 Ventura through 27) in the README.

**Architecture:** New `UpdateChecker` struct in `mmove/UpdateChecker.swift` with a pure static version comparator and an injectable async fetch (no network in tests). `MenuView` gains a menu button that runs the check and reports via `NSAlert`, matching the existing custom-limit panel pattern. Docs updated in README and CHANGELOG.

**Tech Stack:** Swift 5, SwiftUI (`MenuBarExtra`), AppKit (`NSAlert`, `NSWorkspace`), Foundation (`URLSession`, `JSONSerialization`), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-14-update-checker-design.md`

**Project notes:**
- The Xcode project uses file-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files added under `mmove/` and `mmoveTests/` are picked up automatically. Do NOT edit `project.pbxproj`.
- Run tests with:
  `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'`
- The test bundle is hosted in the app process (`TEST_HOST`), so `Bundle.main` inside tests is the mmove app itself.

---

### Task 1: Version comparator (pure, TDD)

**Files:**
- Test: `mmoveTests/UpdateCheckerTests.swift`
- Create: `mmove/UpdateChecker.swift`

- [ ] **Step 1: Write the failing test**

Create `mmoveTests/UpdateCheckerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD FAILED with "cannot find 'UpdateChecker' in scope"

- [ ] **Step 3: Write minimal implementation**

Create `mmove/UpdateChecker.swift`:

```swift
import Foundation

/// Checks GitHub for a newer mmove release.
struct UpdateChecker {
    /// Component-wise numeric version comparison. A leading "v"/"V" is
    /// ignored, missing components count as 0, so "v1.4.0" == "1.4.0",
    /// "1.4" == "1.4.0", and "1.10.0" > "1.3.2".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = components(a), pb = components(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Test Suite 'UpdateCheckerTests' passed

- [ ] **Step 5: Commit**

```bash
git add mmove/UpdateChecker.swift mmoveTests/UpdateCheckerTests.swift
git commit -m "Add version comparator for update checking"
```

---

### Task 2: GitHub release fetch + check result mapping (TDD)

**Files:**
- Modify: `mmove/UpdateChecker.swift`
- Test: `mmoveTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `UpdateCheckerTests` in `mmoveTests/UpdateCheckerTests.swift`:

```swift
    // MARK: - Check result mapping

    /// Minimal GitHub /releases/latest response body.
    private func releaseJSON(tag: String, url: String = "https://github.com/abiheiri/mousemove/releases/tag/\(tag)") -> Data {
        Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)"}"#.utf8)
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
        XCTAssertEqual(await checker.check(), .upToDate)
    }

    func testOlderReleaseYieldsUpToDate() async {
        var checker = UpdateChecker()
        checker.currentVersion = "1.3.2"
        checker.fetchData = { _ in self.releaseJSON(tag: "v1.2.0") }
        XCTAssertEqual(await checker.check(), .upToDate)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD FAILED — `UpdateChecker` has no member `check`, no `fetchData`, etc.

- [ ] **Step 3: Implement the fetch and check**

Replace the contents of `mmove/UpdateChecker.swift` with:

```swift
import Foundation

/// Checks GitHub for a newer mmove release.
struct UpdateChecker {
    /// A newer release than the one running.
    struct LatestRelease: Equatable {
        let version: String
        let url: URL
    }

    enum CheckResult: Equatable {
        case updateAvailable(LatestRelease)
        case upToDate
        case failed(String)
    }

    private static let releasesURL = URL(string: "https://api.github.com/repos/abiheiri/mousemove/releases/latest")!

    /// The running app's marketing version, e.g. "1.3.2".
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Injectable for tests: returns the response body for the releases URL.
    var fetchData: (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Version to compare against; injectable for tests.
    var currentVersion: String = UpdateChecker.appVersion

    /// Queries the latest GitHub release and compares it to currentVersion.
    func check() async -> CheckResult {
        do {
            let data = try await fetchData(Self.releasesURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let urlString = json["html_url"] as? String,
                  let url = URL(string: urlString) else {
                return .failed("Unexpected response from GitHub")
            }
            let latest = String(tag.drop(while: { $0 == "v" || $0 == "V" }))
            guard Self.compare(latest, currentVersion) == .orderedDescending else {
                return .upToDate
            }
            return .updateAvailable(LatestRelease(version: latest, url: url))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Component-wise numeric version comparison. A leading "v"/"V" is
    /// ignored, missing components count as 0, so "v1.4.0" == "1.4.0",
    /// "1.4" == "1.4.0", and "1.10.0" > "1.3.2".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = components(a), pb = components(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: Test Suite 'UpdateCheckerTests' passed; all other suites still pass.

- [ ] **Step 5: Commit**

```bash
git add mmove/UpdateChecker.swift mmoveTests/UpdateCheckerTests.swift
git commit -m "Check latest GitHub release and map to update result"
```

---

### Task 3: Menu item + alert UI

**Files:**
- Modify: `mmove/MenuView.swift`

- [ ] **Step 1: Point MenuView.appVersion at UpdateChecker.appVersion**

In `mmove/MenuView.swift`, replace the `appVersion` computed property:

```swift
    /// The running app's marketing version, e.g. "1.0.0".
    static var appVersion: String {
        UpdateChecker.appVersion
    }
```

- [ ] **Step 2: Add the "Check for Updates…" button and alert handler**

In `mmove/MenuView.swift`, replace this existing block:

```swift
        Divider()

        Text("mmove \(Self.appVersion)")
```

with:

```swift
        Button("Check for Updates…") {
            Task { await checkForUpdates() }
        }

        Divider()

        Text("mmove \(Self.appVersion)")
```

(The final tail of the menu is: `Button("Check for Updates…")`, `Divider()`, `Text("mmove …")`, `Divider()`, `Button("Quit mmove")`.)

Add the handler as a private method next to `showCustomLimitPanel()`:

```swift
    /// Manual update check. Results are shown in a modal alert, the same
    /// pattern as the custom-limit panel, since MenuBarExtra menus can't
    /// host live UI.
    @MainActor
    private func checkForUpdates() async {
        let result = await UpdateChecker().check()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        switch result {
        case .updateAvailable(let release):
            alert.messageText = "mmove \(release.version) is available"
            alert.informativeText = "You're running \(Self.appVersion)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.url)
            }
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "mmove \(Self.appVersion) is the latest version."
            alert.runModal()
        case .failed(let reason):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = reason
            alert.runModal()
        }
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: all suites pass.

- [ ] **Step 5: Manual verification**

Run the app locally (`xcodebuild ... build` output app, or from Xcode) and click "Check for Updates…". Because local builds use `MARKETING_VERSION = 1.0.0` from the project (CI overrides it from the tag at release time), the check should report the latest published release as available; clicking Download must open the release page in the browser. Also verify the failure path by turning off Wi-Fi/network and confirming the "Couldn't check for updates" alert appears.

- [ ] **Step 6: Commit**

```bash
git add mmove/MenuView.swift
git commit -m "Add Check for Updates menu item with download prompt"
```

---

### Task 4: Document supported macOS range + changelog

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README**

In `README.md`, add a Requirements section immediately before the `## Build` section:

```markdown
## Requirements

- macOS 13 Ventura or later — supported through macOS 27. The minimum is
  set by SwiftUI's MenuBarExtra, which powers the entire menu bar UI.
- Apple Silicon (arm64)
```

And in the `## Usage` list, add a bullet after the "Run for" bullet:

```markdown
- **Check for Updates…**: compares the running version against the latest
  GitHub release and offers to open the download page when a newer one
  exists.
```

- [ ] **Step 2: Update CHANGELOG**

In `CHANGELOG.md`, insert the following immediately above the `## [1.3.2] - 2026-09-13` line:

```markdown
## [Unreleased]

### Added

- "Check for Updates…" menu item: checks the latest GitHub release and
  offers to open the download page when a newer version exists.
- README documents the supported macOS range: macOS 13 Ventura (the
  minimum, required by MenuBarExtra) through macOS 27.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document supported macOS range (13–27) and update checker"
```

---

### Task 5: Final verification

- [ ] **Step 1: Full clean test run**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' 2>&1 | tail -15`
Expected: all test suites pass (IdleAssertion, JiggleEngine, SettingsStore, UpdateChecker).

- [ ] **Step 2: Release build**

Run: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Release build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED
