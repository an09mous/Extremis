# Feature Specification: Prompting Improvements & Mode Simplification

**Feature Branch**: `008-prompting-improvements`
**Created**: 2026-01-10
**Status**: Draft
**Input**: User description: "Improve memory prompting and sunsetting autocompletion. Need to remove autocomplete fully as it is not a product market fit. Improving prompting for quick mode and magic mode."

## Clarifications

### Session 2026-01-10

- Q: What should happen when Option+Tab is pressed with no text selected? → A: Do nothing silently (no-op)
- Q: What are the scope changes for mode simplification? → A: Remove autocomplete and auto-generation entirely. Quick Mode remains (opens when selection exists). Chat Mode opens when no selection. Preceding/succeeding text capture removed for privacy reasons.
- Q: Context capture behavior? → A: No preceding/succeeding text capture. Only AX metadata (app name, window title) + selected text if present. Privacy-focused approach.
- Q: Why remove preceding/succeeding text? → A: Privacy concern - users don't want AI automatically copying screen text. Feature not adding sufficient value.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove Autocomplete & Auto-generation Features (Priority: P1)

As a user, I no longer have access to autocomplete (Option+Tab without selection) or auto-generation features because they have been sunset due to lack of product-market fit and privacy concerns.

**Why this priority**: Feature removal is the foundation for the simplified, privacy-respecting interaction model.

**Independent Test**: Can be fully tested by pressing Option+Tab without text selection and verifying no action occurs; verify no auto-generation code paths exist.

**Acceptance Scenarios**:

1. **Given** the user has no text selected, **When** they press Option+Tab, **Then** the system does nothing silently (no-op, no error message)
2. **Given** auto-generation code exists, **When** the feature is removed, **Then** all auto-generation code paths are removed or disabled
3. **Given** a user has used autocomplete/auto-generation before, **When** they upgrade to this version, **Then** no errors occur and the app functions normally

---

### User Story 2 - Remove Preceding/Succeeding Text Capture (Priority: P1)

As a user concerned about privacy, I want Extremis to stop automatically capturing surrounding text from my screen via clipboard markers.

**Why this priority**: Privacy is a core user concern. Removing automatic text capture builds trust.

**Independent Test**: Can be tested by triggering Extremis and verifying no preceding/succeeding text appears in context.

**Acceptance Scenarios**:

1. **Given** the clipboard marker capture code exists, **When** the feature is removed, **Then** no preceding/succeeding text is captured
2. **Given** I trigger Extremis, **When** context is captured, **Then** only AX metadata (app name, window title) and selected text (if any) are included
3. **Given** I have text before/after my cursor, **When** I trigger Extremis without selection, **Then** that surrounding text is NOT captured

---

### User Story 3 - Selection-Based Mode Routing (Priority: P1)

As a user, when I trigger Extremis (Cmd+Shift+Space), the mode that opens depends on whether I have text selected: Quick Mode with selection, Chat Mode without.

**Why this priority**: Clear, predictable behavior based on user intent.

**Independent Test**: Can be tested by triggering with and without selection.

**Acceptance Scenarios**:

1. **Given** I have text selected, **When** I press Cmd+Shift+Space, **Then** Quick Mode opens with the selection as context
2. **Given** I have no text selected, **When** I press Cmd+Shift+Space, **Then** Chat Mode opens with AX metadata as context
3. **Given** I have text selected, **When** I press Option+Tab, **Then** Magic Mode summarizes the selection (unchanged behavior)

---

### User Story 4 - Improved Quick Mode Prompting (Priority: P1)

As a user, when I use Quick Mode (Cmd+Shift+Space with selection), I want the LLM to understand my request better and provide more relevant, contextually-aware responses.

**Why this priority**: Quick Mode is a primary interaction pattern. Better prompting directly improves user satisfaction.

**Independent Test**: Can be tested by triggering Quick Mode, entering an instruction, and evaluating response quality.

**Acceptance Scenarios**:

1. **Given** I have selected text and captured context, **When** I provide an instruction, **Then** the response demonstrates clear understanding of the context
2. **Given** I'm working in a code editor, **When** I ask for help with code, **Then** the response matches the programming language and coding style
3. **Given** I'm composing an email, **When** I ask for writing assistance, **Then** the response maintains appropriate professional tone
4. **Given** I provide a vague instruction, **When** the LLM responds, **Then** it makes reasonable assumptions based on context

---

### User Story 5 - Improved Chat Mode Prompting (Priority: P1)

As a user, when I use Chat Mode (Cmd+Shift+Space without selection), I want a conversational interface that understands my application context.

**Why this priority**: Chat Mode becomes the default for no-selection scenarios.

**Independent Test**: Can be tested by triggering Chat Mode and evaluating conversation quality.

**Acceptance Scenarios**:

1. **Given** I have no selection, **When** Chat Mode opens, **Then** AX metadata (app name, window title) is available as context
2. **Given** I'm in a specific application, **When** I ask questions, **Then** the LLM understands the application context
3. **Given** I continue a conversation, **When** session memory is active, **Then** prior context is maintained

---

### User Story 6 - Improved Magic Mode Prompting (Priority: P2)

As a user, when I use Magic Mode (Option+Tab with text selected) for summarization, I want better-quality summaries.

**Why this priority**: Magic Mode remains as the quick-summarization feature. Improving its quality maximizes value.

**Independent Test**: Can be tested by selecting text and triggering Magic Mode to evaluate summary quality.

**Acceptance Scenarios**:

1. **Given** I select a long passage of text, **When** I trigger Magic Mode, **Then** the summary captures main points
2. **Given** I select technical content, **When** I trigger Magic Mode, **Then** the summary preserves technical accuracy
3. **Given** I select conversational content, **When** I trigger Magic Mode, **Then** the summary identifies key action items

---

### User Story 7 - Enhanced Memory/Session Context Prompting (Priority: P2)

As a user engaged in a multi-turn conversation, I want the session summary to be effectively used for coherent context.

**Why this priority**: Memory persistence optimization ensures users get the intended benefit from the feature.

**Independent Test**: Can be tested by having extended conversations that trigger summarization.

**Acceptance Scenarios**:

1. **Given** a conversation has been summarized, **When** I continue chatting, **Then** the LLM references information naturally
2. **Given** the session summary contains key facts, **When** I ask about those facts later, **Then** the LLM recalls them accurately

---

### Edge Cases

- What happens when Chat Mode is triggered with minimal AX context (app not recognized)?
- How does the system behave if Magic Mode is triggered with very short selection (< 10 characters)?
- What if the session summary itself is very long - is it further truncated?
- How are prompt template loading failures handled gracefully?

## Requirements *(mandatory)*

### Functional Requirements

#### Feature Removal
- **FR-001**: System MUST silently ignore Option+Tab when no text is selected (no-op behavior)
- **FR-002**: System MUST remove all autocomplete-specific code paths
- **FR-003**: System MUST remove all auto-generation code paths
- **FR-004**: System MUST remove preceding/succeeding text capture (clipboard marker method)
- **FR-005**: System MUST update any user-facing documentation that references removed features

#### Mode Behavior
- **FR-006**: System MUST open Quick Mode when Cmd+Shift+Space is pressed WITH text selected
- **FR-007**: System MUST open Chat Mode when Cmd+Shift+Space is pressed WITHOUT text selected
- **FR-008**: System MUST retain Magic Mode (Option+Tab) for summarization when text is selected

#### Context Capture
- **FR-009**: System MUST capture only AX metadata (application name, window title, bundle ID) as base context
- **FR-010**: System MUST include selected text in context when selection exists
- **FR-011**: System MUST NOT capture preceding or succeeding text via clipboard markers

#### Quick Mode Prompting
- **FR-012**: System MUST use an enhanced instruction prompt template that includes context-type awareness
- **FR-013**: System MUST provide context hints to the LLM (application type, content format indicators)
- **FR-014**: System MUST guide the LLM to produce direct, actionable responses without unnecessary preambles

#### Chat Mode Prompting
- **FR-015**: System MUST use an enhanced chat prompt template that leverages AX metadata
- **FR-016**: System MUST instruct the LLM to match output style/tone to the detected application context

#### Magic Mode Prompting
- **FR-017**: System MUST use an enhanced summarization prompt that prioritizes key information extraction
- **FR-018**: System MUST handle different content types (technical, conversational, narrative) appropriately

#### Memory/Session Prompting
- **FR-019**: System MUST format session summaries in a way that enables natural conversation continuation
- **FR-020**: System MUST instruct the LLM to treat summarized context as established facts

### Key Entities

- **PromptTemplate**: Template files (.hbs) defining how context and instructions are formatted for LLM consumption
- **SessionSummary**: Compressed representation of prior conversation for memory persistence
- **Context**: AX metadata (app name, window title, bundle ID) + optional selected text

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete interactions without confusion about removed features
- **SC-002**: Quick Mode responses are relevant to the captured context in 90%+ of test cases
- **SC-003**: Chat Mode provides useful conversations with AX-only context
- **SC-004**: Magic Mode summaries accurately capture the main points of selected text
- **SC-005**: Multi-turn conversations maintain coherence after summarization occurs
- **SC-006**: No increase in error rates or crashes after feature removal
- **SC-007**: Prompt templates are maintainable and externalized (no hardcoded prompts in code)
- **SC-008**: All autocomplete, auto-generation, and clipboard marker code is removed (no dead code)

## Assumptions

- The existing prompt template system (.hbs files) will be used for all prompt improvements
- Session summarization is already functional from the memory-persistence feature
- AX metadata provides sufficient context for Chat Mode conversations
- Users prefer privacy over automatic context capture
- Quick Mode and Chat Mode UI already exist
