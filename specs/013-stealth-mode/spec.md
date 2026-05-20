# Feature Specification: Stealth Mode

**Feature Branch**: `013-stealth-mode`
**Created**: 2026-05-20
**Status**: Draft
**Input**: User description: "Build stealth mode in extremis. When enabled, it will basically be undetectable. No icon on the screen / tool bar. No one should be able to see even the process running. I should be able to use shortcuts to spawn it as usual. When sharing my screen, it should be undetectable whoever viewing my screen. Basically, stealth mode will help in meetings / interview by being undetectable. I should be able to see it, but not anyone else."

## User Scenarios & Testing

### User Story 1 - All UI Surfaces Invisible to Screen Capture (Priority: P1)

As a user in a meeting or interview with screen sharing enabled, I want **every** Extremis UI surface to be invisible to screen capture so that no part of the app is ever visible to viewers — only to me on my physical display.

This applies globally to all windows and overlays Extremis displays, including but not limited to:
- The main prompt window (Quick Mode, Chat Mode)
- The Preferences window
- The loading overlay
- The tool approval overlay
- The context viewer sheet
- The command palette
- Any modal sheets (Add/Edit Command, Add/Edit MCP Server, GitHub Auth)
- Any future windows or panels added to the app

**Why this priority**: This is the core value proposition — being able to use LLM assistance during screen sharing without any trace being visible to viewers. A single visible window or overlay breaks the entire stealth guarantee. Every flow must be covered.

**Independent Test**: Can be fully tested by enabling stealth mode, starting a screen share, and exercising every UI flow (prompt, chat, preferences, tool approval, command palette, context viewer) — verifying none appear in the shared screen feed while all remain visible on the user's monitor.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled and the user is sharing their screen, **When** the user presses Option+Space, **Then** the prompt window appears on the user's physical display but does not appear in the screen share feed.
2. **Given** stealth mode is enabled and the user is sharing their screen, **When** the user opens Preferences, **Then** the Preferences window is invisible to screen share viewers.
3. **Given** stealth mode is enabled, **When** a tool approval dialog appears, **Then** it is invisible to screen share viewers.
4. **Given** stealth mode is enabled, **When** the user triggers the command palette (typing `/`), **Then** the command palette overlay is invisible to screen share viewers.
5. **Given** stealth mode is enabled, **When** any modal sheet (context viewer, add/edit forms, auth sheets) is presented, **Then** it is invisible to screen share viewers.
6. **Given** stealth mode is enabled, **When** the user takes a screenshot or uses screen recording, **Then** no Extremis UI surface appears in the captured image or video.
7. **Given** stealth mode is disabled, **When** the user uses Extremis normally, **Then** all windows behave as they do today (visible in screen shares and screenshots).

---

### User Story 2 - Hidden Menu Bar Icon (Priority: P2)

As a user with stealth mode enabled, I want the menu bar icon to be completely hidden so that no visual indicator of Extremis is present on screen.

**Why this priority**: The menu bar icon is the most visible persistent indicator that Extremis is running. Hiding it prevents casual observers from noticing the app.

**Independent Test**: Can be fully tested by enabling stealth mode and verifying the menu bar icon disappears, then disabling stealth mode and verifying it reappears.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled, **When** the user looks at the menu bar, **Then** no Extremis icon is visible.
2. **Given** stealth mode is enabled and the menu bar icon is hidden, **When** the user needs to access Extremis settings, **Then** they can still do so via a keyboard shortcut or by disabling stealth mode.
3. **Given** stealth mode is disabled after being enabled, **When** the user looks at the menu bar, **Then** the Extremis icon reappears in its normal position.

---

### User Story 3 - Toggle Stealth Mode (Priority: P2)

As a user, I want a quick and discreet way to toggle stealth mode on and off so that I can switch between normal and stealth operation as needed.

**Why this priority**: Users need a way to enter and exit stealth mode. A keyboard shortcut ensures this can be done without any visible UI interaction.

**Independent Test**: Can be fully tested by pressing the stealth toggle shortcut and verifying that all stealth behaviors activate, then pressing it again to verify they deactivate.

**Acceptance Scenarios**:

1. **Given** stealth mode is off, **When** the user presses the stealth toggle shortcut, **Then** stealth mode activates (menu bar icon hides, window becomes screen-capture invisible).
2. **Given** stealth mode is on, **When** the user presses the stealth toggle shortcut, **Then** stealth mode deactivates and normal behavior resumes.
3. **Given** the user is in the Preferences UI, **When** they navigate to the stealth settings, **Then** they can configure the stealth toggle shortcut and enable/disable stealth mode.

---

### User Story 4 - Hidden from App Switcher and Mission Control (Priority: P3)

As a user with stealth mode enabled, I want Extremis to not appear in the App Switcher (Cmd+Tab) or Mission Control so that someone glancing at my screen cannot see Extremis listed among running apps or windows.

**Why this priority**: Adds an extra layer of concealment beyond just the window and menu bar icon. Extremis already runs as a menu bar app without a Dock icon, so Dock hiding is inherently handled, but App Switcher and Mission Control visibility need attention.

**Independent Test**: Can be fully tested by enabling stealth mode, pressing Cmd+Tab, and verifying Extremis does not appear in the app switcher, then opening Mission Control and verifying the prompt window is not shown.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled, **When** the user presses Cmd+Tab to open the App Switcher, **Then** Extremis does not appear in the list.
2. **Given** stealth mode is enabled, **When** the user opens Mission Control or Expose, **Then** the Extremis prompt window is not shown among other windows.

---

### User Story 5 - Obscured Process Identity (Priority: P3)

