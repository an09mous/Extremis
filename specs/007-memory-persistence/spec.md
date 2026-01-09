# Feature Specification: Memory & Persistence

**Feature Branch**: `007-memory-persistence`
**Created**: 2026-01-03
**Status**: Draft
**Input**: User description: "Build a memory and persistence feature for Extremis with session continuity, agentic memory, and dynamic summarization"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resume Previous Conversation (Priority: P1)

As a user, I want Extremis to remember my previous conversation when I relaunch the app, so I can continue where I left off without losing context.

**Why this priority**: This is the foundational feature that enables all other memory capabilities. Without persistence, users lose all context every time they close the app, leading to repetitive interactions and poor UX.

**Independent Test**: Can be fully tested by having a conversation, quitting Extremis, relaunching, and verifying the previous conversation is restored and usable.

**Acceptance Scenarios**:

1. **Given** I have an active conversation with 5 messages, **When** I quit Extremis and relaunch it, **Then** I see my previous conversation restored with all 5 messages intact.
2. **Given** I have a restored conversation, **When** I send a new message, **Then** the AI responds with awareness of the previous context.
3. **Given** I have a restored conversation, **When** I click "New Conversation" or use a clear action, **Then** the conversation is cleared and I start fresh.

---

### User Story 2 - Start Fresh Session (Priority: P1)

As a user, I want the ability to clear my conversation history and start a fresh session, so I can begin a new topic without prior context influencing responses.

**Why this priority**: Equal priority with resume because users need control over their context. Without this, restored conversations could become a hindrance for new tasks.

**Independent Test**: Can be tested by having a conversation, using the clear action, and verifying the conversation is empty and the AI has no memory of previous messages.

**Acceptance Scenarios**:

1. **Given** I have a conversation with history, **When** I choose to start a new session, **Then** the conversation is cleared and no previous messages are shown.
2. **Given** I cleared my conversation, **When** I send a new message, **Then** the AI responds without any awareness of previous conversations.
3. **Given** I want to clear my session, **When** I look for the option, **Then** I can find it easily in the UI (menu bar or within the prompt window).

---

### User Story 3 - Automatic Context Summarization (Priority: P2)

As a user having a long conversation (20+ messages), I want Extremis to automatically summarize older messages so the AI maintains context without hitting token limits or slowing down.

**Why this priority**: Important for power users with extended conversations, but most users won't hit this limit in typical usage. Core persistence (P1) must work first.

**Independent Test**: Can be tested by having a conversation exceed 20 messages and verifying the AI still remembers key points from early in the conversation while response times remain acceptable.

**Acceptance Scenarios**:

1. **Given** I have a conversation with 25 messages, **When** I ask about something mentioned in message #3, **Then** the AI can recall and reference that information accurately.
2. **Given** my conversation exceeds the summarization threshold, **When** I continue chatting, **Then** response times remain similar to shorter conversations (no noticeable slowdown).
3. **Given** summarization has occurred, **When** I view my conversation history, **Then** I still see all my original messages (summarization is internal, not visible to user).

---

### User Story 4 - Cross-Session Memory (Priority: P3)

As a frequent user, I want Extremis to remember key facts about me and my preferences across different conversations, so I don't have to repeat myself in every new session.

**Why this priority**: Nice-to-have feature that enhances long-term UX, but requires P1 and P2 to be solid first. This is a differentiating feature seen in advanced AI assistants.

**Independent Test**: Can be tested by telling Extremis a personal preference, starting a new session, and verifying the AI remembers that preference.

**Acceptance Scenarios**:

1. **Given** I told Extremis "I prefer concise responses" in a previous session, **When** I start a new conversation, **Then** the AI provides concise responses by default.
2. **Given** I want to see what Extremis remembers about me, **When** I ask "What do you remember about me?", **Then** I see a summary of stored preferences and facts.
3. **Given** I want to clear my long-term memory, **When** I choose to reset memory in preferences, **Then** all stored facts and preferences are deleted.

---

### Edge Cases

- What happens when the persisted conversation file is corrupted or unreadable?
  - System starts with a fresh session and optionally notifies the user that previous data couldn't be restored.
- What happens when the conversation is extremely long (100+ messages) and summarization cannot compress enough?
  - System keeps the most recent messages in full detail and provides a condensed summary of earliest messages, potentially with a warning about context limits.
- What happens when the user has multiple Extremis windows open?
  - Each window maintains its own conversation state; persistence saves the most recently active conversation.
- What happens when disk space is insufficient to save conversation?
  - System gracefully handles the error and warns the user, continuing to function without persistence.
- What happens when the user upgrades Extremis and the persistence format changes?
  - System migrates old format to new format automatically, or starts fresh if migration fails (with notification).

## Requirements *(mandatory)*

### Functional Requirements

**Session Persistence**
- **FR-001**: System MUST automatically save conversation state when the app is closed or enters background.
- **FR-002**: System MUST restore the most recent conversation when the app is launched.
- **FR-003**: System MUST provide a clear and discoverable way for users to start a new/fresh conversation.
- **FR-004**: System MUST preserve message content, sender role (user/assistant), and timestamps.

**Context Summarization**
- **FR-005**: System MUST automatically summarize older messages when conversation exceeds 20 messages.
- **FR-006**: System MUST maintain key information from summarized messages so AI can reference them.
- **FR-007**: System MUST keep original messages visible to the user (summarization is internal only).
- **FR-008**: System MUST trigger summarization transparently without blocking user interaction.

**Cross-Session Memory**
- **FR-009**: System MUST allow users to store persistent facts/preferences that survive conversation clears.
- **FR-010**: System MUST provide a way for users to view stored memories.
- **FR-011**: System MUST provide a way for users to clear all stored memories.
- **FR-012**: System MUST include stored memories in AI context for personalized responses.

**Data Management**
- **FR-013**: System MUST store conversation data locally on the user's device.
- **FR-014**: System MUST handle storage failures gracefully without crashing.
- **FR-015**: System MUST support data format migration when persistence schema changes.

### Key Entities

- **Conversation**: A chat session containing messages, creation timestamp, and last-modified timestamp. Can be active or archived.
- **Message**: Individual chat message with content, role (user/assistant/system), timestamp, and optional metadata.
- **ConversationSummary**: Condensed representation of older messages, containing key points and referenced message IDs.
- **UserMemory**: Persistent facts and preferences about the user that survive across conversations. Contains fact content, category, creation date, and source conversation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can quit and relaunch Extremis and see their previous conversation restored in under 2 seconds.
- **SC-002**: Conversations with 50+ messages maintain response times within 20% of conversations with 10 messages.
- **SC-003**: Users can find and use the "new conversation" action within 5 seconds of looking for it.
- **SC-004**: AI can accurately recall information from the first 5 messages of a 30-message conversation at least 90% of the time.
- **SC-005**: Persistence data uses less than 10MB for typical usage (100 conversations, 1000 total messages).
- **SC-006**: 95% of users who try the feature report that conversation restoration "worked as expected" in usability testing.

## Assumptions

- Conversations are stored locally only; no cloud sync is required for MVP.
- The summarization threshold of 20 messages is a reasonable default based on typical LLM context windows.
- Users expect their data to persist indefinitely until manually cleared (no automatic expiration).
- Cross-session memory (P3) extracts facts automatically from conversation; no explicit "remember this" command needed for MVP.
- The existing `ChatConversation` model can be extended to support persistence.
