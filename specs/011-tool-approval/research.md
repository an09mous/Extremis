# Research: Human-in-Loop Tool Approval

**Feature**: 011-tool-approval
**Date**: 2026-01-20

## Industry Best Practices Analysis

### 1. Claude Code Approach (Gold Standard)

**Decision**: Adopt Claude Code's hierarchical permission model with deny → allow → ask precedence.

**Rationale**: Claude Code's approach is the most mature and well-documented. It balances security with usability through:
- Deny rules block dangerous operations immediately
- Allow rules auto-approve safe commands if matched
- Ask rules prompt for approval (default behavior)
- Pattern matching with glob syntax for tools and connectors

**Alternatives Considered**:
- Simple on/off toggle (rejected: too binary, no granularity)
- Per-execution prompts only (rejected: causes approval fatigue)

### 2. UI Pattern Selection

**Decision**: Use inline approval card within chat panel (not modal dialog).

**Rationale**:
- Cursor, Cline, and modern AI tools favor inline approval over modal dialogs
- Reduces context switching - user stays in the conversation flow
- Allows reviewing multiple tool calls simultaneously
- Follows Apple HIG for non-disruptive confirmations

**Pattern**:
```
┌─────────────────────────────────────────────┐
│ 🔧 github_search_issues                     │
│                                             │
│ Tool wants to search GitHub issues:         │
│ • repo: "owner/repo"                        │
│ • query: "bug label:priority"               │
│                                             │
│ ☐ Remember for this session                 │
│                                             │
│     [Deny]  [Allow All]  [⏎ Allow]          │
└─────────────────────────────────────────────┘
```

**Alternatives Considered**:
- Modal sheet (rejected: blocks entire UI, bad for multiple tools)
- System notification (rejected: not in-context, easy to miss)
- Toast with action buttons (rejected: too small for detailed info)

### 3. Keyboard Shortcuts

**Decision**: Follow macOS HIG with these shortcuts:

| Action | Primary | Secondary | Notes |
|--------|---------|-----------|-------|
| Allow (approve) | `Return` | `⌘⏎` | Default action, rightmost button |
| Deny (reject) | `Escape` | | Cancel pattern |
| Allow All | `⌥⏎` | | Batch action |
| Deny All | `⌥Escape` | | Batch action |

**Rationale**:
- Return for primary action is standard macOS behavior
- Escape for cancel/reject is universal
- Option modifiers for batch operations follow system patterns

**Alternatives Considered**:
- Vim-style (y/n): Rejected - not discoverable for general users
- Function keys: Rejected - often remapped on Mac keyboards

### 4. State Machine Design

**Decision**: Extend existing `ToolCallState` with approval states.

**Rationale**: The existing state enum (`pending`, `executing`, `completed`, `failed`) fits naturally with new approval states. States become:

```swift
enum ToolCallState {
    case pendingApproval  // NEW: Awaiting user decision
    case approved         // NEW: User approved, ready to execute
    case denied           // NEW: User rejected
    case executing        // Existing: In progress
    case completed        // Existing: Success
    case failed           // Existing: Error
    case cancelled        // NEW: User cancelled after approval
}
```

**Flow**:
```
LLM requests tool → pendingApproval → [User decision]
                                    → approved → executing → completed/failed
                                    → denied → (inform LLM)
```

### 5. Auto-Approval Rules Pattern

**Decision**: Support connector-level and tool-name pattern matching with glob syntax.

**Rationale**: Claude Code and Cursor both use pattern matching. Supports:
- Exact tool match: `github_search_issues`
- Connector wildcard: `github-mcp:*`
- Tool prefix: `*_search_*`

**Storage**: Array of rule objects in UserDefaults via Preferences model.

```swift
struct ApprovalRule: Codable {
    let id: UUID
    let pattern: String      // Glob pattern
    let ruleType: RuleType   // .allow or .deny
    let createdAt: Date
    var isEnabled: Bool
}
```

### 6. Session Memory Design

**Decision**: Tool-name-only matching (ignore arguments) per spec clarification.

**Rationale**:
- Simpler implementation
- Reduces approval fatigue for iterative workflows
- User trusting a tool once likely trusts it for any arguments
- Aligns with Claude Code's session-based permissions

**Storage**: In-memory Set<String> of approved tool names, cleared on session end.

### 7. Rejection Feedback to LLM

**Decision**: Return structured rejection result that LLM can understand.

**Rationale**: The LLM needs to know the tool was rejected (not failed) so it can:
- Explain to user why the action wasn't taken
- Suggest alternative approaches
- Not retry the same tool call

**Format**:
```swift
ToolResult.failure(
    callID: call.id,
    toolName: call.toolName,
    error: ToolError(
        message: "Tool execution denied by user",
        code: .userDenied  // New error code
    ),
    duration: 0
)
```

## Codebase Integration Analysis

### Integration Point 1: ToolEnabledChatService

**Location**: `Extremis/Connectors/Services/ToolEnabledChatService.swift` lines 186-211

