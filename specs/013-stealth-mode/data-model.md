# Data Model: Stealth Mode

**Feature**: 013-stealth-mode
**Date**: 2026-05-20

## Entities

### StealthManager (Singleton Service)

Central service that manages stealth mode state and coordinates stealth behavior across all windows.

| Property | Type | Description |
|----------|------|-------------|
| `isStealthActive` | `Bool` (`@Published`) | Current stealth mode state, observable by UI |
| `managedWindows` | `NSHashTable<NSWindow>` | Weak references to all registered windows |
| `strategies` | `[StealthStrategy]` | Modular array of stealth techniques to apply |
| `originalProcessName` | `String` | Cached original process name for restore |

| Method | Description |
|--------|-------------|
| `toggle()` | Toggle stealth on/off, applying all strategies to all managed windows |
| `activate()` | Enable stealth mode |
| `deactivate()` | Disable stealth mode |
| `registerWindow(_ window: NSWindow)` | Register a window for stealth management |
| `applyCurrentState(to window: NSWindow)` | Apply current stealth state to a specific window |
| `verifyStealth() -> Bool` | Runtime self-test: captures screen and checks if Extremis windows are excluded |

### StealthStrategy (Protocol)

Modular protocol for stealth techniques. New techniques can be added as conformances without modifying `StealthManager`.

| Method | Description |
|--------|-------------|
| `apply(to window: NSWindow)` | Apply this stealth technique to a window |
| `remove(from window: NSWindow)` | Remove this stealth technique, restoring original state |

**Default conformances**:

| Strategy | Description |
|----------|-------------|
| `SharingTypeStrategy` | Sets `sharingType = .none` (primary screen capture exclusion) |
| `CollectionBehaviorStrategy` | Sets stealth `collectionBehavior` (Mission Control/Expose hiding) |

### StealthVerifier (Utility)

Runtime verification that stealth is working on the current system.

| Method | Description |
|--------|-------------|
| `verify(windowFrame: NSRect) -> Bool` | Captures screen region via `CGWindowListCreateImage` and checks if Extremis content is present. Returns `true` if stealth is effective. |

### StealthConfiguration (UserDefaults-backed)

User-configurable settings for stealth mode behavior.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `stealth_mode_enabled` | `Bool` | `false` | Whether stealth mode is active (persisted) |
| `stealth_toggle_keycode` | `UInt32` | `kVK_ANSI_S` | Key code for stealth toggle shortcut |
| `stealth_toggle_modifiers` | `UInt32` | `optionKey \| shiftKey` | Modifier flags for stealth toggle shortcut |
| `stealth_process_disguise` | `Bool` | `true` | Whether to disguise process name |
| `stealth_disguise_name` | `String` | `"com.apple.hiservices-xpcservice"` | Disguised process name |

### HotkeyIdentifier Extension

| Case | Raw Value | Description |
|------|-----------|-------------|
| `.stealthToggle` | `3` | Stealth mode toggle |
| `.preferences` | `4` | Open Preferences (when menu bar hidden) |

### Window Stealth Properties (Applied per-window)

When stealth is **active**, each registered window gets:

| Property | Value | Purpose |
|----------|-------|---------|
| `sharingType` | `.none` | Exclude from screen capture APIs |
| `collectionBehavior` | `[.canJoinAllSpaces, .transient, .stationary, .fullScreenAuxiliary]` | Hide from Mission Control/Expose |

When stealth is **inactive**, each registered window restores:

| Property | Value | Purpose |
|----------|-------|---------|
| `sharingType` | `.readWrite` (default) | Normal screen capture behavior |
| `collectionBehavior` | Original value | Normal Mission Control behavior |

### StealthToastController (Transient UI)

Manages the brief "Stealth On"/"Stealth Off" toast notification.

| Property | Type | Description |
|----------|------|-------------|
| `toastWindow` | `NSWindow?` | The transient toast window |

| Method | Description |
|--------|-------------|
| `showToast(message: String)` | Show toast, auto-dismiss after ~1 second |

### Stealth Indicator (PromptView addition)

A small visual badge in the prompt window's toolbar area when stealth is active.

| Component | Description |
|-----------|-------------|
| Stealth dot | Small colored dot (e.g., green) visible in the title bar area |
| Visibility | Only shown when `StealthManager.shared.isStealthActive == true` |
| Behavior | Toggles with stealth state, uses SwiftUI conditional rendering |

## State Transitions

```
┌──────────┐  toggle()  ┌──────────┐
│  Normal  │ ────────── │  Stealth │
│  Mode    │ ◄───────── │  Mode    │
└──────────┘  toggle()  └──────────┘

On Activate:
  1. Set isStealthActive = true
  2. Persist to UserDefaults
  3. Apply ALL strategies to ALL managed windows
  4. Hide NSStatusItem (menu bar icon)
  5. Disguise process name (if enabled)
  6. Log macOS version warning if >= 15.0
  7. Show "Stealth On" toast
  8. Register preferences hotkey (if not already registered)

On Deactivate:
  1. Set isStealthActive = false
  2. Persist to UserDefaults
  3. Remove ALL strategies from ALL managed windows
  4. Show NSStatusItem (menu bar icon)
  5. Restore original process name
  6. Show "Stealth Off" toast
  7. Unregister preferences hotkey (menu bar provides access)

On New Window Created (while stealth active):
  1. Register window with StealthManager
  2. Immediately apply ALL strategies

On App Launch:
  1. Read stealth_mode_enabled from UserDefaults
  2. Log macOS version and any stealth limitations
  3. If true: activate stealth BEFORE showing any UI
  4. Register stealth toggle hotkey
```

## Persistence

All stealth configuration is stored in `UserDefaults` — consistent with existing app preferences. No new files or databases needed.

The stealth state is read early in the app launch sequence (before `setupMenuBar()`) to ensure the menu bar icon is never briefly visible when stealth is persisted.
