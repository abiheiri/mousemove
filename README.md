# mmove

A lightweight macOS menu bar utility that keeps your Mac from going idle by
periodically posting an invisible synthetic input event, the same signal real
mouse movement produces, so the screensaver never starts and apps that track
your presence, like Slack, keep you active. A held power assertion (the same
mechanism as `caffeinate`) keeps the display awake even if security software
blocks input injection.

- Lives only in the menu bar; no Dock icon, no windows.
- Never interferes while you're typing or using the mouse.
- Net cursor movement is zero: events are posted at the cursor's current position.
- No special permissions required.

![mmove menu](docs/screenshot.png)

## Usage

Click the mouse icon in the menu bar:

- **Pause / Resume**: toggle the activity timer.
- **Settings**: choose how often to nudge, every 15s, 30s, 60s (default), 2m, or 5m.
- **Settings → Run for**: set an optional runtime limit of no limit, 2, 4, 6,
  or 8 hours, or a custom number of minutes. mmove pauses itself when the
  window elapses, and a "Time left" line under the status shows the remaining
  time.
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
