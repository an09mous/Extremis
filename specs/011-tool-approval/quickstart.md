# Quickstart: Human-in-Loop Tool Approval

**Feature**: 011-tool-approval
**Date**: 2026-01-20

## Overview

This guide covers implementing the human-in-loop tool approval system for Extremis. The feature intercepts MCP tool calls before execution and requires user approval unless auto-approval rules match.

## Prerequisites

- Xcode 15.0+
- macOS 13.0+ (Ventura)
- Existing Extremis codebase with MCP support (feature 010)

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                     ToolEnabledChatService                       │
│                                                                 │
│  LLM generates tool calls                                       │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────────┐                                            │
│  │ resolveToolCalls │                                           │
│  └────────┬────────┘                                            │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────┐                    │
│  │       ToolApprovalManager                │ ◄── NEW           │
│  │  ┌─────────────────────────────────┐    │                    │
│  │  │ Check auto-approval rules       │    │                    │
│  │  │ Check session memory            │    │                    │
│  │  │ Request user approval if needed │    │                    │
│  │  └─────────────────────────────────┘    │                    │
│  └────────┬────────────────────────────────┘                    │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │ executeToolsWithUpdates │ (only approved tools)              │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Core Models (P1 Foundation)

**Files to create:**
- `Extremis/Core/Models/ToolApprovalModels.swift`

**Key types:**
```swift
// Approval rule for auto-approve/deny
struct ApprovalRule: Codable, Identifiable, Equatable

// State of an approval request
enum ApprovalState: Equatable

// User action on an approval request
enum ApprovalAction: String, Codable

// Record of user decision
struct ApprovalDecision: Codable, Identifiable
```

**Integration:**
1. Add `toolApprovalEnabled` and `approvalRules` to `Preferences.swift`
2. Add convenience accessors to `UserDefaultsHelper.swift`

### Phase 2: Approval Manager Service (P1 Core)

**Files to create:**
- `Extremis/Core/Services/ToolApprovalManager.swift`

**Key responsibilities:**
1. Evaluate auto-approval rules
2. Manage session approval memory
3. Coordinate approval UI display
4. Record approval decisions

**Integration points:**
```swift
// In ToolEnabledChatService.generateWithToolsStream()
let toolCalls = self.resolveToolCalls(...)

// NEW: Get approval before execution
let approvedIds = await approvalManager.requestApproval(
    for: toolCalls,
    sessionMemory: currentSession.approvalMemory
)

let approvedCalls = toolCalls.filter { approvedIds.contains($0.id) }
let results = await self.executeToolsWithUpdates(toolCalls: approvedCalls, ...)
```

### Phase 3: Extended Tool States (P1 UI)

**Files to modify:**
- `Extremis/UI/PromptWindow/ChatToolCall.swift`

**State extension:**
```swift
enum ToolCallState: Equatable {
    case pendingApproval  // NEW
    case approved         // NEW
    case denied           // NEW
    case executing
    case completed
    case failed
    case cancelled        // NEW
}
```

### Phase 4: Approval UI (P1 UI)

**Files to create:**
- `Extremis/UI/PromptWindow/ToolApprovalView.swift`

**Key components:**
```swift
struct ToolApprovalView: View {
    let requests: [ToolApprovalRequest]
    let onApprove: (String) -> Void
    let onApproveAll: () -> Void
    let onDeny: (String) -> Void
    let onDenyAll: () -> Void
    @Binding var rememberForSession: Bool
}
```

**Keyboard handling:**
- Return: Approve focused/all
- Escape: Deny focused/all
- Tab: Navigate between tools

### Phase 5: Preferences UI (P2)

**Files to modify:**
- `Extremis/UI/Preferences/GeneralTab.swift` (or create new `ToolsTab.swift`)

**UI sections:**
1. Enable/disable tool approval toggle
2. List of auto-approval rules with add/remove
3. Rule editor (pattern, type, scope)

### Phase 6: Session Memory (P3)

**Integration:**
- Add `SessionApprovalMemory` property to session management
- Clear on session end
- Check before showing approval UI

## Testing Strategy

### Unit Tests

**File:** `Extremis/Tests/Core/ToolApprovalManagerTests.swift`

```swift
// Test rule matching
func testExactToolMatch()
func testWildcardToolMatch()
func testConnectorMatch()

// Test rule priority
func testDenyRulesPrecedeAllow()

// Test session memory
func testSessionMemoryRemembersApproval()
func testSessionMemoryClearsOnEnd()

// Test state transitions
func testApprovalStateTransitions()
```

### Integration Tests

**File:** `Extremis/Tests/Integration/ToolApprovalIntegrationTests.swift`

```swift
// Test full flow with mocked LLM
func testApprovalBlocksExecution()
func testAutoApprovalSkipsUI()
func testRejectionInformsLLM()
```

## Key Design Decisions

### 1. Inline vs Modal UI
**Decision:** Inline approval within chat stream
**Rationale:** Maintains context, allows batch review

### 2. Approval Timeout
**Decision:** No timeout, wait indefinitely
**Rationale:** Security-critical decision shouldn't be rushed

### 3. Session Memory Matching
**Decision:** Tool name only (ignore arguments)
**Rationale:** Reduces approval fatigue, simpler implementation

### 4. Default Approval State
**Decision:** All tools require approval by default
**Rationale:** Secure by default, opt-in trust model

## File Checklist

### New Files
- [ ] `Core/Models/ToolApprovalModels.swift`
- [ ] `Core/Services/ToolApprovalManager.swift`
- [ ] `UI/PromptWindow/ToolApprovalView.swift`
- [ ] `Tests/Core/ToolApprovalManagerTests.swift`

### Modified Files
- [ ] `Core/Models/Preferences.swift`
- [ ] `Utilities/UserDefaultsHelper.swift`
- [ ] `Connectors/Services/ToolEnabledChatService.swift`
- [ ] `UI/PromptWindow/ChatToolCall.swift`
- [ ] `UI/PromptWindow/ToolIndicatorView.swift`
- [ ] `UI/PromptWindow/PromptWindowController.swift`
- [ ] `UI/Preferences/GeneralTab.swift`
- [ ] `scripts/run-tests.sh`

## Common Pitfalls

### 1. MainActor Isolation
All approval state must be MainActor-bound for SwiftUI compatibility.

```swift
@MainActor
final class ToolApprovalManager { ... }
```

### 2. Async Continuation
Use `withCheckedContinuation` for waiting on user approval:

```swift
func requestApproval(...) async -> Set<String> {
    await withCheckedContinuation { continuation in
        // Store continuation, show UI
        // Resume when user decides
    }
}
```

### 3. Rule Matching Order
Always check deny rules before allow rules for security.

### 4. Session Scope
Session memory is tied to `ChatSession`, not app lifecycle.

## Next Steps After Implementation

1. Run full test suite: `./scripts/run-tests.sh`
2. Manual QA of all user flows
3. Update README with new feature documentation
4. Consider future enhancements:
   - Rule import/export
   - Approval history view
   - Quick "always allow this tool" from approval UI
