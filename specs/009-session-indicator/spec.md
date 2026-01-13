# Feature Specification: New Session Indicator

**Feature Branch**: `009-session-indicator`
**Created**: 2026-01-12
**Status**: Draft
**Input**: User description: "Add enhancement in extremis to indicate in the UI when new session start. If on quick mode, user creates a new session user is not getting indicated if a new session is started"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visual Indicator for New Session in Quick Mode (Priority: P1)

When a user is in Quick Mode (has selected text and submits an instruction), a new session is created behind the scenes to store the conversation. Currently, there is no visual indication that a new session has started. Users should see a clear, non-intrusive indicator when a new session begins so they understand they are starting a fresh conversation context.

**Why this priority**: This is the core problem described - users in Quick Mode have no awareness that a new session has started, leading to confusion about conversation context and continuity.

**Independent Test**: Can be fully tested by selecting text, triggering Quick Mode (Option+Space), submitting an instruction, and verifying a visual indicator appears showing a new session has started.

**Acceptance Scenarios**:

1. **Given** user has selected text and triggers Quick Mode, **When** they submit their first instruction, **Then** a visual indicator should appear showing "New Session" or similar messaging
2. **Given** user is viewing the response in Quick Mode, **When** looking at the UI, **Then** they should be able to distinguish this is a new session vs continuing an existing one
3. **Given** a new session indicator is displayed, **When** the user continues interacting, **Then** the indicator should transition or fade after the initial acknowledgment

---

### User Story 2 - Visual Indicator for New Session in Chat Mode (Priority: P2)

When a user is in Chat Mode (no selection, conversational interface), they should also see an indicator when starting a new session. This provides consistency across all modes and helps users understand when they are beginning fresh vs continuing an existing conversation.

**Why this priority**: While Chat Mode may already have some implicit context (empty message list), having an explicit indicator maintains consistency and improves clarity.

**Independent Test**: Can be fully tested by triggering Chat Mode without selection (Option+Space), and verifying a visual indicator appears for new session start.

**Acceptance Scenarios**:

1. **Given** user triggers Chat Mode without selection, **When** a new session starts, **Then** a visual indicator should appear showing the session is new
2. **Given** user loads an existing session from the session list, **When** viewing the chat, **Then** NO new session indicator should appear (it's a continuation)

---

### User Story 3 - Session Transition Indicator (Priority: P3)

When a user explicitly creates a new session while already in a conversation (e.g., clicking "New Session" button), they should see a clear visual transition indicating the previous session has ended and a new one has begun.

**Why this priority**: This is a less common scenario but important for power users who frequently start new sessions to compartmentalize different tasks.

**Independent Test**: Can be fully tested by having an active session, clicking the new session button, and verifying the visual transition/indicator appears.

**Acceptance Scenarios**:

1. **Given** user has an active session with messages, **When** they click "New Session", **Then** a visual indicator should show the transition to a new session
2. **Given** user creates a new session, **When** viewing the UI, **Then** the previous session context should be visually cleared and the new session indicator displayed

---

### Edge Cases

- What happens when the app is first launched with no previous sessions? (Show new session indicator)
- How does the indicator behave if the user rapidly switches between sessions? (Should not flicker or stack indicators)
- What happens if session creation fails? (Do not show new session indicator; show error instead)
- How long should the indicator remain visible? (Should auto-dismiss after 2-3 seconds or on first user interaction)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a visual indicator when a new session is created in Quick Mode
- **FR-002**: System MUST display a visual indicator when a new session is created in Chat Mode
- **FR-003**: System MUST NOT display the new session indicator when loading an existing session
- **FR-004**: The new session indicator MUST be non-intrusive and not block user interaction
- **FR-005**: The new session indicator MUST auto-dismiss after a brief period or on user interaction
- **FR-006**: System MUST display a visual indicator when user explicitly creates a new session while in an existing one
- **FR-007**: The indicator MUST be an inline text badge integrated into the header/toolbar area, following Apple Human Interface Guidelines
- **FR-008**: The indicator MUST be visually consistent with the existing Extremis UI design language (accent colors, typography)

### Key Entities

- **Session**: The conversation context that tracks messages between user and assistant. A new session indicator relates to the creation event of this entity.
- **Session State**: Tracks whether a session is newly created, continuing, or being switched to.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify within 1 second whether they are in a new session or continuing an existing one
- **SC-002**: 100% of new session creation events in Quick Mode result in a visible indicator
- **SC-003**: 100% of new session creation events in Chat Mode result in a visible indicator
- **SC-004**: The indicator does not block or delay any user interactions (appears within 100ms of session creation)
- **SC-005**: User testing shows 90%+ of users correctly understand when they have started a new session

## Clarifications

### Session 2026-01-12

- Q: What visual style should the indicator use (toast, inline badge, or animation)? → A: Inline text badge integrated into header/toolbar area

## Assumptions

- The indicator will be an inline text badge (e.g., "New Session" label) integrated into the header/toolbar area
- The indicator styling will match existing Extremis design patterns (accent colors, typography)
- The indicator will appear in the main prompt/response window area, not in external notifications
- Auto-dismiss timing of 2-3 seconds is appropriate for this type of notification
- The feature applies to both the initial prompt view and the response view states
