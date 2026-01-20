# Implementation Plan: Human-in-Loop Tool Approval

**Branch**: `011-tool-approval` | **Date**: 2026-01-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-tool-approval/spec.md`

## Summary

Implement a human-in-loop approval system that intercepts MCP tool calls before execution and requires explicit user approval. The system follows Claude Code's hierarchical permission model with deny → allow → ask precedence, using inline approval UI within the chat stream. Key features include:
- P1: Core approval flow with approve/deny buttons and keyboard shortcuts
- P2: Configurable auto-approval rules (by tool name or connector)
- P3: Session-scoped approval memory for iterative workflows

Technical approach: Inject approval gate in `ToolEnabledChatService` between tool resolution and execution, using async continuation to pause the generation stream while awaiting user input.

## Technical Context

**Language/Version**: Swift 5.9+, Swift Concurrency (async/await, actors)
**Primary Dependencies**: SwiftUI, AppKit (NSPanel), Carbon (hotkeys)
**Storage**: UserDefaults via existing `UserDefaultsHelper` for approval rules
**Testing**: Standalone Swift test files in `Extremis/Tests/`, run via `scripts/run-tests.sh`
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS menu bar application
**Performance Goals**: <100ms UI response for approval display, <1s delay for auto-approval path
**Constraints**: Must not block main thread, maintain 60fps UI during approval flow
**Scale/Scope**: Single user, ~10-50 tools per session, ~100 max auto-approval rules

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence/Notes |
|-----------|--------|----------------|
| **I. Modularity & Separation of Concerns** | ✅ PASS | New `ToolApprovalManager` service is self-contained; approval logic separate from execution logic; UI component (`ToolApprovalView`) separate from business logic |
| **II. Code Quality & Best Practices** | ✅ PASS | Follows Swift API Guidelines; uses existing patterns from codebase; protocol-based design for testability |
| **III. Extensibility & Testability** | ✅ PASS | `ToolApprovalService` protocol allows mock injection; state machine enables deterministic testing; dependency injection for UI delegate |
| **IV. User Experience Excellence** | ✅ PASS | Inline approval (no modal), keyboard shortcuts (Return/Escape), clear visual states, follows macOS HIG |
| **V. Documentation Synchronization** | ⏳ PENDING | README update required after implementation |
| **VI. Testing Discipline** | ✅ PASS | Unit tests planned for rule matching, state transitions, session memory; edge cases from spec will have coverage |
| **VII. Regression Prevention** | ✅ PASS | Minimal changes to existing execution path; new logic is additive; existing tool execution tests remain valid |

**Quality Standards Check:**
- [ ] Build: Will compile without warnings (to be verified)
- [ ] Lint: SwiftLint compliant (to be verified)
- [ ] Tests: New tests required, existing tests must pass
- [ ] Manual QA: Approval flow to be tested with real MCP tools
- [ ] Memory: No retain cycles (using weak delegates)
- [ ] Performance: Async continuation, no blocking

## Project Structure

### Documentation (this feature)

```text
specs/011-tool-approval/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Industry best practices research
├── data-model.md        # Entity definitions and state machines
├── quickstart.md        # Implementation guide
├── contracts/           # Service and UI contracts
│   ├── approval-service.swift
│   └── approval-ui.swift
├── checklists/          # Quality checklists
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   ├── Preferences.swift          # MODIFY: Add approval settings
│   │   └── ToolApprovalModels.swift   # NEW: ApprovalRule, ApprovalState, etc.
│   └── Services/
│       └── ToolApprovalManager.swift  # NEW: Central approval logic
├── Connectors/
│   └── Services/
│       └── ToolEnabledChatService.swift  # MODIFY: Add approval gate
├── UI/
│   ├── PromptWindow/
│   │   ├── ChatToolCall.swift         # MODIFY: Extend ToolCallState enum
│   │   ├── ToolIndicatorView.swift    # MODIFY: Add approval state rendering
│   │   ├── ToolApprovalView.swift     # NEW: Approval UI component
│   │   └── PromptWindowController.swift # MODIFY: Coordinate approval display
│   └── Preferences/
│       └── GeneralTab.swift           # MODIFY: Add approval settings section
├── Utilities/
│   └── UserDefaultsHelper.swift       # MODIFY: Add approval accessors
└── Tests/
    └── Core/
        └── ToolApprovalManagerTests.swift  # NEW: Unit tests

scripts/
└── run-tests.sh                       # MODIFY: Add new test file
```

**Structure Decision**: Single macOS app structure following existing Extremis patterns. New files added to `Core/Models/`, `Core/Services/`, and `UI/PromptWindow/` directories per established conventions. Tests in `Tests/Core/` following standalone test file pattern.

## Key Integration Points

### 1. Approval Gate Injection

**Location**: `ToolEnabledChatService.generateWithToolsStream()` lines 186-211

```swift
// Current flow:
let toolCalls = self.resolveToolCalls(...)
let results = await self.executeToolsWithUpdates(...)

// New flow:
let toolCalls = self.resolveToolCalls(...)
let approvedIds = await approvalManager.requestApproval(for: toolCalls, ...)
let approvedCalls = toolCalls.filter { approvedIds.contains($0.id) }
let results = await self.executeToolsWithUpdates(toolCalls: approvedCalls, ...)
```

### 2. State Propagation

**Flow**: ToolApprovalManager → PromptViewModel → ToolApprovalView

```swift
// PromptViewModel additions:
@Published var pendingApprovalRequests: [ToolApprovalRequest] = []
@Published var isAwaitingApproval: Bool = false
```

### 3. Keyboard Handling

**Pattern**: SwiftUI `.keyboardShortcut()` modifiers in `ToolApprovalView`

```swift
Button("Allow") { onApprove() }
    .keyboardShortcut(.return, modifiers: [])

Button("Deny") { onDeny() }
    .keyboardShortcut(.escape, modifiers: [])
```

## Dependencies Between Components

```
┌─────────────────────┐
│    Preferences      │ ◄── UserDefaultsHelper reads/writes
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ ToolApprovalManager │ ◄── Singleton service
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
┌────────┐  ┌─────────────────────┐
│ Rules  │  │ SessionApprovalMemory│
└────────┘  └─────────────────────┘
    │
    ▼
┌─────────────────────────────┐
│ ToolEnabledChatService      │ ◄── Calls approvalManager.requestApproval()
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ PromptViewModel             │ ◄── Receives approval events, publishes state
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ ToolApprovalView            │ ◄── SwiftUI view, user interaction
└─────────────────────────────┘
```

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Blocking main thread | Use `withCheckedContinuation` for async approval wait |
| State leakage between sessions | Session memory cleared on session end, tied to ChatSession lifecycle |
| Rule matching performance | Pre-index rules by type (deny/allow) on load |
| UI responsiveness during approval | Approval view is lightweight SwiftUI, no heavy computation |
| Regression in existing tool flow | Keep existing code paths unchanged when approval disabled |

## Complexity Tracking

> No constitution violations requiring justification. Design follows existing patterns with minimal complexity.

| Complexity Added | Justification | Simpler Alternative Considered |
|------------------|---------------|--------------------------------|
| State machine for approval | Required for clear state transitions | Boolean flags would be error-prone |
| Async continuation pattern | Necessary for pausing stream | Polling would waste resources |
| Rule pattern matching | Enables flexible auto-approval | Exact-match only would be too rigid |

## Next Steps

Run `/speckit.tasks` to generate the task breakdown for implementation.
