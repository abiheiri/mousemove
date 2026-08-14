# mmove

A tiny macOS menu bar app that nudges the cursor 1–2 pixels (and back) every
so often, so your Mac — and presence-aware chat apps like Slack — don't think
you've gone idle.

- Lives only in the menu bar (mouse icon); no Dock icon, no windows.
- Never moves the cursor while you're typing or using the mouse.
- Net cursor movement is zero — it always returns to where it was.
- No Accessibility or other permissions required.

## Usage

Click the mouse icon in the menu bar:

- **Pause / Resume** — toggle jiggling.
- **Settings** — how often to move: every 15s, 30s, 60s (default), 2m, or 5m.
- **Quit mmove**.

## Build

Requires Xcode 16+ on macOS.

```bash
xcodebuild -project mmove.xcodeproj -scheme mmove -configuration Release build
```

Run tests:

```bash
xcodebuild test -project mmove.xcodeproj -scheme mmoveTests -destination 'platform=macOS'
```

## Release

Push a `v*` tag. GitHub Actions builds the app, packages a DMG, and creates a
GitHub release with notes from `CHANGELOG.md`.
