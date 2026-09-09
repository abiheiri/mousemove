# Idle Prevention Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mmove actually keep the Mac awake and the user "active" in Slack by replacing the no-op cursor warp with synthetic HID input events plus a held `IOPMAssertion` power assertion, with runtime detection of EDR/policy blocking.

**Architecture:** `JiggleEngine.tick()` posts a synthetic zero-delta `mouseMoved` CGEvent to the HID event tap (resets the system idle timer that the screensaver and Electron/Slack observe) and calls `IOPMAssertionDeclareUserActivity` (caffeinate `-u` equivalent). A new `IdleAssertion` class holds `kIOPMAssertionTypePreventUserIdleDisplaySleep` and an App Nap activity token while enabled. A post-and-verify self-check classifies whether event injection is working; if blocked, the menu shows a degraded "display-only" state and the power assertion alone carries the load. All injection/idle reads go through injectable seams so the retry/block logic is unit-testable.

**Tech Stack:** Swift, SwiftUI (`MenuBarExtra`), CoreGraphics (`CGEvent`), IOKit power management (`IOPMAssertion*`), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-09-idle-prevention-design.md`

**Build/test commands:**
- Tests: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'`
- Build: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Release build`

---

### Task 1: Pure idle-reset classifier

**Files:**
- Modify: `mmove/JiggleEngine.swift`
- Test: `mmoveTests/JiggleEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `mmoveTests/JiggleEngineTests.swift`, inside the `// MARK: - Pure decision logic` section:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' -only-testing:mmoveTests/JiggleEngineTests`
Expected: FAIL — "type 'JiggleEngine' has no member 'idleWasReset'"

- [ ] **Step 3: Implement the classifier**

In `mmove/JiggleEngine.swift`, directly below `shouldJiggle` (line 42), add:

```swift
    /// Pure decision: did posting our synthetic event reset the idle timer?
    /// A reset drops idle time to near zero; anything above half the previous
    /// reading is treated as "kept counting" (i.e. injection was blocked or
    /// swallowed).
    nonisolated static func idleWasReset(idleBefore: TimeInterval, idleAfter: TimeInterval) -> Bool {
        idleAfter < idleBefore / 2
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' -only-testing:mmoveTests/JiggleEngineTests`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add mmove/JiggleEngine.swift mmoveTests/JiggleEngineTests.swift
git commit -m "Add idleWasReset classifier for synthetic-input self-check"
```

---

### Task 2: IdleAssertion (power assertion + App Nap guard)

**Files:**
- Create: `mmove/IdleAssertion.swift`
- Test: `mmoveTests/IdleAssertionTests.swift`
- Modify: `mmove.xcodeproj/project.pbxproj` (add both files to the app and test targets respectively)

- [ ] **Step 1: Write the failing tests**

Create `mmoveTests/IdleAssertionTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

The new file is not yet in the test target, so first add both new files to the project:

1. Open `mmove.xcodeproj` in Xcode, add `mmove/IdleAssertion.swift` (create an empty placeholder file first so Xcode accepts it) to the **mmove** target and `mmoveTests/IdleAssertionTests.swift` to the **mmoveTests** target; OR
2. Edit `mmove.xcodeproj/project.pbxproj` by hand, mirroring how `JiggleEngine.swift` / `JiggleEngineTests.swift` are registered (PBXBuildFile, PBXFileReference, group children, and the Sources build phase of the correct target).

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' -only-testing:mmoveTests/IdleAssertionTests`
Expected: FAIL — "cannot find 'IdleAssertion' in scope"

- [ ] **Step 3: Implement IdleAssertion**

Create `mmove/IdleAssertion.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' -only-testing:mmoveTests/IdleAssertionTests`
Expected: PASS (5 tests). `IOPMAssertionCreateWithName` succeeds from any
user process, so these tests pass in a normal test host.

- [ ] **Step 5: Commit**

```bash
git add mmove/IdleAssertion.swift mmoveTests/IdleAssertionTests.swift mmove.xcodeproj/project.pbxproj
git commit -m "Add IdleAssertion: held display-sleep assertion + App Nap guard"
```

---

### Task 3: Engine rewrite — synthetic events, self-check, assertion ownership

**Files:**
- Modify: `mmove/JiggleEngine.swift`
- Test: `mmoveTests/JiggleEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `mmoveTests/JiggleEngineTests.swift` a new section:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS' -only-testing:mmoveTests/JiggleEngineTests`
Expected: FAIL — compile errors: no member `postEvent`, `readCursor`, `readIdle`, `verifyDelay`, `tick`, `injectionBlocked`, `statusText`, `markInjectionBlockedForTesting`, extra argument `assertion` in init.

- [ ] **Step 3: Rewrite JiggleEngine**

Replace the entire contents of `mmove/JiggleEngine.swift` with:

