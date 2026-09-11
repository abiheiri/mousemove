# Runtime Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick how long mmove stays on (2/4/6/8 h presets or custom minutes); when the window elapses, mmove auto-pauses so the Mac idles naturally again.

**Architecture:** `SettingsStore` persists `runtimeLimitMinutes` (0 = no limit, default). `JiggleEngine` arms a one-shot deadline `Timer` inside the existing `reschedule()` funnel; on fire it calls `expireWindow()`, which flips `settings.isEnabled = false` (reusing the Pause path that stops the jiggle timer and releases the power assertion) and sets `timeLimitReached`. `MenuView` gets a "Run for" submenu with presets and an `NSAlert`-based Custom… panel.

**Tech Stack:** Swift, SwiftUI (MenuBarExtra), XCTest. Spec: `docs/superpowers/specs/2026-09-11-runtime-limit-design.md`.

**Test command** (tests are hosted in the app process; CI does not run them — run locally):

```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS,arch=arm64'
```

Filter to one class with `-only-testing:mmoveTests/SettingsStoreTests` (etc.) appended.

---

### Task 1: SettingsStore — persist `runtimeLimitMinutes`

**Files:**
- Modify: `mmove/SettingsStore.swift`
- Test: `mmoveTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `mmoveTests/SettingsStoreTests.swift`, before the final closing brace:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS,arch=arm64' -only-testing:mmoveTests/SettingsStoreTests
```

Expected: FAIL to compile — "value of type 'SettingsStore' has no member 'runtimeLimitMinutes'".

- [ ] **Step 3: Implement `runtimeLimitMinutes`**

In `mmove/SettingsStore.swift`, add the preset list and max next to the existing statics:

```swift
    /// Allowed runtime-limit presets, in minutes (2/4/6/8 hours).
    static let runtimePresets = [120, 240, 360, 480]
    /// Longest accepted custom limit, in minutes (24 h).
    static let maxCustomMinutes = 1440
```

Add the key inside `private enum Keys`:

```swift
        static let runtimeLimitMinutes = "runtimeLimitMinutes"
```

Add the properties after `frequencySeconds`:

```swift
    /// Minutes mmove stays on before pausing itself. 0 = no limit.
    @Published var runtimeLimitMinutes: Int {
        didSet { defaults.set(runtimeLimitMinutes, forKey: Keys.runtimeLimitMinutes) }
    }

    /// Last custom entry, used to pre-fill the Custom… panel. Not persisted.
    @Published var customMinutes = 60
```

In `init`, register the default and load/validate the stored value:

```swift
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.frequencySeconds: Self.defaultFrequency,
            Keys.runtimeLimitMinutes: 0,
        ])
```

and after the `frequencySeconds` load:

```swift
        let storedLimit = defaults.integer(forKey: Keys.runtimeLimitMinutes)
        self.runtimeLimitMinutes = Self.isValidLimit(storedLimit) ? storedLimit : 0
```

Add the validator at the bottom of the type:

```swift
    static func isValidLimit(_ minutes: Int) -> Bool {
        (0...maxCustomMinutes).contains(minutes)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2. Expected: PASS, 6 tests in `SettingsStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add mmove/SettingsStore.swift mmoveTests/SettingsStoreTests.swift
git commit -m "Add persisted runtime limit setting"
```

---

### Task 2: JiggleEngine — deadline timer and auto-pause

**Files:**
- Modify: `mmove/JiggleEngine.swift`
- Test: `mmoveTests/JiggleEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `mmoveTests/JiggleEngineTests.swift`, before the final closing brace:

