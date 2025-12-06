# Feature Specification: Extremis - Context-Aware LLM Writing Assistant

**Feature Branch**: `001-llm-context-assist`
**Created**: 2025-12-06
**Status**: Draft
**Input**: User description: "Build a tool for macos called extremis. The purpose of the tool is to bring llm functionalities wherever you are writing currently on the screen. When a user presses a hot key, the tool gets activated. It will check the context of the current screen. For example, if the user is currently working on slack, writing mail on gmail, writing a PR description, etc. The tool then sees what the user is trying to write. For example, in slack if the user is sending a message then whom the message is being sent, what are some older messages. If the user is writing a mail, then what he is writing, to whom he is writing and the context of the mail. If the user is writing a PR, then the context of the PR, etc. The tool will then open a prompt window in which user will ask the tool to say complete the mail, or write the mail in polite way, after that the tool will just auto complete the mail, slack message, github PR, etc."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Hotkey Activation & Text Completion (Priority: P1)

As a user typing anywhere on macOS, I want to press a global hotkey to activate Extremis, see a prompt window appear, type my instruction (e.g., "complete this message"), and have the AI-generated text automatically inserted where I was typing.

**Why this priority**: This is the core value proposition - without hotkey activation and text insertion, the tool provides zero value. This represents the minimum viable product.

**Independent Test**: Can be fully tested by pressing the hotkey in any text field (even TextEdit), typing "write a greeting", and seeing text appear at the cursor position.

**Acceptance Scenarios**:

1. **Given** user is typing in any macOS application, **When** user presses the configured hotkey (default: ⌘+Shift+Space), **Then** a prompt window appears within 200ms without losing focus context
2. **Given** prompt window is open, **When** user types an instruction and presses Enter, **Then** the AI processes the request and shows a preview of generated text
3. **Given** AI has generated text, **When** user confirms (presses Enter or clicks Accept), **Then** text is inserted at the original cursor position in the source application
4. **Given** prompt window is open, **When** user presses Escape, **Then** prompt window closes without any text insertion

---

### User Story 2 - Slack Context Awareness (Priority: P2)

