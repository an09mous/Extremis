# Feature Specification: Text Summarization

**Feature Branch**: `002-text-summarization`
**Created**: 2025-12-16
**Status**: Draft (Revised)
**Last Updated**: 2025-12-16
**Input**: User description with UX refinement for selection-aware behavior

## Design Philosophy

**Core Insight**: When a user selects text before triggering Extremis, they're signaling intent to do something WITH that text. The most natural action is to understand/summarize it.

**Key Optimization**: If `selectedText` exists, skip expensive clipboard capture (saves 400-600ms).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Magic Mode: Selection = Summarize (Priority: P1) 🎯 MVP

As a user reading lengthy content anywhere on macOS, I want to select text and press ⌥+Tab to instantly see the Prompt Window with a summary already being generated, while the same hotkey continues to work as autocomplete when I have no selection.

**Why this priority**: Zero new hotkeys to learn. Intelligent behavior based on selection state. Reuses existing PromptWindow UI for familiar experience.

**Independent Test**:
- Test A: Select any text → Press ⌥+Tab → See Prompt Window open with summary streaming
- Test B: No selection, cursor in text field → Press ⌥+Tab → Text autocompletes (existing)

**Acceptance Scenarios**:

1. **Given** user has text selected in any macOS application, **When** user presses ⌥+Tab, **Then** toast shows "📝 Summarizing..." AND Prompt Window opens with summary streaming in ResponseView
2. **Given** user has NO text selected, **When** user presses ⌥+Tab, **Then** toast shows "✨ Completing..." AND autocomplete happens (existing behavior)
3. **Given** summary is displayed in Prompt Window, **When** user clicks Copy or presses ⌘+C, **Then** summary is copied to clipboard
4. **Given** summary is displayed in Prompt Window, **When** user clicks Insert or presses ⌘+↵, **Then** summary replaces original selection
5. **Given** Prompt Window is open with summary, **When** user presses Escape, **Then** window closes cleanly

---

### User Story 2 - Prompt Mode: Summarize Button (Priority: P1) 🎯 MVP

As a user who wants more control, I want to select text, activate the Extremis prompt (⌘+⇧+Space), and see a secondary "Summarize" button that I can click for instant summarization without typing.

**Why this priority**: One-click option available, no typing required. Button is secondary so users can still type custom instructions as primary action.

**Independent Test**: Select text → Press ⌘+⇧+Space → See "Summarize" button (secondary) → Click → Get summary

**Acceptance Scenarios**:

1. **Given** user has text selected, **When** user presses ⌘+⇧+Space, **Then** prompt window shows with secondary "Summarize" button visible
2. **Given** user has NO text selected, **When** user presses ⌘+⇧+Space, **Then** prompt window shows WITHOUT "Summarize" button (existing behavior)
3. **Given** "Summarize" button is visible, **When** user clicks it, **Then** AI generates a concise summary of selected text in ResponseView
4. **Given** user prefers custom instruction, **When** user types in the prompt field instead of clicking button, **Then** typed instruction takes priority
5. **Given** prompt window opens with selection, **When** window appears, **Then** it opens faster (clipboard capture skipped)

---

### User Story 3 - Custom Summary via Typed Instruction (Priority: P2)

As a user who wants specific summary formats, I want to type custom instructions like "summarize in 3 bullet points" or "TLDR" in the prompt window.

**Why this priority**: Provides flexibility for power users who want specific formats without learning new UI.

**Independent Test**: Select text → Press ⌘+⇧+Space → Type "summarize in bullet points" → Press Enter → Receive bulleted summary

**Acceptance Scenarios**:

1. **Given** user has text selected, **When** user types "summarize", **Then** AI generates a concise summary
2. **Given** user types "summarize in 3 bullet points", **When** AI generates response, **Then** summary is formatted as exactly 3 bullet points
3. **Given** user types "TLDR", **When** AI processes, **Then** a one-sentence summary is returned
4. **Given** user types "summarize this email", **When** context is an email thread, **Then** summary includes key points, action items, and decisions

---

### User Story 3 - Adjustable Summary Length (Priority: P2)

As a user viewing a summary, I want options to make the summary shorter or longer so I can get the right level of detail for my needs.

**Why this priority**: Different contexts require different summary lengths - a quick glance vs. a detailed overview.

**Independent Test**: Can be tested by generating a summary, clicking "Make Shorter", and seeing a more concise version appear.

**Acceptance Scenarios**:

