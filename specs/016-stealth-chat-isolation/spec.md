# Feature Specification: Stealth Chat Isolation

**Feature Branch**: `016-stealth-chat-isolation`
**Created**: 2026-06-03
**Status**: Draft
**Input**: User description: "Build a feature so that chats / messages in stealth should be visible only in stealth and not in normal mode"

## User Scenarios & Testing

### User Story 1 - Stealth Sessions Hidden in Normal Mode (Priority: P1)

As a user who has had conversations while stealth mode was active, I want those conversations to be automatically hidden from the session sidebar when I switch back to normal mode, so that anyone glancing at my screen cannot see sensitive stealth conversations.

**Why this priority**: This is the core value proposition — stealth conversations must never leak into the normal-mode UI. Without this, stealth mode only hides the window from screen share but the conversation history remains fully visible afterward.

**Independent Test**: Can be fully tested by enabling stealth mode, having a conversation, disabling stealth mode, and verifying the conversation no longer appears in the sidebar or chat history.

**Acceptance Scenarios**:

1. **Given** the user has active conversations created during stealth mode, **When** the user disables stealth mode, **Then** those conversations disappear from the session sidebar.
2. **Given** the user is in normal mode, **When** the user browses the session sidebar, **Then** no stealth-tagged conversations are visible.
3. **Given** the user is in normal mode and a stealth session was previously the active chat, **When** stealth mode is disabled, **Then** the active view switches to the most recent normal-mode session (or a blank state if none exist).

---

### User Story 2 - Stealth Sessions Visible in Stealth Mode (Priority: P1)

As a user who re-enters stealth mode, I want to see all my previous stealth conversations alongside my normal conversations, so that I can continue sensitive chats or reference normal ones as needed.

**Why this priority**: Equal priority to Story 1 — stealth conversations must be accessible when stealth mode is active, otherwise the isolation feature breaks usability. Showing both types gives the user full flexibility.

**Independent Test**: Can be fully tested by enabling stealth mode, creating a conversation, disabling stealth mode, then re-enabling stealth mode and verifying the conversation reappears alongside normal sessions.

**Acceptance Scenarios**:

1. **Given** the user has previously created stealth conversations, **When** the user enables stealth mode, **Then** all stealth-tagged conversations appear in the session sidebar alongside normal sessions.
2. **Given** the user is in stealth mode, **When** the user creates a new conversation, **Then** the conversation is automatically tagged as a stealth conversation.
3. **Given** the user is in stealth mode, **When** the user opens a stealth conversation, **Then** all messages and history are fully accessible.
4. **Given** the user is in stealth mode, **When** the user opens a normal session, **Then** they can continue conversing in it normally (messages remain normal-tagged).

---

### User Story 3 - Stealth Visual Indicator on Sessions (Priority: P2)

As a user in stealth mode viewing my session sidebar, I want a subtle visual indicator distinguishing stealth sessions from normal sessions so that I understand which conversations are protected.

**Why this priority**: When stealth mode is active, the user sees both stealth and normal sessions. A visual indicator helps the user understand which sessions will disappear when stealth is disabled.

**Independent Test**: Can be fully tested by enabling stealth mode with a mix of stealth and normal sessions and verifying a visual distinction exists.

**Acceptance Scenarios**:

1. **Given** stealth mode is active and the sidebar shows both stealth and normal sessions, **When** the user looks at the sidebar, **Then** stealth sessions have a subtle visual indicator (e.g., a small lock or shield icon) distinguishing them from normal sessions.
2. **Given** stealth mode is disabled, **When** the user views the sidebar, **Then** no stealth indicators are visible (stealth sessions are hidden entirely).

---

### User Story 4 - Session Persistence Across App Restarts (Priority: P2)

As a user, I want my stealth conversations to persist across app restarts and remain properly isolated, so that quitting and reopening the app does not lose stealth conversations or accidentally expose them in normal mode.

**Why this priority**: Persistence ensures the isolation guarantee survives app lifecycle events. Without this, stealth sessions could either be lost or inadvertently exposed after restart.

**Independent Test**: Can be fully tested by creating stealth conversations, quitting the app, reopening it in normal mode, verifying stealth sessions are hidden, then enabling stealth mode and verifying they reappear.

**Acceptance Scenarios**:

1. **Given** the user has stealth conversations and restarts the app in normal mode, **When** the app launches, **Then** stealth sessions are not visible in the sidebar.
2. **Given** the user has stealth conversations and restarts the app, **When** the user enables stealth mode, **Then** all previous stealth sessions are visible and intact.

---

### Edge Cases

- What happens if the user toggles stealth mode rapidly? The sidebar should always reflect the current stealth state without visual glitches or stale entries.
- What happens if the user is actively viewing a stealth session and disables stealth mode? The view should transition to a non-stealth session or blank state — the stealth session content must not remain on screen.
- What happens if all sessions are stealth sessions and the user disables stealth mode? The sidebar shows an empty state with guidance to create a new conversation.
- What happens if the user creates a session in normal mode and then enables stealth? The existing normal session remains tagged as normal and continues to be visible in both modes. The user can still converse in it while stealth is active.
- What happens if a background generation is running on a stealth session when stealth is disabled? The generation continues in the background, but the session is hidden from the sidebar. Notifications (if any) should not reveal stealth content.
- What happens when the user enables stealth mode? The current normal session (if any) stays active — no automatic session switch occurs. The user can manually switch to or create a stealth session.
- What happens if the user wants to delete a stealth session? Stealth sessions can only be deleted while stealth mode is active, since they are not visible in normal mode.
- What happens if the user presses Option+Space (with selection) or Option+Tab in stealth mode? Quick Mode and Magic Mode are disabled in stealth mode. The hotkey is silently ignored (no-op) to prevent transient interactions that could leave traces in clipboard or insertion targets.

