# Feature Specification: Human-in-Loop Tool Approval

**Feature Branch**: `011-tool-approval`
**Created**: 2026-01-20
**Status**: Draft
**Input**: User description: "Build human in loop approval system for tool calls"

## Clarifications

### Session 2026-01-20

- Q: What is the default approval mode for new installations? → A: All tools require approval by default (maximum safety, opt-in trust)
- Q: Should there be a timeout for approval decisions? → A: No timeout - wait indefinitely for user decision
- Q: What defines "similar" for session memory matching? → A: Tool name only - ignore arguments entirely

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review and Approve Tool Before Execution (Priority: P1)

When the LLM requests to execute a tool, the user sees a preview of what the tool will do and can approve or reject it before any action is taken. This ensures users maintain control over potentially impactful operations like creating GitHub issues, sending Slack messages, or modifying files.

**Why this priority**: This is the core value proposition - preventing unintended actions and giving users confidence that the AI won't make changes without their explicit consent. Without this, users may avoid using tool-enabled features entirely.

**Independent Test**: Can be fully tested by triggering an LLM response that requests a tool call, then verifying the approval UI appears and execution only proceeds after user action.

**Acceptance Scenarios**:

1. **Given** the LLM generates a response requesting a tool call (e.g., `github_create_issue`), **When** the response is received, **Then** the tool is NOT executed automatically, and the user sees a review UI showing the tool name, connector, and arguments.

2. **Given** a tool call is pending user approval, **When** the user clicks "Approve" or presses a keyboard shortcut, **Then** the tool executes immediately and the UI updates to show execution progress.

3. **Given** a tool call is pending user approval, **When** the user clicks "Reject" or presses a keyboard shortcut, **Then** the tool is NOT executed, the LLM is informed of the rejection, and the conversation continues.

4. **Given** multiple tool calls are pending in the same round, **When** the user reviews them, **Then** they can approve or reject each tool individually or use batch actions (approve all/reject all).

---

### User Story 2 - Configure Auto-Approval Rules (Priority: P2)

Users can configure rules to automatically approve certain tools based on their connector, tool name, or other criteria. This reduces friction for trusted, low-risk operations while maintaining approval for sensitive actions.

**Why this priority**: Power users who frequently use tools will want to streamline their workflow. This feature builds on P1 and is valuable but not essential for initial release.

**Independent Test**: Can be fully tested by setting an auto-approval rule in preferences, then verifying matching tools execute without showing approval UI.

**Acceptance Scenarios**:

1. **Given** the user is in the Preferences window, **When** they navigate to the Tool Approval settings, **Then** they can see and manage their auto-approval rules.

2. **Given** the user creates an auto-approval rule for a specific tool (e.g., `github_search_issues`), **When** the LLM requests that tool, **Then** the tool executes automatically without showing the approval UI.

3. **Given** the user creates an auto-approval rule for an entire connector (e.g., all tools from `github-mcp`), **When** the LLM requests any tool from that connector, **Then** those tools execute automatically.

4. **Given** no auto-approval rule matches a tool, **When** the LLM requests that tool, **Then** the approval UI is shown as normal.

---

### User Story 3 - Session-Based Approval Memory (Priority: P3)

Within a single session, if a user approves a specific tool, the system remembers this and can optionally auto-approve subsequent requests for the same tool (regardless of arguments).

**Why this priority**: This is a convenience feature that reduces repetitive approvals. It's valuable for iterative workflows but not essential for core functionality.

**Independent Test**: Can be fully tested by approving a tool call, having the LLM request the same tool again, and verifying the system either auto-approves or prompts with a "remember this session" option.

**Acceptance Scenarios**:

1. **Given** a user approves a tool call with "Remember for this session" checked, **When** the same tool is requested again in the same session (with any arguments), **Then** it auto-approves without showing the UI.

2. **Given** a user approved a tool in a previous session, **When** a new session starts and the same tool is requested, **Then** the approval UI is shown (session memory does not persist).

3. **Given** a user has session-remembered approvals, **When** the session ends or user clicks "Clear session approvals", **Then** all session-based auto-approvals are cleared.

---

### Edge Cases

- What happens when the user closes the approval UI without approving or rejecting? The tool is treated as rejected with a "user dismissed" reason.
- How does the system handle network timeout during tool execution after approval? The tool shows a failed state with timeout error, and the user can retry.
- What happens when the LLM requests a tool from a disconnected connector? The approval UI shows a warning that the connector is disconnected, and execution is blocked until reconnected.
- How does approval work when multiple tools are requested simultaneously? Each tool shows in a list, user can batch-approve/reject or handle individually.
- What if the user force-quits the app while a tool is pending approval? On next launch, no pending approvals remain (they are not persisted across app restarts).
- What if the user doesn't respond to the approval prompt? The system waits indefinitely; there is no automatic timeout or auto-rejection.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST intercept all tool calls before execution and require explicit user approval unless an auto-approval rule matches. By default, no auto-approval rules exist; all tools require approval on fresh installations.
- **FR-002**: System MUST display a clear, readable preview of pending tool calls including tool name, connector source, and human-readable argument summary.
- **FR-003**: Users MUST be able to approve or reject each pending tool call individually.
- **FR-004**: Users MUST be able to approve all or reject all pending tool calls when multiple are queued.
- **FR-005**: System MUST support keyboard shortcuts for approve (Enter/Return) and reject (Escape) actions.
- **FR-006**: System MUST inform the LLM when a tool call is rejected, allowing the conversation to continue without execution.
- **FR-007**: System MUST support configurable auto-approval rules based on tool name pattern or connector.
- **FR-008**: Auto-approval rules MUST be persisted in user preferences.
- **FR-009**: System MUST support session-scoped approval memory that clears when the session ends.
- **FR-010**: System MUST show clear visual distinction between pending, approved-executing, completed, and rejected tool states.
- **FR-011**: System MUST allow users to cancel a tool execution after approval but before completion.
- **FR-012**: System MUST log all tool approval decisions for user review within the session.

### Key Entities

- **ToolApprovalRequest**: Represents a tool call awaiting user approval - includes tool call details, timestamp, and approval state (pending/approved/rejected/cancelled).
- **ApprovalRule**: User-defined rule for auto-approval - includes match criteria (connector pattern, tool name pattern), created date, and enabled status.
- **SessionApprovalMemory**: Transient storage of tool names that have been approved with "remember" flag in the current session. Matching is by tool name only (arguments are ignored).
- **ApprovalDecision**: Record of a user's decision on a tool call - includes action taken (approved/rejected), timestamp, and optional "remember" flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can review and decide on a tool call within 5 seconds of it appearing (UI must be responsive and clear).
- **SC-002**: Auto-approval rules reduce manual approval actions by at least 50% for users who configure them.
- **SC-003**: 95% of tool approval workflows complete without requiring the user to consult documentation.
- **SC-004**: Users report feeling "in control" of tool execution in qualitative feedback (survey metric: 4+ out of 5 on control).
- **SC-005**: Zero unintended tool executions occur (tools only run when explicitly approved or matching auto-approval rules).
- **SC-006**: Tool approval flow does not add more than 1 second of delay to the user's perceived response time when auto-approval applies.