As a user with stealth mode enabled, I want the Extremis process to be difficult to identify in process listings so that someone checking Activity Monitor cannot easily spot it.

**Why this priority**: This adds defense-in-depth for scenarios where someone might check running processes. Complete process hiding is not feasible without OS-level modifications, so this focuses on reducing visibility through reasonable means.

**Independent Test**: Can be fully tested by enabling stealth mode and checking Activity Monitor to verify the process name is less conspicuous.

**Acceptance Scenarios**:

1. **Given** stealth mode is enabled, **When** someone opens Activity Monitor, **Then** the Extremis process uses a generic or inconspicuous name rather than "Extremis".
2. **Given** stealth mode is disabled, **When** someone opens Activity Monitor, **Then** the process appears with its normal "Extremis" name.

---

### Edge Cases

- What happens if the user enables stealth mode while any Extremis window is already visible? All visible windows and overlays should immediately become screen-capture invisible.
- What happens if screen sharing starts after stealth mode is already enabled? All windows should remain invisible to the newly started screen share.
- What happens if the user opens Preferences or a modal sheet while stealth mode is active? The new window must automatically inherit screen-capture exclusion — no visible flash or momentary exposure.
- What happens if the user forgets stealth mode is on and cannot find Extremis? The stealth toggle shortcut should always work to restore visibility, and a subtle visual cue on the prompt window reminds the user stealth is active.
- What happens when the user restarts the app with stealth mode previously enabled? The stealth state should persist across app launches.
- What happens on macOS versions that don't support the screen-capture exclusion API? The app should gracefully degrade and inform the user that screen-share invisibility is not available.
- What happens if the user tries to open Preferences while the menu bar icon is hidden? A keyboard shortcut must be available to open Preferences directly.

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide a stealth mode that, when enabled, makes **all** Extremis UI surfaces (prompt window, preferences window, loading overlay, tool approval overlay, context viewer, command palette, modal sheets, and any future windows) invisible to screen capture, screen sharing, and screen recording.
- **FR-002**: System MUST hide the menu bar icon when stealth mode is enabled.
- **FR-003**: System MUST provide a configurable global keyboard shortcut to toggle stealth mode on and off.
- **FR-004**: System MUST ensure all existing hotkeys (Option+Space, Option+Tab) continue to work identically in stealth mode.
- **FR-005**: System MUST persist the stealth mode state across app restarts.
- **FR-006**: System MUST hide Extremis from Mission Control and Expose when stealth mode is enabled.
- **FR-007**: System MUST allow access to Preferences via keyboard shortcut when the menu bar icon is hidden.
- **FR-008**: System SHOULD disguise the process name in Activity Monitor when stealth mode is enabled.
- **FR-009**: System MUST provide a stealth mode toggle in the Preferences UI.
- **FR-010**: System MUST display a small dot or icon badge in the prompt window's title bar or toolbar area (visible only to the user on the physical display) to indicate stealth mode is active.
- **FR-011**: System MUST ensure all UI surfaces remain fully functional (input, output, scrolling, tool approval, image attachments, preferences editing, command palette) while in stealth mode.
- **FR-012**: System MUST apply stealth mode immediately when toggled, including to all currently-visible windows and overlays.
- **FR-013**: System MUST automatically apply screen-capture exclusion to any new window or overlay created while stealth mode is active, so that newly opened UI surfaces are invisible by default without requiring a toggle.
- **FR-014**: System MUST show a brief transient overlay/toast on the prompt window (e.g., "Stealth On" / "Stealth Off") that fades after approximately 1 second when the user toggles stealth mode, providing clear confirmation that the toggle succeeded.

### Key Entities

- **StealthState**: Whether stealth mode is currently active, persisted in user preferences.
- **StealthConfiguration**: User-configurable settings including toggle shortcut and auto-enable-on-launch preference.

## Success Criteria

### Measurable Outcomes

- **SC-001**: When stealth mode is enabled, no Extremis UI surface (prompt window, preferences, tool approval, command palette, modal sheets, loading overlay) appears in any screen share, screenshot, or screen recording output — verified across at least 3 major video conferencing tools (Zoom, Google Meet, Microsoft Teams).
- **SC-002**: Users can toggle stealth mode in under 1 second via a single keyboard shortcut.
- **SC-003**: All existing Extremis functionality (prompt input, response display, tool execution, chat mode, image attachments, preferences, command palette) works identically with stealth mode enabled.
- **SC-006**: Any new window or overlay opened while stealth mode is active is automatically screen-capture invisible — no user action required beyond the initial stealth toggle.
- **SC-004**: The menu bar icon hides and restores within 200ms of toggling stealth mode.
- **SC-005**: Stealth mode state persists correctly across app restarts with no user re-configuration needed.

## Clarifications

### Session 2026-05-20

- Q: What form should the stealth-active visual indicator take? → A: Small dot or icon badge in the window's title bar or toolbar area.
- Q: How should the user receive confirmation that stealth mode toggled successfully? → A: Brief transient overlay/toast on the prompt window (e.g., "Stealth On" / "Stealth Off") that fades after ~1 second.

## Assumptions

- macOS provides a window-level API to exclude windows from screen capture. This capability is available on macOS 12.0+ and will be the primary mechanism for screen-share invisibility.
- If the user's macOS version does not support screen-capture exclusion, the feature will degrade gracefully with a user-facing warning.
- Complete process hiding is not feasible at the OS level without kernel extensions or SIP modifications. The process disguise feature (FR-008) is best-effort and uses standard macOS process naming capabilities.
- Extremis already runs as an LSUIElement app (no Dock icon), so Dock hiding is inherently handled.
- The stealth toggle keyboard shortcut will default to a modifier combination that does not conflict with existing system or Extremis shortcuts.
