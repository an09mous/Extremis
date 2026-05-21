# Quickstart: Stealth Mode

## Overview

Stealth Mode makes all Extremis UI invisible to screen sharing, screenshots, and screen recordings while remaining visible on your physical display.

## How It Works

1. **Toggle**: Press `Option+Shift+S` (default) to toggle stealth mode
2. **Toast**: A brief "Stealth On" / "Stealth Off" message confirms the toggle
3. **Indicator**: A small green dot appears in the prompt window's toolbar when stealth is active
4. **Menu bar**: The menu bar icon is hidden while stealth is active
5. **Preferences**: Press `Option+Shift+,` to open Preferences when the menu bar icon is hidden

## Configuration

Open Preferences → General → Stealth Mode:

- **Enable Stealth Mode**: Toggle on/off
- **Toggle Shortcut**: Customize the stealth toggle keyboard shortcut
- **Disguise Process Name**: Hide the "Extremis" name in Activity Monitor
- **Process Name**: Custom name shown in Activity Monitor when disguised

## Zoom Setup (Recommended)

For best results with Zoom, change the screen capture mode:

1. Open Zoom → Settings → Screen Share
2. Set "Screen capture mode" to **"Capture with window filtering"** or **"Advanced capture with window filtering"**
3. This ensures Zoom respects window capture exclusion

## Platform Compatibility

| Platform | Status |
|----------|--------|
| Google Meet (browser) | Fully invisible |
| Zoom (window filtering mode) | Fully invisible |
| Microsoft Teams | Fully invisible |
| HackerRank / CoderPad (browser) | Fully invisible |
| macOS Screenshots (Cmd+Shift+3/4) | Fully invisible |
| QuickTime Screen Recording | May be visible on macOS 15+ |
| OBS Studio | May be visible on macOS 15+ |

## Technical Details

- Uses `NSWindow.sharingType = .none` — the industry-standard macOS API for screen capture exclusion
- All Extremis windows (prompt, preferences, overlays, sheets) are covered globally
- Stealth state persists across app restarts
- All existing functionality works identically in stealth mode
