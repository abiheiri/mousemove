# mmove — Design Spec

Date: 2026-08-14

## Overview

`mmove` is a minimal macOS menu bar (status bar) utility that periodically moves
the mouse cursor by an imperceptible amount (1–2 px, then back) to reset the
system idle timer, so presence-aware apps (Slack, Teams, etc.) don't mark the
user as idle/away. It runs without a Dock icon, is controlled entirely from the
menu bar, never interrupts active typing or mouse use, and requires no
Accessibility permission.

The name "mmove" is deliberately low-key.

## Goals

- Menu bar–only app (no Dock icon, no windows).
- Menu bar icon: a mouse symbol.
- Clicking the icon shows a menu with Settings (frequency presets) and Quit.
- Random, subtle cursor movement at a configurable frequency.
- Never jiggle while the user is actively typing or moving the mouse.
- Buildable in Xcode IDE and via GitHub Actions CI (mirroring the `wamp`
  project's build workflow).

## Non-Goals

- No settings window, no launch-at-login, no hotkeys, no scheduling.
- No Accessibility permission flow (we avoid APIs that need it).

## Platform

- SwiftUI lifecycle with `MenuBarExtra` scene.
- Minimum deployment target: macOS 13 (Ventura).
- Xcode 16 project, built on `macos-15` CI runners, arm64.
- App sandbox disabled (standard for this class of utility; keeps
  `CGWarpMouseCursorPosition` unrestricted).
- `LSUIElement = true` in Info.plist → no Dock icon, no menu bar app menu.

## Architecture

Four small source files plus tests:

### `mmoveApp.swift`
`@main` entry point. A single `MenuBarExtra` scene whose label is the mouse
icon (SF Symbol `computermouse`, with `menubar extra` rendering). Hosts
`MenuView` as content. No `WindowGroup`.

### `JiggleEngine.swift`
Timer-driven engine. One clear purpose: decide when to jiggle and perform it.

- A repeating `Timer` fires every `frequency` seconds (frequency comes from
  `SettingsStore`; the timer is rescheduled when the setting changes).
- On each fire:
  1. Read idle time via
     `CGEventSource.secondsSinceLastEventType(.hidSystemState, kCGAnyInputEventType)`
     — a single read; the any-input event type covers keyboard, mouse, and
     other HID input. No permissions required.
  2. **If the user typed or moved the mouse since the last fire (idle time <
      frequency), do nothing.**
  3. Otherwise, read the current cursor position
     (`CGEvent(source: nil)?.location`), warp it by a random 1–2 px offset in a
     random direction via `CGWarpMouseCursorPosition`, then after a short delay
     (~0.5 s) warp it back to the original position. Net drift: zero.
- The "should I jiggle now, given seconds-since-last-input and frequency?"
  decision is a pure, static function so it is unit-testable without a display.
- Warping (not synthetic `CGEvent` posting) is used because it needs no
  Accessibility permission and still resets the HID idle timer.

### `SettingsStore.swift`
Thin `ObservableObject` wrapper over `UserDefaults`:

- `isEnabled: Bool` (default `true`)
- `frequencySeconds: Int` (default `60`; presets: 15, 30, 60, 120, 300)

Publishes changes so the engine and menu react immediately.

### `MenuView.swift`
Content of the `MenuBarExtra`:

- Status line: "mmove is on" / "mmove is off"
- Toggle: Pause / Resume
- "Settings" submenu with the five presets ("Every N seconds/minutes"),
  checkmark on the current one
- Separator, then Quit (`NSApplication.shared.terminate`)

### `mmoveTests/`
Unit tests for the pure decision logic of `JiggleEngine` (jiggle vs. skip given
idle seconds / enabled state / frequency) and `SettingsStore` persistence.

## Data Flow

```
UserDefaults <-> SettingsStore --(frequency/enabled)--> JiggleEngine
                                                          |
                                        Timer fires every frequency s
                                                          |
                              idle check via CGEventSource (no permission)
                                                          |
                                    warp +1-2 px -> wait -> warp back
```

## Error Handling

- Cursor position read fails → skip this tick silently.
- This app has no network, no filesystem writes beyond `UserDefaults`; errors
  are limited to "couldn't read cursor position", handled by skipping.

## Testing

- `mmoveTests` XCTest target (mirrors wamp's test target).
- Pure-function tests for the jiggle decision:
  - idle < frequency → no jiggle
  - idle >= frequency → jiggle
  - disabled → never jiggle
  - frequency change reschedules the timer
- UI/actual cursor warping is manual-verified; not unit tested.

## Repo Layout

```
mmove.xcodeproj/        # Xcode 16 project, hand-maintained
mmove/
  mmoveApp.swift
  JiggleEngine.swift
  SettingsStore.swift
  MenuView.swift
  Info.plist            # LSUIElement = true (or via build settings)
  Assets.xcassets       # app icon (for Finder/DMG), not shown in Dock
mmoveTests/
  JiggleEngineTests.swift
  SettingsStoreTests.swift
scripts/
  create-dmg.sh
  extract-changelog.sh
.github/workflows/build.yml
README.md
CHANGELOG.md
```

## CI / Build

`.github/workflows/build.yml` adapted from `/Users/al/Documents/wamp/.github/workflows/build.yml`:

- Triggers: push of `v*` tags, PRs to `main`.
- Runner `macos-15`, Xcode 16 via `maxim-lobanov/setup-xcode`.
- On tags: stamp `MARKETING_VERSION` from the tag via `agvtool`.
- Build: `xcodebuild -project mmove.xcodeproj -scheme mmove -configuration
  Release -destination 'platform=macOS,arch=arm64'`, unsigned
  (`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO`).
- On tags: package DMG via `scripts/create-dmg.sh`, upload artifact, create or
  update the GitHub release with notes extracted from `CHANGELOG.md` via
  `scripts/extract-changelog.sh`.

## Manual Verification Checklist

1. App launches, no Dock icon, mouse icon appears in menu bar.
2. Menu shows status, Pause/Resume, frequency presets, Quit.
3. With frequency 15 s: leave machine idle → `pmset -g log | grep -i idle` /
   Slack presence stays active; cursor does not visibly drift.
4. Type or move the mouse continuously → no jiggle occurs (cursor never moves
   on its own while active).
5. Changing frequency takes effect without relaunch.
6. Quit exits cleanly.
