# Menu Bar State Indicator — Design

Date: 2026-09-13

## Goal

Let the user tell at a glance whether mmove is running, without opening the
menu. The original request (tint the icon red when active) was dropped in
favor of a text indicator, because macOS renders MenuBarExtra labels as
template images and tinting is unreliable.

## Behavior

The MenuBarExtra label is state-driven:

| Engine state                     | Menu bar label                        |
|----------------------------------|---------------------------------------|
| Running with a runtime limit     | mouse icon + live countdown to window end |
| Running with no limit ("No limit") | mouse icon + `On`                   |
| Paused (manual or time limit hit) | plain mouse icon (unchanged from today) |

The menu contents (status text, "Time left" line, pause/resume, settings)
are unchanged.

## Implementation

### JiggleEngine

- `@Published private(set) var windowEnd: Date?` — when the current runtime
  window expires; set in `armDeadline()`, cleared in `stop()`, at the top of
  `reschedule()`, and synchronously in `expireWindow()`. Feeds the countdown.
- Add `@Published private(set) var countdownText: String?` — the rendered
  countdown string ("9:41" / "1:02:03"), refreshed once per second by an
  engine-owned 1 s `Timer` armed in `armDeadline()`. A static string drives
  the label because a live-updating `Text(timerInterval:)` in a MenuBarExtra
  label sends SwiftUI into a runaway update loop (100% CPU, unresponsive
  app — observed on macOS 26).
- Clear the timer and text everywhere deadline state is cleared: `stop()`,
  the top of `reschedule()`, and synchronously in `expireWindow()`.

### mmoveApp

- The `MenuBarExtra` label switches on engine state. MenuBarExtra renders
  only ONE label element — a `Label` shows its icon and drops its title, an
  inline symbol inside `Text` drops the image, and an `HStack` drops the
  text (all verified on macOS 26). Icon + text are therefore composited
  into a single template `NSImage` (`MMoveApp.menuBarImage(text:)`):
  - `countdownText != nil` → composite image of symbol + countdown
  - `settings.isEnabled` (no limit) → composite image of symbol + `On`
  - otherwise → the current plain `Image(systemName: "computermouse")`.

## Performance

One 1 s `Timer` and one label re-render per second, only while a runtime
limit is active. Negligible compared to the existing jiggle timer.

## Testing

Extend `JiggleEngineTests`:

- `windowEnd` is set to roughly `now + limit` when starting with a
  runtime limit.
- `windowEnd` is `nil` when running with no limit.
- `windowEnd` is `nil` when the engine is paused / disabled.
- `windowEnd` is `nil` immediately after `expireWindow()` (synchronous
  clear, before the deferred reschedule).
- `windowEnd` is `nil` after `stop()`.
- `windowEnd` is `nil` after removing the limit mid-window.
- `formatCountdown` formats "M:SS" under an hour, "H:MM:SS" at/above,
  clamps negative to "0:00".
- `countdownText` is set while a window is active, ticks down each second,
  is `nil` with no limit, and clears on stop and expiry.

## Out of scope

- Coloring the menu bar icon (rejected: template rendering ignores tints).
- A countdown for the next jiggle (user chose runtime-limit countdown).
