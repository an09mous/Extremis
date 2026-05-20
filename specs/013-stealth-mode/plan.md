# Implementation Plan: Stealth Mode

**Branch**: `013-stealth-mode` | **Date**: 2026-05-20 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-stealth-mode/spec.md`

## Summary

Stealth Mode makes Extremis completely invisible during screen sharing, video calls, and screen recordings. When enabled, all Extremis UI surfaces (prompt window, preferences, loading overlay, modal sheets) are excluded from screen capture via `NSWindow.sharingType = .none`. The menu bar icon is hidden, the process name is disguised, and windows are excluded from Mission Control/Expose. All existing functionality continues to work identically — the app is only invisible to screen capture, not to the user on their physical display. A centralized `StealthManager` service coordinates stealth state across all windows, with a global hotkey toggle and UserDefaults persistence.

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: AppKit (NSWindow.sharingType, NSStatusBar, NSPanel), Carbon (global hotkeys), SwiftUI
**Storage**: UserDefaults (stealth state and configuration)
**Testing**: Standalone Swift test files with TestRunner pattern (project convention)
**Target Platform**: macOS 13.0+ (Ventura). Screen capture exclusion API available since macOS 10.0, but legacy on macOS 15+.
**Project Type**: Single macOS menu bar app
**Performance Goals**: Stealth toggle <100ms perceived latency, menu bar hide/show <200ms
**Constraints**: No new external dependencies, no private/undocumented APIs
**Scale/Scope**: ~8 new/modified files, 1 new service, 2 new hotkeys, 1 new Preferences tab section

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity & Separation of Concerns | PASS | StealthManager is a single-responsibility service. Window controllers remain unchanged except for a one-line registration call. |
| II. Code Quality & Best Practices | PASS | Follows Swift API Design Guidelines, singleton pattern consistent with existing services. |
| III. Extensibility & Testability | PASS | StealthManager is testable in isolation. Window registration is protocol-free (uses NSWindow directly). New windows automatically get stealth via registration. |
| IV. User Experience Excellence | PASS | Toggle is instant (<100ms), toast provides feedback, stealth indicator is subtle. All existing UX preserved. |
| V. Documentation Synchronization | PASS | README, CLAUDE.md, and feature docs will be updated. |
| VI. Testing Discipline | PASS | Unit tests for StealthManager state logic, hotkey registration, persistence, and process name management. |
| VII. Regression Prevention | PASS | Minimal changes to existing files. All stealth logic is additive. Existing window behavior unchanged when stealth is off. |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/013-stealth-mode/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 research output
├── data-model.md        # Phase 1 data model
├── quickstart.md        # Phase 1 quickstart guide
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (new and modified files)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   └── StealthConfiguration.swift    # NEW — UserDefaults-backed stealth settings
│   ├── Protocols/
│   │   └── StealthStrategy.swift         # NEW — Protocol for modular stealth techniques
│   └── Services/
│       ├── StealthManager.swift          # NEW — Central stealth state coordinator
│       └── StealthVerifier.swift         # NEW — Runtime stealth self-test via CGWindowListCreateImage
├── UI/
│   ├── PromptWindow/
│   │   ├── PromptWindowController.swift  # MODIFIED — Register window with StealthManager
│   │   └── PromptView.swift             # MODIFIED — Add stealth indicator badge
│   ├── Preferences/
│   │   ├── PreferencesWindow.swift       # MODIFIED — Register window with StealthManager
│   │   └── GeneralTab.swift             # MODIFIED — Add stealth settings section + Test Stealth button
│   └── Components/
│       ├── LoadingOverlayController.swift # MODIFIED — Register window with StealthManager
│       └── StealthToastController.swift  # NEW — Transient stealth toggle toast
├── App/
│   └── AppDelegate.swift                 # MODIFIED — Stealth init, menu bar hide, hotkeys
└── Tests/
    └── Core/
        └── StealthManagerTests.swift     # NEW — Unit tests for stealth logic

scripts/
└── run-tests.sh                          # MODIFIED — Add StealthManagerTests
```

