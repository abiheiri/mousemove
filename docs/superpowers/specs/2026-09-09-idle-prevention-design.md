# mmove — Idle Prevention Fix: Design Spec

Date: 2026-09-09

## Problem

mmove's jiggle uses `CGWarpMouseCursorPosition`, which only repositions the
cursor. It generates **no input event**, so it never resets macOS's system idle
timer. On modern macOS the screensaver/display-sleep timer and apps like Slack
(Electron) read that idle timer, so both fire as if mmove weren't running.

The target machine may be enterprise-managed (e.g. CrowdStrike EDR), which can
potentially interfere with synthetic input injection, so the fix must degrade
gracefully when event posting is blocked.

## Root Cause

`CGWarpMouseCursorPosition` does not generate an event and does not reset the
HID/system idle timer. Only real or synthetic *events* posted through the HID
event tap reset it. None of the APIs used here require Accessibility
permission.

## Goals

- Screensaver / display sleep never fires while mmove is on.
- Slack (and other presence-aware Electron apps) never mark the user idle.
- Zero net cursor movement.
- No Accessibility permission, no visible side effects.
- Graceful, *detected* degradation if an EDR/policy blocks event injection.

## Non-Goals

- No bypassing of MDM-enforced policies (impossible by design; out of scope).
- No new settings UI beyond what mmove already has.

## Architecture

Two mechanisms run on each tick (belt-and-suspenders):

1. **Synthetic input** — replaces the warp. Resets the system idle timer, which
   both the screensaver and Slack's idle detection observe.
2. **Power assertions** — guarantee display sleep can't occur even if mechanism
   1 is blocked by security software.

### `JiggleEngine.swift` (modified)

`tick()` replaces `jiggle()`:

1. Compute idle time (unchanged:
   `CGEventSource.secondsSinceLastEventType(.hidSystemState, kCGAnyInputEventType)`).
2. Skip if disabled or `idle < frequency` (unchanged pure `shouldJiggle` logic).
3. Post a synthetic `CGEvent` of type `.mouseMoved` at the cursor's current
   position to `kCGHIDEventTap`. Cursor stays put — no warp-back needed, no
   drift, no hot corners.
4. Post the same event to `kCGSessionEventTap` as a courtesy tap for listeners
   at the session layer.
5. **Self-check**: after a short delay, read idle time again and classify with
   a pure function `classifyInjection(idleBefore:idleAfter:)`:
   - idle reset → injection working.
   - idle unchanged → retry once with a `+1px` then `−1px` event pair.
   - still unchanged → set `injectionBlocked = true`; rely on the power
     assertion; reflect the degraded state in the menu.
6. Each tick also calls `IOPMAssertionDeclareUserActivity(kIOPMUserActiveLocal)`
   (equivalent to `caffeinate -u`).

### `IdleAssertion` (new small class)

- On `start()`: `IOPMAssertionCreateWithName(
  kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, …)`
  and hold it; also `ProcessInfo.processInfo.beginActivity(options:
  [.userInitiated])` to prevent App Nap from throttling the timer.
- On `stop()` / disable / quit: release both.
- `IOPMAssertionCreateWithName` returning a non-success code → set
  `assertionFailed = true` so the menu can surface it.

`mmoveApp` starts/stops the assertion in step with `SettingsStore.isEnabled`.

### `MenuView.swift` (minor)

Status line becomes:

- `mmove is on` — normal
- `mmove is on (input blocked — display-only mode)` — injection self-check failed
- `mmove is on (display sleep not blocked)` — power assertion creation failed
- `mmove is on (protection unavailable on this Mac)` — both failed
- `mmove is off` — paused

## Data Flow

```
Timer fires every frequency s
   |
   idle check (CGEventSource)          -- unchanged
   |
   post mouseMoved @HID tap            -- resets system idle timer
   + IOPMAssertionDeclareUserActivity  -- caffeinate -u equivalent
   |
   re-read idle, classifyInjection()   -- detect EDR/policy blocking
   |
   held: PreventUserIdleDisplaySleep   -- display can never sleep while on
```

## Error Handling

- Cursor-position read fails → skip tick (existing behavior).
- Synthetic event creation fails → skip tick.
- Injection blocked (self-check) → degrade to display-only mode, shown in menu.
- Assertion creation fails → surface in menu; synthetic input alone continues.
- All failures are silent in the UI except the single status line; no alerts.

## Testing

- `classifyInjection(idleBefore:idleAfter:)` — pure function, unit tested:
  reset detected, retry-trigger, blocked.
- Existing `shouldJiggle` and `SettingsStore` tests unchanged.
- Timer reschedule / assertion lifecycle (start on enable, release on disable)
  unit tested via injected seams where possible; actual HID/power behavior is
  manual-verified (cannot run in CI).

## Manual Verification Checklist

1. With mmove on, frequency 15s: leave machine idle 30+ min → no screensaver,
   display stays on.
2. Slack presence stays active while mmove on.
3. Cursor never visibly moves.
4. Typing/using the mouse → no synthetic posts (skip logic intact).
5. Pause → assertions released (`pmset -g assertions` shows no mmove entry);
   screensaver returns on its normal schedule.
6. If injection is blocked on the machine: menu shows display-only mode and the
   display still stays on.

## Security / Policy Notes

- Synthetic input injection may be monitored (but is not normally blocked) by
  EDR such as CrowdStrike. The app detects failure rather than assuming success.
- MDM-enforced screensaver/lock policies cannot be overridden; if the OS is
  forced to lock, no user-space app can prevent it.