1. **Given** summary panel shows a summary, **When** user clicks "Shorter" button, **Then** AI regenerates a more concise version (50% fewer words)
2. **Given** summary panel shows a summary, **When** user clicks "Longer" button, **Then** AI regenerates with more detail (50% more words)
3. **Given** summary is at minimum length (1 sentence), **When** user clicks "Shorter", **Then** button is disabled with tooltip "Already at minimum"
4. **Given** length adjustment is in progress, **When** new summary loads, **Then** previous summary remains visible until new one is ready

---

### User Story 4 - Summary Format Options (Priority: P3)

As a power user, I want to choose summary formats (paragraph, bullet points, key takeaways, action items) via quick buttons or preferences.

**Why this priority**: Different content types benefit from different summary formats - meetings need action items, articles need key points.

**Independent Test**: Can be tested by selecting meeting notes, clicking "Action Items" format, and receiving extracted action items.

**Acceptance Scenarios**:

1. **Given** summary panel is shown, **When** user clicks "Bullets" format button, **Then** summary regenerates as bullet points
2. **Given** summary panel is shown, **When** user clicks "Key Points" format, **Then** summary shows numbered key takeaways
3. **Given** text contains action items, **When** user clicks "Actions" format, **Then** only actionable items are extracted
4. **Given** user sets default format in preferences, **When** summarizing next time, **Then** default format is used automatically

---

### User Story 5 - Insert Summary into Document (Priority: P3)

As a user who needs to add a summary to my document, I want to insert the generated summary directly at my cursor position.

**Why this priority**: Useful for creating executive summaries, meeting notes, or TLDR sections within documents.

**Independent Test**: Can be tested by summarizing selected text, then clicking "Insert" to place the summary at the cursor.

**Acceptance Scenarios**:

1. **Given** summary is displayed, **When** user clicks "Insert" or presses ⌘+↵, **Then** summary is inserted at the original cursor position
2. **Given** summary is inserted, **When** insertion completes, **Then** panel closes and cursor is after inserted text
3. **Given** user is in a read-only field, **When** user clicks "Insert", **Then** fallback to copy with notification "Copied - field is read-only"

---

### Edge Cases

- **No text selected**: When summarize hotkey is pressed with no selection, show "Please select text to summarize" message
- **Selection too short**: When selected text is under 50 characters, show "Text too short to summarize. Select more content."
- **Selection too long**: When selected text exceeds 100K characters, intelligently truncate with notice "Summarizing first 100K characters"
- **LLM unavailable**: When provider is not configured, show "Configure an LLM provider in Preferences to use summarization"
- **Network error during summarization**: Show error with "Retry" button, preserve selected text context
- **Empty summary returned**: If LLM returns empty/invalid response, retry once then show error
- **Multiple monitors**: Summary panel appears on the same screen as the source window
- **Full-screen apps**: Panel floats above full-screen applications

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST register a dedicated summarization hotkey (default: ⌥+S) that works globally
- **FR-002**: System MUST capture selected text from the active application when summarize is triggered
- **FR-003**: System MUST display a floating summary panel with loading state within 500ms of activation
- **FR-004**: System MUST stream the summary response from the LLM for perceived performance
- **FR-005**: System MUST provide "Copy" functionality to copy summary to clipboard
- **FR-006**: System MUST provide "Insert" functionality to insert summary at cursor position
- **FR-007**: System MUST provide "Shorter" and "Longer" buttons to adjust summary length
- **FR-008**: System MUST provide format options: Paragraph, Bullets, Key Points, Action Items
- **FR-009**: System MUST integrate with existing LLM providers (OpenAI, Anthropic, Gemini, Ollama)
- **FR-010**: System MUST handle the "summarize" instruction through the existing prompt window
- **FR-011**: System MUST allow users to configure the summarization hotkey in Preferences
- **FR-012**: System MUST preserve user's clipboard content during operations
- **FR-013**: System MUST work with text selected in any macOS application
- **FR-014**: System MUST gracefully handle accessibility permission requirements

### Key Entities

- **SummaryRequest**: Contains selected text, source application, requested format, and length preference
- **SummaryResult**: The generated summary with format type, word count, and generation metadata
- **SummaryFormat**: Enum of supported formats (paragraph, bullets, keyPoints, actionItems)
- **SummaryLength**: Enum of length preferences (short, medium, long, custom word count)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Summary panel appears within 500ms of hotkey press in 95% of activations
- **SC-002**: First summary token streams within 2 seconds of request for 90% of requests
- **SC-003**: Users can complete summarize → copy workflow in under 5 seconds for typical text
- **SC-004**: Summarization works correctly for 95%+ of text selections across supported applications
- **SC-005**: Summary accuracy rated 4+/5 by users for preserving key information
- **SC-006**: Memory footprint increases by less than 10MB when summary panel is active
