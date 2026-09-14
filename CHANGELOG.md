# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- "Check for Updates…" menu item: checks the latest GitHub release and
  offers to open the download page when a newer version exists.
- README documents the supported macOS range: macOS 13 Ventura (the
  minimum, required by MenuBarExtra) through macOS 27.

## [1.3.2] - 2026-09-13

### Fixed

- The menu bar countdown now shows the mouse icon next to it. SwiftUI's
  MenuBarExtra renders only one label element, so icon and text are now
  composited into a single image.

### Changed

- Clearer menu structure: frequency presets live under "Jiggle every" and
  runtime limits under "Run for", as two separate submenus instead of a
  generic "Settings" menu.

## [1.3.1] - 2026-09-13

### Fixed

- 100% CPU and an unresponsive app while a runtime limit was active: the
  menu bar countdown used a live-updating SwiftUI Text, which sends
  MenuBarExtra into a runaway update loop. The countdown is now a plain
  string refreshed once per second by the engine's own timer.

## [1.3.0] - 2026-09-13

### Added

- Menu bar state indicator: a live countdown to the end of the runtime
  window when a "Run for" limit is set, "On" next to the icon when running
  with no limit, and the plain icon when paused.

## [1.2.0] - 2026-09-11

### Added

- Settings → "Run for" submenu: No limit, 2/4/6/8 hours, or a Custom…
  entry in minutes.
- Auto-pause when the runtime window elapses, so the Mac idles naturally
  again and the screensaver and display sleep resume.
- "Paused — time limit reached" status after the limit expires.
- "Time left: X h Y min" line under the status while a limit is running.

## [1.1.0] - 2026-09-09

### Fixed

- Replaced cursor warping with synthetic input events: warping never reset the
  system idle timer, so the screensaver and Slack idle detection fired anyway.

### Added

- Held display-sleep power assertion (caffeinate-style) while enabled, so the
  display stays awake even if input injection is blocked by security software.
- Self-check that detects blocked input injection and shows a degraded
  "display-only mode" status in the menu.

## [1.0.0]

### Added

- Menu bar app (no Dock icon) with mouse icon.
- App icon.
- Version shown in the menu.
- Periodic 1–2 px cursor jiggle that returns to the original position.
- Idle detection: never jiggles while the user is typing or moving the mouse.
- Pause/Resume toggle and frequency presets (15s / 30s / 60s / 2m / 5m).
