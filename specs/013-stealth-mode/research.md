# Research: Stealth Mode

**Feature**: 013-stealth-mode
**Date**: 2026-05-20

## R1: Screen Capture Exclusion on macOS

### Decision: Multi-layered approach using `NSWindow.sharingType = .none` as primary mechanism + window level tuning + `collectionBehavior` hardening

### Findings

**Primary API — `NSWindow.sharingType = .none`**:
- Sets `CGWindowSharingType.none` on the window, instructing the OS to exclude it from screen capture APIs.
- Historically works with `CGWindowListCreateImage()` — the legacy capture API that many apps still use.
- **macOS 15+ (Sequoia)**: Apple marked `NSWindow.SharingType.none` as a legacy constant. ScreenCaptureKit-based capture (used by QuickTime, OBS, and some Zoom modes) captures the composited framebuffer directly and ignores this flag.
- **However**: Browser-based screen sharing (Google Meet via Chrome, HackerRank via browser) still uses `getDisplayMedia()` which goes through system picker and often respects legacy window exclusion on many configurations. Zoom's "Capture with window filtering" and "Advanced capture with window filtering" modes also respect it.
- **Industry validation**: Tools like Interview Coder, LockedIn AI, Interview Solver, and ShareSpeak all use this exact API as their primary stealth mechanism. It works for the majority of real-world screen sharing scenarios.

**ScreenCaptureKit (macOS 12.3+)**:
- `SCContentFilter(display:excludingApplications:exceptingWindows:)` allows apps to exclude specific windows/apps from their own capture. This is for apps *performing* capture, not for apps *being* captured.
- No public API exists for an app to mark its own windows as "uncapturable" via ScreenCaptureKit. Apple has stated there are no public APIs for preventing screen capture and recommends filing Feedback Assistant requests.

**Window Level Considerations**:
- `NSWindow.Level.floating` is the current level used by the prompt panel.
- Higher window levels (e.g., `.screenSaver`, `.popUpMenu`) can sometimes interfere with capture tools but also cause UX issues (window appears above everything including system dialogs).
- **Decision**: Keep `.floating` level — it's proven by industry tools and doesn't cause UX regressions.