## Requirements

### Functional Requirements

- **FR-001**: System MUST tag every new conversation created while stealth mode is active as a stealth session.
- **FR-002**: System MUST hide all stealth-tagged sessions from the session sidebar when stealth mode is disabled.
- **FR-003**: System MUST show all stealth-tagged sessions in the session sidebar when stealth mode is enabled.
- **FR-004**: System MUST show all normal (non-stealth) sessions in the sidebar regardless of stealth mode state. Users can continue conversing in normal sessions while stealth is active.
- **FR-005**: System MUST persist the stealth tag as part of the session data so isolation survives app restarts.
- **FR-006**: System MUST automatically switch the active session away from a stealth session when the user disables stealth mode (transition to the most recent normal session, or an empty state if none exist).
- **FR-007**: System MUST keep the current active session unchanged when stealth mode is enabled — no automatic session switch on stealth activation.
- **FR-008**: System MUST display a visual indicator (e.g., lock or shield icon) on stealth sessions in the sidebar when stealth mode is active.
- **FR-009**: System MUST ensure stealth session content (titles, previews, message snippets) never appears in normal mode UI, including any search results or session previews.
- **FR-010**: System MUST continue background operations (e.g., in-progress generation) on stealth sessions even when stealth mode is disabled, without exposing content.
- **FR-011**: System MUST NOT allow a session's stealth tag to change after creation — a session created in stealth stays stealth, a session created in normal mode stays normal.
- **FR-012**: System MUST only allow deletion of stealth sessions while stealth mode is active (stealth sessions are not accessible for deletion in normal mode).
- **FR-013**: System MUST disable Quick Mode (Option+Space with text selection) when stealth mode is active. The hotkey MUST be silently ignored (no-op).
- **FR-014**: System MUST disable Magic Mode (Option+Tab) when stealth mode is active. The hotkey MUST be silently ignored (no-op).

### Key Entities

- **Stealth Tag**: A boolean property on each conversation/session indicating whether it was created during stealth mode. Immutable after creation.
- **Session Visibility Filter**: Logic that filters the session list based on the current stealth mode state — in normal mode shows only normal sessions; in stealth mode shows all sessions (stealth + normal).

## Success Criteria

### Measurable Outcomes

- **SC-001**: When stealth mode is disabled, zero stealth-tagged sessions are visible in the sidebar, search results, or any other UI surface.
- **SC-002**: When stealth mode is enabled, 100% of stealth-tagged sessions are accessible in the sidebar alongside normal sessions.
- **SC-003**: Stealth session isolation persists correctly across app restarts — no stealth content is exposed during or after app relaunch in normal mode.
- **SC-004**: Toggling stealth mode updates the sidebar session list within 200ms with no visible flicker.
- **SC-005**: Users can distinguish stealth sessions from normal sessions at a glance when stealth mode is active.
- **SC-006**: Quick Mode and Magic Mode hotkeys produce no response or side effects when stealth mode is active.

## Clarifications

### Session 2026-06-03

- Q: When stealth mode is enabled, what happens to the active session? → A: The current active session stays unchanged — no automatic session switch on stealth activation. The user manually switches to or creates a stealth session if desired.
- Q: Can users converse in normal sessions while stealth mode is active? → A: Yes. Normal sessions are always accessible regardless of stealth state. Users can freely switch between stealth and normal sessions in stealth mode. New sessions auto-tag based on current mode.
- Q: Can stealth sessions be deleted, and from which mode? → A: Stealth sessions can only be deleted while stealth mode is active — they are not visible or accessible in normal mode, so deletion naturally requires stealth to be on.
- Q: Should Quick Mode and Magic Mode work in stealth mode? → A: No. Both are disabled in stealth mode — hotkeys are silently ignored to prevent transient interactions that could leave traces (clipboard, text insertion).

## Assumptions

- The existing session/conversation model can be extended with a boolean stealth tag without breaking backward compatibility. Existing sessions default to non-stealth.
- `StealthManager.shared.isStealthActive` is the single source of truth for current stealth state and is already observable.
- Session filtering is applied at the UI layer (sidebar view model) rather than at the storage layer, so stealth sessions remain persisted and intact regardless of mode.
- The stealth tag is immutable after session creation to prevent accidental exposure through tag toggling.
- Isolation is at the session level (not message level) to maintain LLM conversation coherence and follow established industry patterns (WhatsApp Chat Lock, Telegram Secret Chats).
- Chat Mode (Option+Space without selection) remains functional in stealth — it opens the prompt window for stealth chat sessions. Only Quick Mode (with selection) and Magic Mode are disabled.