As a Slack user composing a message, I want Extremis to understand the conversation context (who I'm messaging, recent message history) so I can ask it to "reply professionally" or "summarize the thread" and get contextually appropriate responses.

**Why this priority**: Slack is one of the most common professional communication tools. Context-aware assistance here provides significant productivity value and demonstrates the core differentiation of Extremis.

**Independent Test**: Can be tested by opening a Slack conversation, activating Extremis, and asking it to "summarize what was discussed" - it should return an accurate summary of visible messages.

**Acceptance Scenarios**:

1. **Given** user is in a Slack direct message conversation, **When** Extremis is activated, **Then** it captures the recipient name and last 10 visible messages as context
2. **Given** user is in a Slack channel, **When** Extremis is activated, **Then** it captures the channel name, thread context (if in thread), and recent messages
3. **Given** Slack context is captured, **When** user asks "reply agreeing to the meeting time", **Then** AI generates a response that references the specific meeting details mentioned in the conversation
4. **Given** user has typed partial text in Slack, **When** Extremis is activated with instruction "complete this", **Then** the completion maintains the user's tone and references conversation context

---

### User Story 3 - Gmail/Email Context Awareness (Priority: P2)

As a user composing an email in Gmail (web), I want Extremis to understand who I'm writing to, the email subject, any thread history, and my draft text so I can ask it to "make this more formal" or "write a follow-up" with full context.

**Why this priority**: Email is a universal professional communication medium. Context-aware email assistance saves significant time on a daily basis.

**Independent Test**: Can be tested by opening a Gmail compose window with a reply thread, activating Extremis, and asking "write a polite follow-up" - it should reference the original email content.

**Acceptance Scenarios**:

1. **Given** user is composing a new email in Gmail, **When** Extremis is activated, **Then** it captures recipient(s), subject line, and any draft body text
2. **Given** user is replying to an email thread, **When** Extremis is activated, **Then** it captures the original email content, sender, and thread history
3. **Given** email context is captured, **When** user asks "decline this meeting politely", **Then** AI generates a professional decline that references the specific meeting invitation details
4. **Given** user has a partial draft, **When** user asks "finish this email", **Then** completion matches the user's writing style and logically concludes the email

---

### User Story 4 - GitHub PR Context Awareness (Priority: P3)

As a developer writing a GitHub Pull Request description or comment, I want Extremis to understand the PR context (title, changed files summary, existing comments) so I can ask it to "write a detailed description" or "respond to this review comment" appropriately.

**Why this priority**: Developers frequently write PR descriptions and review comments. While valuable, this is more niche than general communication tools.

**Independent Test**: Can be tested by opening a GitHub PR page, activating Extremis in the description field, and asking "summarize the changes" - it should reference the visible file changes.

**Acceptance Scenarios**:

1. **Given** user is editing a PR description on GitHub, **When** Extremis is activated, **Then** it captures PR title, branch names, and visible changed files summary
2. **Given** user is replying to a review comment, **When** Extremis is activated, **Then** it captures the original comment, file context, and code snippet being discussed
3. **Given** PR context is captured, **When** user asks "write a description for this PR", **Then** AI generates a structured description mentioning the actual changes visible on the page

---

### User Story 5 - Custom Hotkey & Preferences (Priority: P3)

As a power user, I want to customize the activation hotkey and configure preferences (like default AI behavior, appearance) so the tool fits my workflow.

**Why this priority**: While not essential for core functionality, customization improves user adoption and satisfaction for power users.

**Independent Test**: Can be tested by opening preferences, changing the hotkey, and verifying the new hotkey activates the prompt window.

**Acceptance Scenarios**:

1. **Given** user opens Extremis preferences, **When** user clicks "Change Hotkey" and presses a new key combination, **Then** the new hotkey is saved and immediately active
2. **Given** user has set a custom hotkey, **When** user restarts their Mac, **Then** the custom hotkey persists and works on login
3. **Given** preferences window is open, **When** user toggles "Launch at Login", **Then** Extremis starts automatically on next system boot

---

### User Story 6 - Generic Text Field Support (Priority: P2)

As a user typing in any application (browsers, native apps, Electron apps), I want Extremis to work even when it cannot detect specific app context, falling back to capturing visible/selected text and providing general writing assistance.

**Why this priority**: Users expect the tool to work everywhere. Graceful degradation ensures the tool is always useful even without rich context.

**Independent Test**: Can be tested by activating Extremis in any random text field (e.g., Notes app) and asking "improve this text" - it should work with whatever text is visible/selected.

**Acceptance Scenarios**:

1. **Given** user is in an unsupported application, **When** Extremis is activated, **Then** it attempts to capture selected text or text near cursor as context
2. **Given** no text is selected or detectable, **When** Extremis is activated, **Then** prompt window opens and user can still type freeform instructions for AI generation
3. **Given** generic context is captured, **When** user asks "rewrite this formally", **Then** AI rewrites the captured text appropriately

---

### Edge Cases

- **No active text field**: When Extremis is activated but no text input is focused, show a message "No text field detected. You can still generate text to copy."
- **Permission denied**: When screen capture or accessibility permissions are missing, show clear instructions to grant permissions in System Preferences
- **AI service unavailable**: When the LLM service is unreachable, show "Unable to connect. Check your internet connection." with retry option
- **Very long context**: When captured context exceeds LLM limits, intelligently truncate older messages while preserving recent context
- **Hotkey conflict**: When the configured hotkey conflicts with another app, detect this and suggest alternatives
- **Rapid successive activations**: Debounce hotkey presses to prevent multiple windows opening
- **User cancels mid-generation**: When user presses Escape during AI generation, cancel the request and close the window cleanly
- **Clipboard interference**: When inserting text, preserve the user's original clipboard content

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST register a global hotkey that works across all macOS applications
- **FR-002**: System MUST display a prompt window within 200ms of hotkey activation
- **FR-003**: System MUST capture the active application name and window title when activated
- **FR-004**: System MUST capture visible or selected text from the current context when possible
- **FR-005**: System MUST provide a text input field for user instructions in the prompt window
- **FR-006**: System MUST send context + user instruction to an LLM service and display the response
- **FR-007**: System MUST allow users to accept, edit, or cancel the generated text
- **FR-008**: System MUST insert accepted text at the original cursor position in the source application
- **FR-009**: System MUST provide app-specific context extraction for Slack (web and desktop)
- **FR-010**: System MUST provide app-specific context extraction for Gmail (web)
- **FR-011**: System MUST provide app-specific context extraction for GitHub (web)
- **FR-012**: System MUST gracefully degrade to generic text capture for unsupported applications
- **FR-013**: System MUST persist user preferences (hotkey, launch at login, appearance settings)
- **FR-014**: System MUST run as a menu bar application without a Dock icon
- **FR-015**: System MUST request and handle macOS Accessibility permissions for text insertion
- **FR-016**: System MUST request and handle macOS Screen Recording permissions for context capture (if needed)
- **FR-017**: System MUST provide visual feedback during AI processing (loading state)
- **FR-018**: System MUST support multiple LLM providers: Google Gemini, Anthropic Claude, and OpenAI ChatGPT
- **FR-018a**: System MUST allow users to configure API keys for any combination of supported providers
- **FR-018b**: System MUST use any configured provider (user's choice if multiple are configured)
- **FR-018c**: System MUST clearly indicate which provider is currently active
- **FR-019**: System MUST preserve user's clipboard content when inserting generated text
- **FR-020**: System MUST support keyboard navigation in the prompt window (Enter to submit, Escape to cancel, Tab to navigate)

### Key Entities

- **Context**: Represents the captured state when Extremis is activated - includes source application, window title, selected/visible text, and app-specific metadata (conversation participants, email subject, PR title, etc.)
- **Instruction**: The user's natural language request for what they want the AI to do with the context
- **Generation**: The AI-produced text response, along with metadata like token count and generation time
- **Preferences**: User settings including hotkey configuration, LLM provider settings, appearance options, and launch behavior

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Prompt window appears within 200ms of hotkey press in 95% of activations
- **SC-002**: Users can complete a full cycle (activate → instruct → insert text) in under 10 seconds for simple requests
- **SC-003**: Context capture succeeds for supported applications (Slack, Gmail, GitHub) in 90%+ of activations
- **SC-004**: Text insertion succeeds at the correct cursor position in 95%+ of attempts
- **SC-005**: 80% of first-time users successfully complete their first AI-assisted text generation without errors
- **SC-006**: Application consumes less than 50MB of memory when idle in the menu bar
- **SC-007**: Application launches and registers hotkey within 2 seconds of system startup

## Assumptions

- Users have a stable internet connection for LLM API calls
- Users are willing to grant Accessibility permissions for text insertion functionality
- Users will provide their own API key for the LLM provider
- Screen content for context capture can be obtained via macOS Accessibility APIs or screen capture
- Modern macOS versions (13.0 Ventura and later) are the target platform
- Web applications (Slack, Gmail, GitHub) are used in Safari or Chrome browsers primarily