**`collectionBehavior` for Mission Control/Expose hiding**:
- `.transient` — window is not managed by Mission Control, doesn't get its own space.
- `.stationary` — window stays in place during Expose/Mission Control animations.
- `.canJoinAllSpaces` — window appears on all desktops.
- `.fullScreenAuxiliary` — auxiliary to full-screen windows (prevents showing in Mission Control's window list).
- **Decision**: Use `[.canJoinAllSpaces, .transient, .stationary, .fullScreenAuxiliary]` to hide from Mission Control.

### Rationale

Despite the macOS 15+ limitation, `sharingType = .none` remains the industry-standard approach used by all major stealth overlay tools. It works for:
- Google Meet (browser-based via Chrome/Firefox/Safari)
- Zoom (with recommended capture mode settings)
- Microsoft Teams (browser and desktop app in most modes)
- HackerRank, CoderPad, and other browser-based interview platforms
- Most proctoring tools that use standard macOS screen capture APIs

### Alternatives Considered

1. **Private/undocumented APIs** — Rejected: fragile, breaks with OS updates, App Store rejection risk.
2. **Rendering to a separate GPU layer** — Not feasible without kernel-level access.
3. **CALayer-level content protection** (`isSecure` on CALayer) — Only prevents screenshots of that specific layer content, not the window itself. Not sufficient.
4. **Hardware overlay (IOSurface)** — Extremely complex, undocumented, and fragile. Not appropriate for production use.

### Sources

- [How Interview Cheating Tools Hide from Zoom — Adam Svoboda](https://adamsvoboda.net/how-interview-cheating-tools-hide-from-zoom/)
- [Building a (kind of) invisible mac app — Pierce Freeman](https://pierce.dev/notes/building-a-kind-of-invisible-mac-app)
- [NSWindow.SharingType.none — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)
- [macOS 15+: ScreenCaptureKit ignores sharingType — Tauri Issue #14200](https://github.com/tauri-apps/tauri/issues/14200)
- [Undetectability — Interview Solver](https://interviewsolver.com/docs/undetectability)
- [Stealth Interview AI: How Undetectable Tools Actually Work — InterviewMan](https://interviewman.com/blog/stealth-interview-ai)
- [Zoom Flickering with NSWindowSharingNone — Zoom Community](https://community.zoom.com/meetings-2/flickering-window-in-the-screen-capture-of-zoom-mac-desktop-client-when-nswindowsharingnone-is-set-35876)

---

## R2: Menu Bar Icon Hiding

### Decision: Remove and re-add `NSStatusItem` dynamically via `NSStatusBar.system`

### Findings

- `NSStatusBar.system.removeStatusItem(_:)` removes the icon from the menu bar.
- `NSStatusBar.system.statusItem(withLength:)` re-creates it.
- The `statusItem` reference in `AppDelegate` is already an optional `NSStatusItem?` — setting it to `nil` after removal is clean.
- Re-creating requires rebuilding the menu, which `setupMenuBar()` already handles.

### Rationale

This is the standard AppKit pattern. No alternative approach needed — it's simple, reliable, and instantly effective.

---

## R3: Stealth Toggle Hotkey

### Decision: Register a new global hotkey `Option+Shift+S` (configurable) via existing `HotkeyManager`

### Findings

- `HotkeyManager` already supports multiple hotkeys via `HotkeyIdentifier` enum.
- Adding a new case (e.g., `.stealthToggle = 3`) is straightforward.
- The default shortcut `Option+Shift+S` doesn't conflict with system shortcuts or existing Extremis hotkeys (Option+Space, Option+Tab).
- Must be configurable via Preferences, stored in UserDefaults.

### Rationale

Reuses existing infrastructure. No new frameworks or patterns needed.

---

## R4: Process Name Disguise

### Decision: Use `ProcessInfo.processInfo.processName` setter at runtime

### Findings

- `ProcessInfo.processInfo.processName` is read-write in Swift.
- Setting it changes what appears in Activity Monitor's "Process Name" column.
- The executable name on disk doesn't change (still "Extremis" in the .app bundle), but the displayed process name does.
- Some tools may still show the original executable name, but Activity Monitor respects the runtime name.
- **Alternative**: C-level `setprogname()` — works but `ProcessInfo` setter is the Swift-native approach.

### Rationale

Best-effort feature (FR-008 is SHOULD, not MUST). Simple one-liner with meaningful impact for casual observers.

### Alternatives Considered

1. **Renaming the executable** — Requires rebuilding the app bundle. Not feasible at runtime.
2. **Kernel-level process hiding** — Requires SIP disable and kernel extensions. Rejected.
3. **`setprogname()` C function** — Works but ProcessInfo setter is preferred in Swift.

---

## R5: Preferences Access When Menu Bar Hidden

### Decision: Register a dedicated global hotkey for opening Preferences (e.g., `Option+Shift+,`)

### Findings

- When the menu bar icon is hidden, users have no clickable UI to reach Preferences.
- A global hotkey is the only viable approach since the app has no Dock icon.
- This hotkey can be registered alongside the stealth toggle hotkey.
- Adding a new `HotkeyIdentifier` case (`.preferences = 4`) follows the existing pattern.

### Rationale

Users must always be able to access Preferences to disable stealth mode. A dedicated hotkey is the safest failsafe.

---

## R6: Stealth Mode Persistence

### Decision: Store stealth state in `UserDefaults` via a simple boolean key

### Findings

- Existing preferences use `UserDefaults` for simple flags (e.g., active provider, hotkey config).
- A `stealth_mode_enabled` boolean key is sufficient.
- On app launch, check this flag and apply stealth before showing any UI.
- The stealth toggle shortcut configuration can also be stored in UserDefaults.

### Rationale

Consistent with existing persistence patterns. No new storage mechanism needed.

---

## R7: Window Stealth Application Strategy

### Decision: Centralized `StealthManager` service that all window controllers consult

### Findings

- Extremis has multiple window creation points:
  - `PromptWindowController` — main prompt panel (NSPanel)
  - `PreferencesWindowController` — preferences window (NSWindow)
  - `LoadingOverlayController` — floating loading indicator (NSWindow, borderless)
  - `AppDelegate` — API key dialog window (NSWindow)
  - Tool approval overlays — rendered inside PromptWindowController's view
  - Command palette — rendered inside PromptWindowController's view
  - Modal sheets — attached to their parent windows (inherit parent's sharingType)

- **Key insight**: Modal sheets and child views (tool approval, command palette) inherit their parent window's `sharingType`. So we only need to set it on the **top-level NSWindow/NSPanel instances**.

- **Strategy**: Create a `StealthManager.shared` singleton that:
  1. Holds the current stealth state (observable via `@Published`)
  2. Provides `applyStealthToWindow(_ window: NSWindow)` method
  3. Maintains a `WeakSet` of all managed windows for batch toggling
  4. Each window controller calls `StealthManager.shared.registerWindow(window)` at creation
  5. On toggle, iterates all registered windows and applies/removes stealth properties

### Rationale

Centralizing stealth logic prevents the risk of a single window being missed. The registry pattern ensures newly created windows automatically get stealth applied if stealth mode is active. This is consistent with the existing singleton service pattern used throughout the codebase.

---

## R8: Stealth Toast/Indicator

### Decision: Reuse `LoadingOverlayController` pattern for toast, add stealth badge to `PromptView`

### Findings

- The toast ("Stealth On" / "Stealth Off") can follow the same pattern as `LoadingOverlayController` — a floating borderless window with auto-fade.
- The toast window itself must also have `sharingType = .none` to be invisible during screen sharing.
- The persistent stealth indicator (small dot in title bar area) should be added to the `PromptView` SwiftUI view, positioned in the window's toolbar/title area.

### Rationale

Consistent with existing UI patterns. The toast is transient (1-second fade), the badge is persistent while stealth is active.

---

## R9: Zoom-Specific Considerations

### Decision: Document recommended Zoom settings for users; no programmatic Zoom configuration

### Findings

- Zoom's default screen-sharing method on macOS may use ScreenCaptureKit, which bypasses `sharingType = .none`.
- Setting Zoom's screen capture mode to "Capture with window filtering" or "Advanced capture with window filtering" restores respect for the sharingType flag.
- This is a user-configurable Zoom setting under Settings > Screen Share > Screen capture mode.
- Other tools like Interview Coder and LockedIn AI also document this Zoom setting for their users.

### Rationale

This is a well-known industry approach. Programmatic control of Zoom settings is not possible. Documentation/tooltip guidance is the appropriate solution.

---

## R10: Regression Prevention

### Decision: Comprehensive unit tests + manual QA checklist

### Findings

- Unit tests can verify:
  - `StealthManager` state toggling logic
  - Window property application (sharingType, collectionBehavior)
  - Hotkey registration for stealth toggle
  - Persistence of stealth state
  - Process name change and restore
- Manual QA is required for:
  - Screen sharing verification across Zoom, Google Meet, Teams
  - Menu bar icon hide/show visual verification
  - Mission Control/Expose hiding
  - All existing flows work unchanged in stealth mode

### Rationale

Aligns with Constitution principle VII (Regression Prevention). Unit tests catch logic regressions; manual QA catches visual/behavioral regressions.

---

## R11: Future-Proofing — Platform Version Detection

### Decision: Log macOS version at launch and warn if stealth limitations apply

### Findings

- `ProcessInfo.processInfo.operatingSystemVersion` provides the macOS major/minor/patch version at runtime.
- On macOS 15+ (Sequoia), `sharingType = .none` is ignored by ScreenCaptureKit-based capture tools (QuickTime, OBS). Browser-based sharing (Google Meet, HackerRank) and Zoom's window filtering mode still work.
- A console log at launch (e.g., "Stealth: macOS 15+ detected — local recording tools may capture Extremis windows") helps with debugging and user awareness.
- No UI alert needed — stealth still works for all meeting/interview platforms. The warning is informational.

### Rationale

Low-cost, high-value signal for debugging. If Apple adds a new ScreenCaptureKit exclusion API in the future, this version check is the natural place to gate the new behavior.

---

## R12: Future-Proofing — Modular Stealth Strategy Architecture

### Decision: Extract stealth-application logic behind a `StealthStrategy` protocol so new techniques can be added without modifying `StealthManager`

### Findings

- The current stealth technique (`sharingType = .none`) is the only public API available. However, Apple may introduce a ScreenCaptureKit exclusion API in the future, or the community may discover new approaches.
- By encapsulating the window-level stealth application behind a strategy protocol, new techniques can be added as conforming types without touching the `StealthManager` orchestration logic.
- Strategy protocol: `StealthStrategy` with `apply(to: NSWindow)` and `remove(from: NSWindow)` methods.
- Default implementation: `SharingTypeStrategy` — sets `sharingType = .none` and `collectionBehavior`.
- `StealthManager` holds an array of `[StealthStrategy]` and applies all strategies to each window. New strategies (e.g., a future ScreenCaptureKit exclusion strategy) can be added to the array without modifying existing code.
- This is a lightweight abstraction — one protocol, one default conformance. Not over-engineered.

### Rationale

Follows Constitution principle III (Extensibility & Testability). The strategy pattern is minimal overhead but provides a clean seam for future techniques. Each strategy is independently testable.

### Alternatives Considered

1. **Hardcoded in StealthManager** — Simpler today, but requires modifying StealthManager internals when new techniques emerge. Rejected for future-proofing.
2. **Full plugin architecture** — Over-engineered for 1-2 strategies. Rejected.

---

## R13: Future-Proofing — Runtime Stealth Self-Test

### Decision: Add a `verifyStealth()` method that captures a screenshot via `CGWindowListCreateImage` and checks if Extremis windows appear

### Findings

- `CGWindowListCreateImage()` is the legacy capture API that `sharingType = .none` is designed to defeat.
- By capturing the screen region where an Extremis window is positioned and checking if the window content appears in the captured image, we can verify stealth is working at runtime.
- Implementation approach:
  1. Capture screen region at the Extremis window's frame using `CGWindowListCreateImage(.optionOnScreenOnly)`
  2. Compare pixel data at the window location — if the window's background color is present, stealth may not be working
  3. Return a simple pass/fail result
- Surface as a "Test Stealth" button in the Preferences Stealth section. On press, shows "Stealth verified" (green) or "Stealth may not be effective on this system" (yellow warning).
- This self-test only validates against legacy capture APIs (which is what meeting platforms use). It cannot test ScreenCaptureKit-based capture.

### Rationale

Gives users confidence that stealth is working in their specific environment. Also serves as a diagnostic tool if users report stealth failures — "click Test Stealth and tell me the result." Low implementation cost (one function using existing CGWindowListCreateImage API).