```swift
    // MARK: - Runtime limit

    @MainActor
    func testLimitArmsDeadlineTimer() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertEqual(engine.deadlineInterval, 7200)
        engine.stop()
    }

    @MainActor
    func testNoLimitArmsNoDeadline() {
        let store = SettingsStore(defaults: defaults)
        let engine = JiggleEngine(settings: store)
        engine.start()
        XCTAssertEqual(engine.deadlineInterval, 0)
        engine.stop()
    }

    @MainActor
    func testExpireWindowPausesEngineAndReleasesAssertion() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let assertion = IdleAssertion()
        let engine = JiggleEngine(settings: store, assertion: assertion)
        engine.start()
        engine.expireWindow()
        // isEnabled=false triggers a deferred reschedule one runloop tick later.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertFalse(store.isEnabled)
        XCTAssertTrue(engine.timeLimitReached)
        XCTAssertEqual(engine.currentInterval, 0)
        XCTAssertEqual(engine.deadlineInterval, 0)
        XCTAssertFalse(assertion.isActive)
    }

    @MainActor
    func testResumeAfterExpiryClearsFlagAndRearmsDeadline() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.expireWindow()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertTrue(engine.timeLimitReached)

        store.isEnabled = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertFalse(engine.timeLimitReached)
        XCTAssertEqual(engine.deadlineInterval, 7200)
        engine.stop()
    }

    @MainActor
    func testStopClearsDeadlineState() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.stop()
        XCTAssertEqual(engine.deadlineInterval, 0)
        XCTAssertFalse(engine.timeLimitReached)
    }

    @MainActor
    func testDeadlineFiresAndPausesEngine() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 5
        let engine = JiggleEngine(settings: store)
        // Shrink a "minute" so the test doesn't wait 5 real minutes.
        engine.limitInterval = { _ in 0.05 }
        engine.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertFalse(store.isEnabled)
        XCTAssertTrue(engine.timeLimitReached)
        XCTAssertEqual(engine.currentInterval, 0)
    }

    @MainActor
    func testStopPreventsPendingDeadlineFromFiring() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 5
        let engine = JiggleEngine(settings: store)
        engine.limitInterval = { _ in 0.05 }
        engine.start()
        engine.stop()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertTrue(store.isEnabled)
        XCTAssertFalse(engine.timeLimitReached)
    }

    @MainActor
    func testStatusTextShowsTimeLimitReachedOnlyAfterExpiry() {
        let store = SettingsStore(defaults: defaults)
        store.runtimeLimitMinutes = 120
        let engine = JiggleEngine(settings: store)
        engine.start()
        engine.expireWindow()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(engine.statusText, "Paused — time limit reached")

        // A manual pause after a resume shows the normal "off" text.
        store.isEnabled = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        store.isEnabled = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(engine.statusText, "mmove is off")
        engine.stop()
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS,arch=arm64' -only-testing:mmoveTests/JiggleEngineTests
```

Expected: FAIL to compile — no members `deadlineInterval`, `timeLimitReached`, `expireWindow`, `limitInterval`.

- [ ] **Step 3: Implement the deadline timer**

In `mmove/JiggleEngine.swift`:

a) Add state after the existing `injectionBlocked` property:

```swift
    /// True when the runtime window elapsed and the engine paused itself.
    /// Cleared on the next resume, which starts a fresh window.
    @Published private(set) var timeLimitReached = false

    /// When the current window started (nil when stopped or no limit).
    /// Read by MenuView for the "Time left" line.
    private(set) var startedAt: Date?
    private var deadlineTimer: Timer?
```

b) Add the test seam and interval exposure next to `currentInterval`:

```swift
    /// The interval the deadline timer is armed with (0 when no limit or
    /// stopped). Exposed for tests.
    private(set) var deadlineInterval: TimeInterval = 0

    /// Injectable seam for tests: minutes -> seconds until expiry.
    var limitInterval: (Int) -> TimeInterval = { TimeInterval($0 * 60) }
```

c) In `stop()`, clear the deadline state alongside the rest:

```swift
    func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        startedAt = nil
        timeLimitReached = false
        currentInterval = 0
        injectionBlocked = false
        assertion.stop()
    }
```

d) In `reschedule()`, invalidate any pending deadline up front, clear the
flag when (re)enabling, and arm the deadline when a limit is set. The full
replacement:

```swift
    private func reschedule() {
        generation += 1
        timer?.invalidate()
        timer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        startedAt = nil
        guard settings.isEnabled else {
            currentInterval = 0
            assertion.stop()
            return
        }
        timeLimitReached = false
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
        armDeadline()
    }

    /// Arms the one-shot deadline timer when a runtime limit is set.
    private func armDeadline() {
        let limit = settings.runtimeLimitMinutes
        guard limit > 0 else { return }
        startedAt = Date()
        let deadline = limitInterval(limit)
        deadlineInterval = deadline
        let generation = self.generation
        let timer = Timer(timeInterval: deadline, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Bail if the engine stopped or rescheduled since this
                // deadline was armed.
                guard let self, self.generation == generation else { return }
                self.expireWindow()
            }
        }
        // Allow coalescing, but never more than a minute late.
        timer.tolerance = min(deadline * 0.05, 60)
        RunLoop.main.add(timer, forMode: .default)
        deadlineTimer = timer
    }

    /// Ends the runtime window: pause via the normal isEnabled path (stops
    /// the jiggle timer and releases the power assertion so the Mac idles
    /// naturally) and flag the expiry for the status text. Internal (not
    /// private) so tests can drive it directly.
    func expireWindow() {
        guard settings.isEnabled else { return }
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        deadlineInterval = 0
        timeLimitReached = true
        settings.isEnabled = false
    }
```

e) Add the leading case to `statusText`:

```swift
    var statusText: String {
        if !settings.isEnabled && timeLimitReached { return "Paused — time limit reached" }
        if !settings.isEnabled { return "mmove is off" }
        if injectionBlocked && assertion.creationFailed { return "mmove is on (protection unavailable on this Mac)" }
        if injectionBlocked { return "mmove is on (input blocked — display-only mode)" }
        if assertion.creationFailed { return "mmove is on (display sleep not blocked)" }
        return "mmove is on"
    }
```

