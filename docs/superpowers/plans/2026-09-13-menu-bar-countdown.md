# Menu Bar State Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the mmove engine state directly in the menu bar: a live countdown when a runtime limit is active, "On" when running without a limit, and the plain icon when paused.

**Architecture:** `JiggleEngine` publishes a new `windowEnd: Date?` (when the current runtime window expires). `mmoveApp`'s `MenuBarExtra` label switches on that value plus `settings.isEnabled`. SwiftUI's `Text(timerInterval:countsDown:)` renders the live countdown, so no new timers are added.

**Tech Stack:** SwiftUI (MenuBarExtra), XCTest, Combine (existing `objectWillChange` observation).

**Spec:** `docs/superpowers/specs/2026-09-13-menu-bar-countdown-design.md`

**Test command (whole suite):**
```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'
```
Expected at the end of every task: `** TEST SUCCEEDED **`

---

### Task 1: Publish `windowEnd` from JiggleEngine

**Files:**
- Modify: `mmove/JiggleEngine.swift`
- Test: `mmoveTests/JiggleEngineTests.swift`

Context: `JiggleEngine` already tracks `startedAt: Date?` and `deadlineInterval: TimeInterval` (both non-published, set in `armDeadline()`/`reschedule()`/`stop()`). Tests use an isolated `UserDefaults` suite per test and `@MainActor` test methods. Rescheduling after a settings change is deferred one runloop tick, which tests handle with `RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))`.

- [ ] **Step 1: Write the failing tests**

Append this new MARK section inside `JiggleEngineTests` in `mmoveTests/JiggleEngineTests.swift`, right before the final closing brace of the class:

```swift
    // MARK: - Window end (menu bar countdown)

    @MainActor
    func testWindowEndSetWhenStartingWithLimit() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        XCTAssertNil(engine.windowEnd) // not started yet

        let before = Date()
        engine.start()
        let end = engine.windowEnd
        XCTAssertNotNil(end)
        XCTAssertEqual(end?.timeIntervalSince(before) ?? 0, 7200, accuracy: 5)
        engine.stop()
    }

    @MainActor
    func testWindowEndNilWithoutLimit() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertNil(engine.windowEnd)
        engine.stop()
    }

    @MainActor
    func testWindowEndNilAfterManualPause() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertNotNil(engine.windowEnd)

        store.isEnabled = false
        // objectWillChange is observed and rescheduling is deferred one runloop tick.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertNil(engine.windowEnd)
    }

    @MainActor
    func testWindowEndNilAfterExpiry() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.expireWindow()
        // isEnabled=false triggers a deferred reschedule one runloop tick later.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertNil(engine.windowEnd)
    }

    @MainActor
    func testStopClearsWindowEnd() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.stop()
        XCTAssertNil(engine.windowEnd)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'
```
Expected: FAIL — compile error, `value of type 'JiggleEngine' has no member 'windowEnd'`.

- [ ] **Step 3: Implement `windowEnd` in JiggleEngine**

In `mmove/JiggleEngine.swift`, add the published property directly below the `timeLimitReached` property (after line 30):

```swift
    /// When the current runtime window expires (nil when stopped or no
    /// limit). Published so the menu bar label can render a countdown.
    @Published private(set) var windowEnd: Date?
```

In `stop()`, clear it alongside the other deadline state — change:

```swift
        deadlineInterval = 0
        startedAt = nil
        timeLimitReached = false
```

to:

```swift
        deadlineInterval = 0
        startedAt = nil
        windowEnd = nil
        timeLimitReached = false
```

In `reschedule()`, the disabled branch — change:

```swift
        guard settings.isEnabled else {
            currentInterval = 0
            assertion.stop()
            return
        }
```

to:

```swift
        guard settings.isEnabled else {
            currentInterval = 0
            windowEnd = nil
            assertion.stop()
            return
        }
```

In `armDeadline()`, set `windowEnd` once the deadline is known — change:

```swift
        startedAt = Date()
        let deadline = limitInterval(limit)
        deadlineInterval = deadline
```

to:

```swift
        startedAt = Date()
        let deadline = limitInterval(limit)
        deadlineInterval = deadline
        windowEnd = Date().addingTimeInterval(deadline)
```

(`reschedule()` already clears `startedAt`/`deadlineInterval` before the guard; `windowEnd` is only ever non-nil after `armDeadline()` sets it, and the two paths that clear deadline state — `stop()` and the disabled branch of `reschedule()` — now clear it too. `expireWindow()` needs no direct change: it sets `isEnabled = false`, which routes through the disabled branch of `reschedule()`.)

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'
```
Expected: `** TEST SUCCEEDED **` — all existing tests plus the 5 new ones pass.

- [ ] **Step 5: Commit**

```bash
git add mmove/JiggleEngine.swift mmoveTests/JiggleEngineTests.swift
git commit -m "Publish windowEnd from JiggleEngine for menu bar countdown"
```

---

### Task 2: State-driven MenuBarExtra label

**Files:**
- Modify: `mmove/mmoveApp.swift`

Context: the label is currently a fixed `Image(systemName: "computermouse")`. `mmoveApp` holds `settings` and `engine` as `@StateObject`, so the label re-renders when `engine.windowEnd` or `settings.isEnabled` changes. `Text(timerInterval:countsDown:)` updates itself once per second — no manual timer needed.

- [ ] **Step 1: Update the label**

In `mmove/mmoveApp.swift`, replace the whole `body` property:

```swift
    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings, engine: engine)
        } label: {
            Image(systemName: "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
```

with:

```swift
    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: settings, engine: engine)
        } label: {
            if let windowEnd = engine.windowEnd {
                Label {
                    Text(timerInterval: Date()...windowEnd, countsDown: true)
                } icon: {
                    Image(systemName: "computermouse")
                }
            } else if settings.isEnabled {
                Label("On", systemImage: "computermouse")
            } else {
                Image(systemName: "computermouse")
            }
        }
        .menuBarExtraStyle(.menu)
    }
```

Behavior this produces:
- Running with a runtime limit → mouse icon + live countdown to window end.
- Running with no limit → mouse icon + "On".
- Paused (manual or time limit reached) → plain mouse icon, unchanged from today.

- [ ] **Step 2: Build and run the full test suite**

Run:
```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'
```
Expected: `** TEST SUCCEEDED **`. (The label change is SwiftUI view code with no unit-testable logic; existing tests must keep passing.)

- [ ] **Step 3: Manual smoke check**

Run the app:
```bash
xcodebuild -project mmove.xcodeproj -scheme mmove -destination 'platform=macOS' build
```
Then launch the built app (or run from Xcode) and confirm in the menu bar:
1. With Settings → Run for → a preset selected and mmove resumed: icon + countdown, ticking down each second.
2. With Run for → No limit and mmove resumed: icon + "On".
3. After clicking Pause: plain icon only.

If the countdown or "On" text does not appear, check that `engine.windowEnd` is non-nil (limit set and engine enabled) before suspecting the view code.

- [ ] **Step 4: Commit**

```bash
git add mmove/mmoveApp.swift
git commit -m "Show engine state in menu bar: countdown, On, or plain icon"
```
