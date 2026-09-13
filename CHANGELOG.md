# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
