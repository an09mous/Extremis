# Tool Approval Architecture

This document describes the human-in-loop tool approval mechanism in Extremis, providing security controls for MCP (Model Context Protocol) tool execution.

## Overview

The tool approval system ensures users maintain control over which tools the LLM can execute. It provides:
- **Session memory** for tools approved with "remember for session"
- **Interactive UI** for manual approval decisions
- **Audit logging** of all approval decisions

> **Note:** This is Phase 1 of the tool approval implementation. Phase 2 will add persistent approval rules for automatic allow/deny based on patterns.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TOOL APPROVAL FLOW                                   │
└─────────────────────────────────────────────────────────────────────────────┘

   LLM Response with Tool Calls
              │
              ▼
   ┌──────────────────────┐
   │ToolEnabledChatService│
   │  parseToolCalls()    │
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────┐
   │  ToolApprovalManager │
   │  requestApproval()   │
   └──────────┬───────────┘
              │
              ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │                    EVALUATION (Phase 1)                         │
   │  ┌──────────────────┐                                          │
   │  │  Session Memory  │                                          │
   │  │                  │                                          │
   │  └────────┬─────────┘                                          │
   │           │                                                     │
   │           ▼                                                     │
   │    Session-Approved or Needs User Approval                     │
   └─────────────────────────────────────────────────────────────────┘
              │
              │ (Not in session memory)
              ▼
   ┌──────────────────────┐
   │ Needs User Approval  │
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                    UI LAYER                                      │
   │  ┌─────────────────────┐    ┌─────────────────────────────────┐ │
   │  │PromptWindowController│    │     ToolApprovalView           │ │
   │  │(ToolApprovalUIDelegate)│ → │  - Request list                │ │
   │  └──────────┬──────────┘    │  - Allow/Deny buttons           │ │
   │             │               │  - Remember checkbox            │ │
   │             │               │  - Keyboard shortcuts           │ │
   │             │               └─────────────────────────────────┘ │
   └─────────────┴───────────────────────────────────────────────────┘
              │
              ▼
   ┌──────────────────────┐
   │  ApprovalDecision    │  ← Recorded in session audit log
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────┐
   │   ToolExecutor       │  (Only approved tools execute)
   └──────────────────────┘
```

## Components

### 1. Data Models (`ToolApprovalModels.swift`)

#### ApprovalState
```swift
enum ApprovalState: Equatable {
    case pending           // Waiting for user decision
    case approved          // User approved
    case denied(reason: String?)
    case dismissed         // User dismissed without deciding
}
```

#### ApprovalAction
```swift
enum ApprovalAction: String, Codable {
    case approved         // User clicked approve
    case denied           // User clicked deny
    case dismissed        // User dismissed without deciding
    case sessionApproved  // Auto-approved via session memory
}
```

#### ToolApprovalRequest
Transient object for pending approvals:
```swift
struct ToolApprovalRequest: Identifiable {
    let id: String              // Same as tool call ID
    let toolCall: ToolCall
    let chatToolCall: ChatToolCall  // UI-friendly representation
    let requestedAt: Date
    var state: ApprovalState
    var rememberForSession: Bool
}
```

#### ApprovalDecision
Audit record of a decision:
```swift
struct ApprovalDecision: Codable, Identifiable {
    let id: UUID
    let requestId: String
    let toolName: String
    let connectorId: String
    let action: ApprovalAction
    let rememberForSession: Bool
    let decidedAt: Date
    let reason: String?
}
```

#### SessionApprovalMemory
In-memory storage for session-scoped approvals:
```swift
@MainActor
final class SessionApprovalMemory {
    private(set) var approvedToolNames: Set<String>
    let sessionId: String

    func remember(toolName: String)
    func isApproved(toolName: String) -> Bool
    func clear()
}
```

### 2. ToolApprovalManager (`ToolApprovalManager.swift`)

Central service coordinating the approval workflow.

#### Key Properties
```swift
@MainActor
final class ToolApprovalManager {
    static let shared = ToolApprovalManager()