**Structure Decision**: All new code follows the existing directory structure. `StealthManager` goes in `Core/Services/` (consistent with `HotkeyManager`, `SessionManager`, etc.). `StealthConfiguration` goes in `Core/Models/` (consistent with `Preferences`). The toast controller goes in `UI/Components/` (consistent with `LoadingOverlayController`).

## Design Details

### StealthManager Service

```
StealthManager.shared (singleton, @MainActor)
├── isStealthActive: Bool (@Published)
├── managedWindows: NSHashTable<NSWindow> (weak refs)
├── strategies: [StealthStrategy]  ← modular strategy array
├── originalProcessName: String
├── originalCollectionBehaviors: [ObjectIdentifier: NSWindow.CollectionBehavior]
│
├── toggle() → activates or deactivates
├── activate()
│   ├── Set isStealthActive = true
│   ├── Persist to UserDefaults
│   ├── Apply ALL strategies to ALL managed windows
│   ├── Hide NSStatusItem (via callback to AppDelegate)
│   ├── Disguise process name (if configured)
│   ├── Log macOS version warning if >= 15.0
│   └── Show "Stealth On" toast
├── deactivate()
│   ├── Set isStealthActive = false
│   ├── Persist to UserDefaults
│   ├── Remove ALL strategies from ALL managed windows
│   ├── Show NSStatusItem (via callback to AppDelegate)
│   ├── Restore process name
│   └── Show "Stealth Off" toast
├── registerWindow(_ window: NSWindow)
│   ├── Add to managedWindows (weak ref)
│   ├── Cache original collectionBehavior
│   └── If stealth active: immediately apply all strategies
├── verifyStealth() → Bool  ← runtime self-test
│   ├── Capture screen at Extremis window frame via CGWindowListCreateImage
│   └── Return true if window content NOT present in capture
└── applyStealthProperties(to window: NSWindow) / removeStealthProperties(from window: NSWindow)
```

### Window Registration Points

Each window controller registers its window with `StealthManager` immediately after creation:

| Controller | Window Type | Registration Point |
|------------|-------------|-------------------|
| `PromptWindowController` | `NSPanel` | `configureWindow()` |
| `PreferencesWindowController` | `NSWindow` | `init()` |
| `LoadingOverlayController` | `NSWindow` (borderless) | `show()` (created dynamically) |
| `StealthToastController` | `NSWindow` (borderless) | `showToast()` (created dynamically) |
| `AppDelegate` | `NSWindow` (API key dialog) | `showAPIKeyDialogForProvider()` |

### Hotkey Registration

Two new hotkeys added to `HotkeyIdentifier`:

| Identifier | Default Shortcut | Purpose |
|------------|-----------------|---------|
| `.stealthToggle` (3) | `Option+Shift+S` | Toggle stealth mode on/off |
| `.preferences` (4) | `Option+Shift+,` | Open Preferences when menu bar hidden |

Both registered in `AppDelegate.setupHotkey()` alongside existing `.prompt` and `.magicMode`.

### Menu Bar Icon Management

```
AppDelegate:
├── statusItem: NSStatusItem? (existing)
├── hideMenuBarIcon()
│   ├── NSStatusBar.system.removeStatusItem(statusItem!)
│   └── statusItem = nil
├── showMenuBarIcon()
│   └── setupMenuBar() (existing method, re-creates statusItem)
│
StealthManager:
├── onMenuBarHide: (() -> Void)?  — callback to AppDelegate.hideMenuBarIcon()
└── onMenuBarShow: (() -> Void)?  — callback to AppDelegate.showMenuBarIcon()
```

### Stealth Indicator (PromptView)

A small green dot in the window's top-left toolbar area:

```swift
// In PromptView, conditionally rendered:
if StealthManager.shared.isStealthActive {
    Circle()
        .fill(Color.green)
        .frame(width: 8, height: 8)
        .help("Stealth Mode Active")
}
```

### Stealth Toast

Follows `LoadingOverlayController` pattern — small floating window at top-center of screen:

```
StealthToastController.shared.showToast("Stealth On")
  → Creates borderless NSWindow
  → Registers with StealthManager (gets sharingType = .none)
  → Fades in (0.15s)
  → Auto-fades out after 1 second (0.3s fade)
  → Window destroyed
```

### App Launch Sequence (Modified)

```
applicationDidFinishLaunching:
  1. Read stealth_mode_enabled from UserDefaults          # NEW
  2. If stealth active: set process name disguise          # NEW
  3. setupMainMenu()                                       # EXISTING
  4. If stealth active: skip setupMenuBar()                # MODIFIED
     Else: setupMenuBar()                                  # EXISTING
  5. setupHotkey() — now also registers stealth hotkeys    # MODIFIED
  6. checkPermissions()                                    # EXISTING
  7. ... remaining startup tasks ...                       # EXISTING
```

### Preferences UI (GeneralTab)

New "Stealth Mode" section added to the General tab:

```
┌─ Stealth Mode ──────────────────────────────┐
│ ☑ Enable Stealth Mode                       │
│                                             │
│ Toggle Shortcut: [⌥⇧S] [Record...]         │
│ Preferences Shortcut: [⌥⇧,]               │
│                                             │
│ ☑ Disguise process name                     │
│   Process name: [com.apple.hiservices-xpc]  │
│                                             │
│ [Test Stealth]  ✅ Stealth verified          │
│                                             │
│ ⓘ Stealth mode hides Extremis from screen   │
│   sharing, screenshots, and recordings.     │
└─────────────────────────────────────────────┘
```

### Modular Stealth Strategy Architecture

Stealth-application logic is encapsulated behind a protocol, allowing new techniques to be added without modifying `StealthManager`:

```swift
/// Protocol for stealth techniques applied to windows
protocol StealthStrategy {
    /// Apply stealth properties to a window
    func apply(to window: NSWindow)
    /// Remove stealth properties from a window, restoring original state
    func remove(from window: NSWindow)
}
```

**Default strategy — `SharingTypeStrategy`**:

```swift
struct SharingTypeStrategy: StealthStrategy {
    func apply(to window: NSWindow) {
        window.sharingType = .none
    }
    func remove(from window: NSWindow) {
        window.sharingType = .readWrite
    }
}
```

**`CollectionBehaviorStrategy`** — handles Mission Control/Expose hiding:

```swift
struct CollectionBehaviorStrategy: StealthStrategy {
    // Caches original behaviors per window for restore
    func apply(to window: NSWindow) {
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .stationary, .fullScreenAuxiliary]
    }
    func remove(from window: NSWindow) {
        // Restore cached original behavior
    }
}
```

`StealthManager` initializes with `strategies = [SharingTypeStrategy(), CollectionBehaviorStrategy()]`. Future techniques (e.g., a ScreenCaptureKit exclusion API if Apple adds one) can be added as new strategy conformances without touching existing code.

### Runtime Stealth Self-Test

A `verifyStealth()` method lets users confirm stealth is working in their environment:

```
verifyStealth():
  1. Get the frame of an Extremis managed window
  2. Capture that screen region via CGWindowListCreateImage(.optionOnScreenOnly)
  3. Sample pixels at the window location
  4. If window content is NOT present in the captured image → stealth verified
  5. Return pass/fail result
```

Surfaced as a "Test Stealth" button in Preferences → Stealth section:
- Pass → green checkmark "Stealth verified"
- Fail → yellow warning "Stealth may not be effective on this system"

This validates against legacy capture APIs (the same APIs used by meeting platforms). It cannot validate ScreenCaptureKit-based capture, but that's acceptable since meeting platforms don't use it.