f) Add `remainingSeconds` for the menu's "Time left" line, after `statusText`:

```swift
    /// Seconds left in the current runtime window; nil when there is no
    /// limit or the engine is paused.
    var remainingSeconds: TimeInterval? {
        guard settings.isEnabled, let startedAt, deadlineInterval > 0 else { return nil }
        return max(0, deadlineInterval - Date().timeIntervalSince(startedAt))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2. Expected: PASS — all `JiggleEngineTests`
including the 8 new ones.

- [ ] **Step 5: Commit**

```bash
git add mmove/JiggleEngine.swift mmoveTests/JiggleEngineTests.swift
git commit -m "Auto-pause mmove when the runtime limit elapses"
```

---

### Task 3: MenuView — "Run for" submenu, Custom… panel, time-left line

**Files:**
- Modify: `mmove/MenuView.swift`

No new unit tests (per spec; menu wiring is verified by the full build and
manual check in Task 4).

- [ ] **Step 1: Add the UI**

Replace the `body` of `MenuView` in `mmove/MenuView.swift` with:

```swift
    var body: some View {
        Text(engine.statusText)
        if let remaining = engine.remainingSeconds {
            Text("Time left: \(Self.formatRemaining(remaining))")
        }

        Button(settings.isEnabled ? "Pause" : "Resume") {
            settings.isEnabled.toggle()
        }

        Menu("Settings") {
            ForEach(SettingsStore.frequencyPresets, id: \.self) { seconds in
                Button {
                    settings.frequencySeconds = seconds
                } label: {
                    if seconds == settings.frequencySeconds {
                        Label(label(for: seconds), systemImage: "checkmark")
                    } else {
                        Text(label(for: seconds))
                    }
                }
            }

            Divider()

            Menu("Run for") {
                Button {
                    settings.runtimeLimitMinutes = 0
                } label: {
                    if settings.runtimeLimitMinutes == 0 {
                        Label("No limit", systemImage: "checkmark")
                    } else {
                        Text("No limit")
                    }
                }
                ForEach(SettingsStore.runtimePresets, id: \.self) { minutes in
                    Button {
                        settings.runtimeLimitMinutes = minutes
                    } label: {
                        if minutes == settings.runtimeLimitMinutes {
                            Label(runtimeLabel(for: minutes), systemImage: "checkmark")
                        } else {
                            Text(runtimeLabel(for: minutes))
                        }
                    }
                }
                Button {
                    showCustomLimitPanel()
                } label: {
                    if isCustomLimitActive {
                        Label("Custom (\(settings.runtimeLimitMinutes) min)", systemImage: "checkmark")
                    } else {
                        Text("Custom…")
                    }
                }
            }
        }

        Divider()

        Text("mmove \(Self.appVersion)")

        Divider()

        Button("Quit mmove") {
            NSApplication.shared.terminate(nil)
        }
    }
```

Add the helpers below `label(for:)`:

```swift
    private var isCustomLimitActive: Bool {
        settings.runtimeLimitMinutes != 0
            && !SettingsStore.runtimePresets.contains(settings.runtimeLimitMinutes)
    }

    private func runtimeLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    /// MenuBarExtra menus can't host a live text field, so the custom entry
    /// is collected in a modal panel. Invalid input (non-numeric, out of
    /// 1...1440) leaves the setting unchanged.
    private func showCustomLimitPanel() {
        let alert = NSAlert()
        alert.messageText = "Custom runtime limit"
        alert.informativeText = "Minutes mmove stays on before pausing (1–\(SettingsStore.maxCustomMinutes))."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(settings.customMinutes)
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(trimmed), SettingsStore.isValidLimit(minutes), minutes > 0 else { return }
        settings.customMinutes = minutes
        settings.runtimeLimitMinutes = minutes
    }

    /// "2 h 5 min" / "42 min"; rounds up so the line never reads "0 min".
    static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add mmove/MenuView.swift
git commit -m "Add runtime limit picker to the settings menu"
```

---

### Task 4: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run:

```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS,arch=arm64'
```

Expected: PASS — all tests in `SettingsStoreTests`, `JiggleEngineTests`, and
`IdleAssertionTests`.

- [ ] **Step 2: Release build (matches CI)**

Run:

```bash
xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke check**

Run the app (`open` the built `.app` or run from Xcode) and verify:
- Settings → Run for shows No limit (checked), 2/4/6/8 hours, Custom….
- Picking "2 hours" shows a "Time left: 2 h 0 min" line under the status.
- Custom… opens the panel; typing `90` checks "Custom (90 min)"; typing `abc`
  or `9999` changes nothing.
- Choosing a very short custom value (1 min) pauses mmove after a minute and
  the status reads "Paused — time limit reached"; clicking Resume clears it
  and starts a fresh window.