    weak var uiDelegate: ToolApprovalUIDelegate?
    private(set) var sessionDecisions: [ApprovalDecision]  // Audit log
}
```

#### Evaluation Flow (Phase 1)
1. **Session memory** - Check if tool was previously approved this session
2. **User prompt** - If not in session memory, prompt user

#### Main Entry Point
```swift
func requestApproval(
    for toolCalls: [ToolCall],
    sessionMemory: SessionApprovalMemory?
) async -> ApprovalResult
```

Returns `ApprovalResult` containing:
- `approvedIds: Set<String>` - Tool call IDs approved for execution
- `decisions: [ApprovalDecision]` - All decisions for audit logging

### 3. UI Components

#### ToolApprovalUIDelegate Protocol
```swift
@MainActor
protocol ToolApprovalUIDelegate: AnyObject {
    func showApprovalUI(
        for requests: [ToolApprovalRequest],
        completion: @escaping ([String: ApprovalDecision]) -> Void
    )
    func dismissApprovalUI()
    func updateApprovalState(requestId: String, state: ApprovalState)
}
```

Implemented by `PromptWindowController`.

#### ToolApprovalView (`ToolApprovalView.swift`)
Main approval UI showing:
- Header with pending count badge
- List of pending tool requests
- "Remember for session" checkbox
- Allow/Deny buttons for individual tools
- "Allow All" / "Deny All" bulk actions
- Keyboard shortcuts

**Keyboard Shortcuts:**
| Shortcut | Action |
|----------|--------|
| `Option+Return` | Allow All |
| `Option+Escape` | Deny All |
| `Return` | Allow focused |
| `Escape` | Deny focused |

#### ApprovalRequestDisplayModel
View-friendly model for UI display:
```swift
struct ApprovalRequestDisplayModel: Identifiable {
    let id: String
    let toolName: String
    let connectorId: String      // Human-readable connector name
    let argumentsSummary: String
    let state: ApprovalState
    var rememberForSession: Bool
}
```

### 4. Integration with Tool Execution

#### ToolEnabledChatService Integration
```swift
// In ToolEnabledChatService.generateToolEnabledChatStream()

// 1. Parse tool calls from LLM response
let toolCalls = parseToolCalls(from: response)

// 2. Request approval
let approvalResult = await approvalManager.requestApproval(
    for: toolCalls,
    sessionMemory: sessionApprovalMemory
)

// 3. Only execute approved tools
let approvedToolCalls = toolCalls.filter {
    approvalResult.approvedIds.contains($0.id)
}

// 4. Execute approved tools
for toolCall in approvedToolCalls {
    let result = await toolExecutor.execute(toolCall)
    // ...
}
```

## Complete Flow Sequence

```
1. USER sends message
       │
       ▼
2. ToolEnabledChatService sends to LLM
       │
       ▼
3. LLM responds with tool_use blocks
       │
       ▼
4. ToolSchemaConverter.parseToolCalls()
   - Creates ToolCall objects with connectorID and connectorName
       │
       ▼
5. ToolApprovalManager.requestApproval()
   │
   ├─► For each tool call:
   │   │
   │   ├─► Check Session Memory
   │   │   └─► Previously approved? → Session-APPROVE
   │   │
   │   └─► No match? → Add to pendingRequests
   │
   ├─► If pendingRequests is empty:
   │   └─► Return ApprovalResult with session-approved decisions
   │
   └─► If pendingRequests exists:
       │
       ▼
