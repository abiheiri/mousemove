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
- Set it in `armDeadline()` to `startedAt + deadlineInterval` (i.e. the
  moment the current runtime window expires).
- Clear it in `stop()` and in the disabled branch of `reschedule()`.
- `expireWindow()` needs no direct change: it sets `isEnabled = false`,
  which triggers `reschedule()` through the existing `objectWillChange`
  observer, clearing `windowEnd`.

### mmoveApp

- The `MenuBarExtra` label switches on engine state:
  - `windowEnd != nil` → `Label` with the `computermouse` SF Symbol and
    `Text(timerInterval: Date()...end, countsDown: true)`. SwiftUI
    re-renders the countdown once per second automatically; no manual
    timer is added.
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
- `windowEnd` is `nil` when the engine is paused / disabled.
- `windowEnd` is `nil` after `expireWindow()`.

## Out of scope

- Coloring the menu bar icon (rejected: template rendering ignores tints).
- A countdown for the next jiggle (user chose runtime-limit countdown).
