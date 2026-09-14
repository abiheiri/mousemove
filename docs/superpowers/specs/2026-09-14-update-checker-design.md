# Update Checker + Documented macOS Support Range — Design

Date: 2026-09-14

## Goals

1. Let the user check for updates from the menu and, when a newer release
   exists, offer to download it.
2. Document the supported macOS range in the README: minimum viable OS
   through the latest release (macOS 27).

## Decisions

- **Mechanism**: lightweight check against the GitHub Releases API. No
  Sparkle — it would require a new dependency, an appcast feed, and EdDSA
  signing infrastructure, none of which fits the current unsigned DMG
  distribution.
- **Trigger**: manual only, via a "Check for Updates…" menu item. No
  automatic or scheduled checks.
- **Download**: browser-based. The alert's Download button opens the
  release page so the user installs the DMG the same way they did
  originally. No in-app download or install.
- **Minimum viable OS**: macOS 13 Ventura. The app's entire UI is built on
  SwiftUI `MenuBarExtra`, available only on macOS 13+. This matches the
  existing `MACOSX_DEPLOYMENT_TARGET = 13.0`, so no project change is
  needed — the docs make the existing floor explicit. Supported range:
  macOS 13 through macOS 27.

## Components

### `mmove/UpdateChecker.swift` (new)

- Fetches `https://api.github.com/repos/abiheiri/mousemove/releases/latest`
  with `URLSession` (async), decodes JSON `tag_name` and `html_url`.
- A pure static version comparator: strips a leading `v`, splits on `.`,
  compares numeric components (missing components count as 0), e.g.
  `1.10.0 > 1.3.2`, `v1.4.0 == 1.4.0`. Pure so it's unit-testable with no
  network.
- Exposes a single async check that returns a result enum: update available
  (version + URL), up to date, or failed (with a human-readable reason).

### `mmove/MenuView.swift` (modified)

- New "Check for Updates…" button above the existing version line.
- On tap, runs the check and shows an `NSAlert` (the menu already uses
  `NSAlert` for the custom runtime panel, since `MenuBarExtra` can't host
  live UI):
  - Update available: "mmove X.Y.Z is available — you're running A.B.C",
    buttons **Download** (opens release URL via `NSWorkspace`) and **Later**.
  - Up to date: "mmove A.B.C is the latest version."
  - Failure: "Couldn't check for updates" with the reason (offline, HTTP
    error, etc.).

## Docs

- **README.md**: add a Requirements section — "Requires macOS 13 Ventura or
  later (supported through macOS 27), Apple Silicon" — and document the
  "Check for Updates…" item under Usage.
- **CHANGELOG.md**: a new `## [Unreleased]` section with Added entries for
  the update checker and the documented support range.

## Testing

- `mmoveTests/UpdateCheckerTests.swift`: unit tests for the version
  comparator — equal versions, v-prefix handling, major/minor/patch
  ordering, uneven component counts ("1.4" vs "1.4.0"). No network access
  in tests.
- Existing test suites (IdleAssertion, JiggleEngine, SettingsStore) must
  still pass via:
  `xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'`

## Out of scope

- Automatic/scheduled update checks.
- In-app download or install (auto-update).
- Windows/other-platform support statements.