6. waitForUserDecisions()
   │
   ├─► ToolApprovalUIDelegate.showApprovalUI()
   │   │
   │   ▼
   │ ┌─────────────────────────────────────────┐
   │ │      PromptWindowController              │
   │ │  - Creates PendingApprovalBatch          │
   │ │  - Sets up callbacks                     │
   │ │  - Shows ToolApprovalView overlay        │
   │ └─────────────────────────────────────────┘
   │   │
   │   ▼
   │ ┌─────────────────────────────────────────┐
   │ │        ToolApprovalView                  │
   │ │  - Displays pending tools                │
   │ │  - User clicks Allow/Deny                │
   │ │  - Or uses keyboard shortcuts            │
   │ └─────────────────────────────────────────┘
   │   │
   │   ▼
   │ User makes decision(s)
   │   │
   │   ▼
   └─► completion callback fires with decisions
       │
       ▼
7. Update Session Memory (if "remember" checked)
   │
   ▼
8. Return ApprovalResult
   │
   ▼
9. ToolEnabledChatService filters to approved tools
   │
   ▼
10. ToolExecutor.execute() for each approved tool
   │
   ▼
11. Tool results sent back to LLM
```

## Timeout Handling

- **Default timeout:** 5 minutes (300 seconds)
- If user doesn't respond, all pending requests are auto-denied
- Timeout task is cancelled if user makes decisions

```swift
private static let approvalTimeoutSeconds: UInt64 = 300

// In waitForUserDecisions():
let timeoutTask = Task {
    try? await Task.sleep(nanoseconds: Self.approvalTimeoutSeconds * 1_000_000_000)
    // Auto-deny all pending if timeout
}
```

## Session Memory

Session memory provides "remember for session" functionality:
- When a user approves a tool with "remember" checked, the tool name is stored in `SessionApprovalMemory`
- Subsequent calls to the same tool within the session are auto-approved
- Session memory is cleared when a new session starts
- Session memory is stored in-memory only (not persisted)

```swift
// Remember a tool for the session
memory.remember(toolName: "github_search_issues")

// Check if tool is approved
if memory.isApproved(toolName: "github_search_issues") {
    // Auto-approve
}
```

## UI Overlay Architecture

The approval UI appears as an overlay in `PromptWindowController`:

```swift
.overlay {
    if viewModel.showApprovalView && !viewModel.pendingApprovalRequests.isEmpty {
        ZStack {
            // Dimmed background covering entire view
            Color(NSColor.windowBackgroundColor).opacity(0.9)
                .ignoresSafeArea()

            // Approval view at bottom
            VStack {
                Spacer()
                ToolApprovalView(...)
                    .padding()
            }
        }
    }
}
```

This ensures:
- The approval UI takes focus
- Underlying content is visually dimmed
- User must make a decision before continuing

## Error Handling

```swift
enum ToolApprovalError: Error {
    case approvalCancelled
    case approvalTimeout
}
```

## Security Considerations

1. **No default auto-allow** - All tools require user approval or session memory
2. **Session memory is ephemeral** - Cleared when session ends
3. **Audit logging** - All decisions are recorded in `sessionDecisions`
4. **Timeout protection** - Prevents infinite hangs if UI callback fails

## Default Behavior

- All tools require manual approval on first use
- "Remember for session" allows skipping prompts for same tool within session
- Session memory does not persist across sessions

## Phase 2 Preview

Phase 2 will add:
- **Approval Rules** - Persistent rules for automatic allow/deny
- **Pattern Matching** - Glob patterns for tool/connector matching (e.g., `github_*`)
- **Rule Priority** - Deny rules take precedence over allow rules
- **Rule Management UI** - Add/edit/delete rules in Preferences

## Related Files

| File | Purpose |
|------|---------|
| `ToolApprovalModels.swift` | Data models and enums |
| `ToolApprovalManager.swift` | Central coordination service |
| `ToolApprovalView.swift` | SwiftUI approval UI |
| `ToolIndicatorView.swift` | Tool execution status display |
| `ChatToolCall.swift` | UI-friendly tool call model |
| `ToolCall.swift` | Core tool call model |
| `PromptWindowController.swift` | UI delegate implementation |
| `ToolEnabledChatService.swift` | Integration with LLM loop |
| `ConnectorsTab.swift` | Tool approval info display |