### Platform Version Detection

On app launch, `StealthManager` checks the macOS version:

```swift
let version = ProcessInfo.processInfo.operatingSystemVersion
if version.majorVersion >= 15 {
    print("[Stealth] macOS \(version.majorVersion).\(version.minorVersion) detected — " +
          "local recording tools (QuickTime, OBS) may capture Extremis windows. " +
          "Meeting platforms (Google Meet, Zoom, Teams) remain unaffected.")
}
```

This is informational only — no UI alert. Stealth still works for all meeting/interview platforms on macOS 15+.

### Screen Capture Exclusion — Technical Mechanism

The core stealth technique is setting `NSWindow.sharingType = .none` on all Extremis windows (via `SharingTypeStrategy`):

```swift
// Apply stealth
window.sharingType = .none

// Remove stealth
window.sharingType = .readWrite
```

**Coverage by platform**:

| Platform | Capture Method | sharingType Respected? | Notes |
|----------|---------------|----------------------|-------|
| Google Meet (Chrome) | getDisplayMedia → CGWindowListCreateImage | Yes | Browser uses legacy API |
| Google Meet (Firefox) | getDisplayMedia → CGWindowListCreateImage | Yes | Browser uses legacy API |
| Zoom (window filtering) | Window-based capture | Yes | Requires user to set this mode |
| Zoom (default/auto) | ScreenCaptureKit | Varies by version | May need capture mode change |
| Microsoft Teams | Window-based capture | Yes | Desktop app |
| HackerRank (browser) | Browser getDisplayMedia | Yes | Browser-based platform |
| CoderPad (browser) | Browser getDisplayMedia | Yes | Browser-based platform |
| macOS Screenshot | CGWindowListCreateImage | Yes | Cmd+Shift+3/4 |
| QuickTime Recorder | ScreenCaptureKit | No (macOS 15+) | Limitation documented |
| OBS Studio | ScreenCaptureKit | No (macOS 15+) | Limitation documented |

**Additional hardening**:
- `collectionBehavior = [.canJoinAllSpaces, .transient, .stationary, .fullScreenAuxiliary]` — hides from Mission Control/Expose
- Process name disguise via `ProcessInfo.processInfo.processName`
- Menu bar icon removal via `NSStatusBar.system.removeStatusItem()`

### Testing Strategy

**Unit Tests** (`Tests/Core/StealthManagerTests.swift`):
- `testStealthToggle` — verify isStealthActive toggles correctly
- `testStealthPersistence` — verify UserDefaults read/write
- `testProcessNameDisguise` — verify process name change and restore
- `testStealthConfigurationDefaults` — verify default values
- `testHotkeyIdentifierCases` — verify new enum cases exist
- `testStealthConfigurationCustomValues` — verify custom settings
- `testWindowRegistration` — verify managed windows tracking (count-based)
- `testActivateDeactivateCycle` — verify full cycle restores original state
- `testSharingTypeStrategy` — verify SharingTypeStrategy applies/removes .none correctly
- `testCollectionBehaviorStrategy` — verify CollectionBehaviorStrategy applies stealth behaviors
- `testStrategyArrayApplication` — verify all strategies are applied to windows
- `testPlatformVersionDetection` — verify macOS version check logs appropriately

**Manual QA Checklist**:
1. Toggle stealth via hotkey → toast appears → menu bar icon hides
2. Screen share via Google Meet → Extremis windows not visible
3. Screen share via Zoom (window filtering mode) → not visible
4. Open Preferences via hotkey while stealth active → works, not visible in capture
5. Tool approval dialog appears → not visible in capture
6. Command palette opens → not visible in capture
7. Disable stealth → menu bar icon reappears
8. Restart app with stealth enabled → stealth persists
9. All existing flows work unchanged (prompt, chat, magic mode, insert)