```swift
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

    /// True when the self-check proved synthetic events are not resetting the
    /// idle timer (e.g. blocked by EDR/policy). The power assertion still
    /// protects against display sleep in that state.
    @Published private(set) var injectionBlocked = false

    // Injectable seams for tests.
    var readIdle: () -> TimeInterval = Self.secondsSinceLastInput
    var readCursor: () -> CGPoint? = { CGEvent(source: nil)?.location }
    var postEvent: (CGPoint) -> Void = Self.postMouseMoved
    var verifyDelay: TimeInterval = 0.75

    /// The interval the current timer is scheduled with (0 when stopped).
    /// Exposed for tests.
    private(set) var currentInterval: TimeInterval = 0

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
        timer?.invalidate()
        timer = nil
        currentInterval = 0
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
        if !settings.isEnabled { return "mmove is off" }
        if injectionBlocked && assertion.creationFailed { return "mmove is on (protection unavailable on this Mac)" }
        if injectionBlocked { return "mmove is on (input blocked — display-only mode)" }
        if assertion.creationFailed { return "mmove is on (display sleep not blocked)" }
        return "mmove is on"
    }

    /// Test hook to exercise the degraded status without faking the timer.
    func markInjectionBlockedForTesting() {
        injectionBlocked = true
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard settings.isEnabled else {
            currentInterval = 0
            assertion.stop()
            return
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + verifyDelay) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
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
```

Note: `import IOKit.pwr_mgt` is required for `IOPMAssertionDeclareUserActivity` / `kIOPMUserActiveLocal`. No new frameworks need linking — IOKit symbols are reachable via the implicit SDK linking for an app target; if the linker complains, add `IOKit.framework` to the mmove target's "Link Binary With Libraries" phase in `project.pbxproj`.

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'`
Expected: PASS — all tests including the pre-existing ones.

- [ ] **Step 5: Commit**

```bash
git add mmove/JiggleEngine.swift mmoveTests/JiggleEngineTests.swift
git commit -m "Replace cursor warp with synthetic input events + self-check and power assertion"
```

---

### Task 4: Menu wiring — degraded status display

**Files:**
- Modify: `mmove/mmoveApp.swift`
- Modify: `mmove/MenuView.swift`

- [ ] **Step 1: Pass the engine to the menu**

Replace `mmove/mmoveApp.swift` body with:

```swift
import SwiftUI

@main
struct MMoveApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var engine: JiggleEngine

    init() {
        let store = SettingsStore()
        let engine = JiggleEngine(settings: store)
        _settings = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: engine)
        engine.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings, engine: engine)
        } label: {
            Image(systemName: "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

Note: `JiggleEngine` is `@MainActor`; `MMoveApp.init()` runs on the main
actor for a SwiftUI `App`, so constructing it there is fine. If the compiler
complains about actor isolation in `init`, wrap construction in
`MainActor.assumeIsolated { ... }`.

- [ ] **Step 2: Show the degraded status in the menu**

In `mmove/MenuView.swift`, replace the struct header and status line:

```swift
struct MenuView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: JiggleEngine
```

and change the first row:

```swift
        Text(engine.statusText)
```

Everything else in `MenuView` stays unchanged.

- [ ] **Step 3: Build and run tests**

Run: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Debug build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add mmove/mmoveApp.swift mmove/MenuView.swift
git commit -m "Surface injection-blocked state in the menu bar status line"
```

---

### Task 5: Docs (README + CHANGELOG)

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README**

In `README.md`, replace the first paragraph (lines 3–6) with:

```markdown
A lightweight macOS menu bar utility that keeps your Mac from going idle by
periodically posting an invisible synthetic input event — the same signal real
mouse movement produces — so the screensaver never starts and presence-aware
apps like Slack keep you active. A held power assertion (the same mechanism as
`caffeinate`) keeps the display awake even if security software blocks input
injection.
```

Replace the feature bullet "Net cursor movement is zero — it always returns to where it was." with:

```markdown
- Net cursor movement is zero — events are posted at the cursor's current position.
```

- [ ] **Step 2: Update CHANGELOG**

In `CHANGELOG.md`, insert above `## [1.0.0]`:

```markdown
## [Unreleased]

### Fixed

- Replaced cursor warping with synthetic input events: warping never reset the
  system idle timer, so the screensaver and Slack idle detection fired anyway.

### Added

- Held display-sleep power assertion (caffeinate-style) while enabled, so the
  display stays awake even if input injection is blocked by security software.
- Self-check that detects blocked input injection and shows a degraded
  "display-only mode" status in the menu.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document idle-prevention mechanism change"
```

---

### Task 6: Release build + manual verification

**Files:** none (verification only)

- [ ] **Step 1: Release build**

Run: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Release build`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual checks (from the spec checklist)**

1. Launch the built app; set frequency to 15s; leave the machine idle →
   `pmset -g assertions` lists mmove's `PreventUserIdleDisplaySleep`, and the
   screensaver/display sleep never fires past the system's normal timeout.
2. Slack presence stays active while mmove is on.
3. Cursor never visibly moves.
4. Type/use the mouse continuously → no synthetic posts (no interference).
5. Pause → `pmset -g assertions` no longer lists mmove.
6. Menu shows "mmove is on" normally; on a machine where injection is blocked
   it shows "mmove is on (input blocked — display-only mode)".
