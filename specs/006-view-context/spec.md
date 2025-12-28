# Feature Specification: View Context Button

**Feature Branch**: `006-view-context`
**Created**: 2025-12-28
**Status**: Draft
**Input**: User description: "Add a view button in the header below Extremis header to view the full current context. For example, in the image it's showing Code and text selected. Clicking on the view button, I should be able to view the complete context whatever Extremis has captured."

## Design Philosophy

**Core Insight**: Users need transparency into what context Extremis has captured before generating AI responses. Currently, only a truncated preview is shown (e.g., "Code (text selected: {..."). A "View" button provides full visibility into the captured context.

**Current State**: The ContextBanner component displays a single-line truncated summary of context (app name, window title, selected text preview). Users cannot see the full captured text including preceding/succeeding text, metadata, or source details.

**Key Change**: Add a clickable "View" button to the ContextBanner that opens a modal or popover displaying the complete captured context in a readable, organized format.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Full Context (Priority: P1) 🎯 MVP

As a user who has selected text or activated Extremis from an application, I want to view the complete captured context, so I can verify what information Extremis will use when generating responses.

**Why this priority**: Core functionality - users need to trust and verify what context the AI will use before generating responses.

**Independent Test**: Activate Extremis with selected text → See context banner with "View" button → Click button → See full context displayed

**Acceptance Scenarios**:

1. **Given** Extremis is activated with captured context, **When** user sees the context banner, **Then** a "View" button/icon is visible next to the context summary
2. **Given** context banner with View button is visible, **When** user clicks the View button, **Then** a modal/popover opens displaying the full context
3. **Given** context viewer is open, **When** user reviews the content, **Then** they can see: source application name, window title, selected text (full), preceding text (if any), succeeding text (if any), and any app-specific metadata
4. **Given** context viewer is open, **When** user clicks outside or presses Escape, **Then** the viewer closes and returns to prompt input

---

### User Story 2 - Copy Context (Priority: P2)

As a user viewing the full context, I want to copy specific parts or all of the captured context, so I can use it elsewhere or share it.

**Why this priority**: Useful secondary feature - allows users to extract and reuse captured context.

**Independent Test**: Open context viewer → Click copy button → Paste in another app → Verify content matches

**Acceptance Scenarios**:

1. **Given** context viewer is open, **When** user clicks "Copy All" button, **Then** entire context is copied to clipboard
2. **Given** context viewer is open with text content, **When** user selects text and copies, **Then** selected portion is copied to clipboard
3. **Given** context is successfully copied, **When** copy action completes, **Then** user sees brief visual feedback (e.g., "Copied!")

---

### Edge Cases

- What happens when there is no context captured (no selected text, no preceding/succeeding text)?
  - View button should be hidden or disabled
- What happens when context contains very long text (e.g., 10,000+ characters)?
  - Context viewer should be scrollable with performance optimization
- What happens when context contains special characters or code?
  - Content should be displayed with proper escaping and syntax preservation
- What happens when metadata is empty or minimal?
  - Show only available sections, hide empty ones

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a "View" button/icon in the context banner when context is available
- **FR-002**: System MUST open a context viewer when the View button is clicked
- **FR-003**: Context viewer MUST display the source application name and bundle identifier
- **FR-004**: Context viewer MUST display the window title (if available)
- **FR-005**: Context viewer MUST display the full selected text (if any) with clear labeling
- **FR-006**: Context viewer MUST display preceding text (if any) with clear labeling
- **FR-007**: Context viewer MUST display succeeding text (if any) with clear labeling
- **FR-008**: Context viewer MUST display app-specific metadata (Slack channel, Gmail subject, GitHub PR number, etc.) when available
- **FR-009**: Context viewer MUST be dismissible via click outside, Escape key, or close button
- **FR-010**: System MUST allow copying entire context or selected portions
- **FR-011**: View button MUST be hidden or disabled when no context is captured

### Key Entities

- **Context**: The main captured context containing source info, selected text, preceding/succeeding text, and metadata
- **ContextSource**: Information about the source application (name, bundle ID, window title, URL)
- **ContextMetadata**: App-specific metadata (Slack, Gmail, GitHub, or generic)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can access full context within 2 clicks (click View button → see content)
- **SC-002**: Context viewer opens within 200ms of button click
- **SC-003**: All captured context fields are displayed when present (100% coverage)
- **SC-004**: Context viewer remains responsive with text up to 50,000 characters
- **SC-005**: Copy functionality works correctly for all content types (plain text, code, special characters)
- **SC-006**: User can dismiss the viewer using keyboard (Escape) or mouse (click outside/close button)

## Assumptions

- The context data structure (Context, ContextSource, ContextMetadata) remains unchanged
- The ContextBanner component is the appropriate location for the View button
- A sheet presentation (SwiftUI `.sheet`) is appropriate for macOS design conventions
- The prompt window's viewModel already has access to the full context object via `currentContext`
