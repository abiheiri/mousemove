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

- Add `@Published private(set) var windowEnd: Date?`.
- Set it in `armDeadline()` to `startedAt + deadline` (i.e. the moment the
  current runtime window expires), reusing the same captured `Date` for both
  so `windowEnd` and `remainingSeconds` stay consistent.
- Clear it in `stop()`, at the top of `reschedule()` (covers both the
  disabled path and removing the limit mid-window), and synchronously in
  `expireWindow()`.

### mmoveApp

- The `MenuBarExtra` label switches on engine state:
  - `windowEnd != nil` → `Label` with the `computermouse` SF Symbol and
    `Text(timerInterval: min(Date(), end)...end, countsDown: true)`. The
    lower bound is clamped because the deadline timer's tolerance can leave
    `windowEnd` in the past while the engine still runs, and an inverted
    `ClosedRange` traps. SwiftUI re-renders the countdown once per second
    automatically; no manual timer is added.
  - `settings.isEnabled` (no limit) → `Label` with icon and `On`.
  - otherwise → the current plain `Image(systemName: "computermouse")`.

## Performance

One extra SwiftUI label re-render per second, only while a runtime limit
is active. Negligible compared to the existing jiggle timer; no new
`Timer` objects are created.

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

## Out of scope

- Coloring the menu bar icon (rejected: template rendering ignores tints).
- A countdown for the next jiggle (user chose runtime-limit countdown).
