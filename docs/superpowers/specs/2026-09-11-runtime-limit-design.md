# Runtime Limit — Design

Date: 2026-09-11

## Goal

Let the user choose how long mmove stays active: a preset of 2, 4, 6, or 8
hours, a custom duration typed in minutes, or no limit (current behavior).
When the runtime window elapses, mmove pauses itself — it stops posting
synthetic mouse events and releases its power assertion — so the Mac can idle
naturally again and the screensaver / display sleep work.

## Decisions (from brainstorming)

- The countdown starts fresh each time mmove is resumed: at app launch and on
  every manual Resume. Manually pausing does not carry leftover time over.
- On expiry, mmove auto-pauses and shows a status note in the menu
  ("Paused — time limit reached"). No system notification, no quit.
- Quitting and relaunching starts a fresh window. No deadline is persisted;
  only the configured limit (in minutes) is stored.
- Implementation: a dedicated one-shot deadline timer inside `JiggleEngine`
  (approach A). Precise expiry for any limit length; the timer fires once per
  window and causes no extra wakeups while pending.

## SettingsStore

- New persisted key `runtimeLimitMinutes: Int` via UserDefaults.
  - `0` = "No limit" (default; preserves current behavior).
  - Presets: `static let runtimePresets = [120, 240, 360, 480]` (2/4/6/8 h).
  - Custom: any whole number of minutes in `1...1440`.
  - A stored value that is neither `0`, a preset, nor in `1...1440` falls back
    to `0` at launch (mirrors how `frequencySeconds` is validated).
- Unpersisted `@Published var customMinutes: Int` (default 60) so the Custom…
  panel remembers the last typed value for the session.

## JiggleEngine

New state:

- `private(set) var startedAt: Date?` (read-only exposure; MenuView uses it
  for the "Time left" line)
- `private var deadlineTimer: Timer?`
- `@Published private(set) var timeLimitReached = false`
- `private(set) var deadlineInterval: TimeInterval = 0` — the interval the
  deadline timer is armed with (0 when no limit / stopped), exposed for tests
  like `currentInterval`.

Behavior:

- `reschedule()` remains the single funnel for lifecycle changes:
  - Enabled with a limit: record `startedAt = Date()`, arm a one-shot
    `Timer` for `TimeInterval(runtimeLimitMinutes * 60)`, set
    `deadlineInterval` accordingly.
  - Disabled (or no limit): invalidate and clear the deadline timer, set
    `deadlineInterval = 0`.
- The existing `generation` counter is bumped and captured so a deadline
  queued before a stop/reschedule cannot fire afterwards.
- On fire, the engine calls `expireWindow()` (internal so tests can drive it
  directly):
  1. `settings.isEnabled = false` — reuses the existing Pause path
     (`objectWillChange` → deferred `reschedule()`), which stops the jiggle
     timer and releases the `IdleAssertion`, so the Mac idles naturally.
  2. `timeLimitReached = true`.
- `timeLimitReached` is cleared in `reschedule()` whenever the engine becomes
  enabled again (a resume starts a fresh window). A manual Pause does not set
  the flag.
- Changing the limit while running restarts the window, because the settings
  observer already triggers `reschedule()`.
- `statusText` gains a leading case: when `!settings.isEnabled &&
  timeLimitReached` → `"Paused — time limit reached"`. All other cases keep
  their current strings.

## MenuView

- The Settings menu gains a nested **"Run for"** submenu (below the frequency
  items, separated by a `Divider`):
  - "No limit" (default), "2 hours", "4 hours", "6 hours", "8 hours",
    "Custom…".
  - The active choice gets a checkmark, using the same label pattern as the
    frequency items. "Custom…" shows a checkmark plus the value
    (e.g. "Custom (90 min)") when a custom value is active.
- "Custom…" opens an `NSAlert` with an `NSTextField` accessory (MenuBarExtra
  menus cannot host a live text field). Input is trimmed and parsed as an
  integer; non-numeric, zero, negative, or greater-than-1440 input leaves the
  setting unchanged. Valid input sets `runtimeLimitMinutes` and
  `customMinutes`.
- While running with a limit, a "Time left: X h Y min" line appears under the
  status text, computed from `engine.startedAt` (exposed read-only) and the
  limit. The line is absent when there is no limit or the engine is paused.
  The value refreshes when the menu is opened (MenuBarExtra re-renders on
  open); no live ticking countdown.

## Testing

- `JiggleEngineTests`:
  - `expireWindow()` pauses the engine (jiggle timer cleared,
    `currentInterval == 0`), stops the assertion, and sets
    `timeLimitReached`.
  - Resuming after expiry clears `timeLimitReached` and re-arms the deadline
    (`deadlineInterval > 0`).
  - With no limit, `deadlineInterval == 0` and no deadline timer is armed.
  - A stop/reschedule invalidates a pending deadline (generation guard): a
    deadline captured before `stop()` does not mutate state.
  - `statusText` returns "Paused — time limit reached" only in the expired
    state.
- `SettingsStoreTests`:
  - `runtimeLimitMinutes` round-trips through UserDefaults.
  - Default is `0`; an invalid stored value (e.g. -5 or 5000) falls back to
    `0`.

## Out of scope

- Persisting the deadline across relaunches.
- System notifications on expiry.
- Live per-second countdown in the menu.