**Current Flow**:
```swift
let toolCalls = self.resolveToolCalls(...)
let chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
continuation.yield(.toolCallsStarted(chatToolCalls))
let results = await self.executeToolsWithUpdates(...)
```

**Integration Approach**: Insert approval gate between resolution and execution:
```swift
let toolCalls = self.resolveToolCalls(...)
let chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
continuation.yield(.toolCallsStarted(chatToolCalls))

// NEW: Request approval
let approved = await self.approvalManager.requestApproval(
    toolCalls: toolCalls,
    sessionMemory: sessionApprovalMemory
)

// Execute only approved tools
let approvedToolCalls = toolCalls.filter { approved.contains($0.id) }
let results = await self.executeToolsWithUpdates(toolCalls: approvedToolCalls, ...)
```

### Integration Point 2: PromptViewModel

**Location**: `Extremis/UI/PromptWindow/PromptWindowController.swift` lines 1010-1047

**Current Flow**: Event stream handler updates `activeToolCalls` and `isExecutingTools`.

**Integration Approach**: Add new event type and state:
```swift
@Published var pendingApprovalCalls: [ChatToolCall] = []
@Published var isAwaitingApproval: Bool = false

case .toolCallsNeedingApproval(let calls):
    pendingApprovalCalls = calls
    isAwaitingApproval = true
```

### Integration Point 3: ChatToolCall State Extension

**Location**: `Extremis/UI/PromptWindow/ChatToolCall.swift` line 178

**Current States**: `pending`, `executing`, `completed`, `failed`

**Addition**: Add `pendingApproval`, `approved`, `denied`, `cancelled`

**UI Updates**: Extend `ToolIndicatorView` to show approval UI when state is `pendingApproval`.

### Integration Point 4: Preferences Storage

**Location**: `Extremis/Core/Models/Preferences.swift` and `Extremis/Utilities/UserDefaultsHelper.swift`

**Current Pattern**: `Preferences` struct with Codable fields, `UserDefaultsHelper` with typed accessors.

**Addition**:
```swift
struct Preferences: Codable {
    // Existing...
    var toolApprovalEnabled: Bool = true
    var approvalRules: [ApprovalRule] = []
}
```

## Architecture Decisions

### 1. Approval Manager Service

**Decision**: Create `ToolApprovalManager` as a singleton service.

**Rationale**:
- Centralizes approval logic
- Manages session memory
- Coordinates between UI and execution layer
- Follows existing service patterns (e.g., `ConnectorRegistry.shared`)

### 2. Async Approval Flow

**Decision**: Use Swift Concurrency with continuation pattern for approval UI.

**Rationale**: The approval decision is inherently async (waiting for user input). Using `withCheckedContinuation` allows the execution flow to pause cleanly.

```swift
func requestApproval(for calls: [ToolCall]) async -> Set<String> {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            self.pendingContinuation = continuation
            self.showApprovalUI(for: calls)
        }
    }
}
```

### 3. UI Component Placement

**Decision**: Inline approval view within chat stream, not a separate overlay.

**Rationale**:
- Maintains conversation context
- Allows scrolling through multiple pending approvals
- Consistent with existing `ToolIndicatorView` pattern
- Less intrusive than modal

### 4. Test Strategy

**Decision**: Unit tests for approval logic, integration tests for UI flow.

**Test Coverage**:
- `ToolApprovalManager` rule matching logic
- Session memory storage/retrieval
- State transitions in `ChatToolCall`
- Keyboard shortcut handling
- Preferences persistence

## File Structure

### New Files
```
Extremis/
├── Core/
│   ├── Models/
│   │   └── ToolApprovalModels.swift    # ApprovalRule, ApprovalDecision enums
│   └── Services/
│       └── ToolApprovalManager.swift   # Central approval logic
├── UI/
│   └── PromptWindow/
│       └── ToolApprovalView.swift      # Inline approval UI component
└── Tests/
    └── Core/
        └── ToolApprovalManagerTests.swift
```

### Modified Files
```
- Preferences.swift              # Add approval settings
- UserDefaultsHelper.swift       # Add approval accessors
- ToolEnabledChatService.swift   # Add approval gate
- ChatToolCall.swift             # Extend state enum
- ToolIndicatorView.swift        # Add approval state rendering
- PromptWindowController.swift   # Coordinate approval UI
- GeneralTab.swift               # Add approval preferences section
- run-tests.sh                   # Register new test file
```

## Risk Mitigation

### Risk 1: Generation Flow Disruption
**Mitigation**: Keep approval logic in separate service; execution flow unchanged for auto-approved tools.

### Risk 2: UI Complexity
**Mitigation**: Extend existing `ToolIndicatorView` rather than creating entirely new component.

### Risk 3: State Management Bugs
**Mitigation**: Comprehensive unit tests for state transitions; follow existing patterns.

### Risk 4: Performance Impact
**Mitigation**: Auto-approval rules checked synchronously; no network calls in approval path.

## Sources

- Claude Code Permissions Documentation
- Apple Human Interface Guidelines - Dialogs and Confirmations
- Cursor AI Security Model
- Cline GitHub Repository
- MCP Security Best Practices
- Existing Extremis codebase patterns
