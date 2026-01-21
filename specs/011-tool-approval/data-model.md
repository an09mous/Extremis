# Data Model: Human-in-Loop Tool Approval

**Feature**: 011-tool-approval
**Date**: 2026-01-20

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Preferences                               │
│  (persisted in UserDefaults)                                    │
├─────────────────────────────────────────────────────────────────┤
│  + toolApprovalEnabled: Bool                                    │
│  + approvalRules: [ApprovalRule]                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 1:*
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ApprovalRule                              │
│  (persisted as part of Preferences)                             │
├─────────────────────────────────────────────────────────────────┤
│  + id: UUID                                                     │
│  + pattern: String                                              │
│  + ruleType: ApprovalRuleType                                   │
│  + scope: ApprovalRuleScope                                     │
│  + createdAt: Date                                              │
│  + isEnabled: Bool                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    SessionApprovalMemory                         │
│  (in-memory only, per session)                                  │
├─────────────────────────────────────────────────────────────────┤
│  + approvedToolNames: Set<String>                               │
│  + sessionId: String                                            │
│  + createdAt: Date                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    ToolApprovalRequest                           │
│  (transient, during approval flow)                              │
├─────────────────────────────────────────────────────────────────┤
│  + id: String                                                   │
│  + toolCall: ToolCall                                           │
│  + chatToolCall: ChatToolCall                                   │
│  + requestedAt: Date                                            │
│  + state: ApprovalState                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    ApprovalDecision                              │
│  (recorded for logging/audit)                                   │
├─────────────────────────────────────────────────────────────────┤
│  + requestId: String                                            │
│  + toolName: String                                             │
│  + connectorId: String                                          │
│  + action: ApprovalAction                                       │
│  + rememberForSession: Bool                                     │
│  + decidedAt: Date                                              │
│  + reason: String?                                              │
└─────────────────────────────────────────────────────────────────┘
```

## Enumerations

### ApprovalRuleType
```swift
/// Type of approval rule
enum ApprovalRuleType: String, Codable, CaseIterable {
    /// Always allow matching tools without prompting
    case allow

    /// Always deny matching tools without prompting
    case deny
}
```

### ApprovalRuleScope
```swift
/// Scope of what the rule matches
enum ApprovalRuleScope: String, Codable, CaseIterable {
    /// Match against tool name (e.g., "github_search_issues")
    case tool

    /// Match against connector ID (e.g., "github-mcp")
    case connector
}
```

### ApprovalState
```swift
/// State of an approval request
enum ApprovalState: Equatable {
    /// Waiting for user decision
    case pending

    /// User approved execution
    case approved

    /// User denied execution
    case denied(reason: String?)

    /// Auto-approved by rule
    case autoApproved(ruleId: UUID)

    /// Auto-denied by rule
    case autoDenied(ruleId: UUID)

    /// Request was dismissed (treated as denied)
    case dismissed
}
```

### ApprovalAction
```swift
/// User action on an approval request
enum ApprovalAction: String, Codable {
    /// User clicked approve/allow
    case approved

    /// User clicked deny/reject
    case denied

    /// User dismissed without deciding
    case dismissed

    /// Automatically approved by rule
    case autoApproved

    /// Automatically denied by rule
    case autoDenied

    /// Approved via session memory
    case sessionApproved
}
```

### Extended ToolCallState
```swift
/// Execution state of a tool call (extended for approval)
enum ToolCallState: Equatable {
    /// Waiting for user approval decision
    case pendingApproval

    /// User approved, waiting to execute
    case approved

    /// User denied execution
    case denied

    /// Currently executing
    case executing

    /// Completed successfully
    case completed

    /// Execution failed
    case failed

    /// User cancelled after approval
    case cancelled
}
```

## Entity Definitions

### ApprovalRule

Represents a user-configured rule for automatic approval or denial.

```swift
struct ApprovalRule: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID

    /// Pattern to match (glob-style)
    /// Examples:
    /// - "github_search_issues" (exact tool match)
    /// - "github-mcp" (exact connector match)
    /// - "github_*" (prefix match)
    /// - "*_search_*" (contains match)
    let pattern: String

    /// Whether this rule allows or denies
    let ruleType: ApprovalRuleType

    /// What the pattern matches against
    let scope: ApprovalRuleScope

    /// When the rule was created
    let createdAt: Date

    /// Whether the rule is active
    var isEnabled: Bool

    // MARK: - Matching Logic

    /// Check if this rule matches a tool call
    func matches(toolName: String, connectorId: String) -> Bool {
        let targetValue: String
        switch scope {
        case .tool:
            targetValue = toolName
        case .connector:
            targetValue = connectorId
        }
        return matchesPattern(pattern, against: targetValue)
    }

    /// Glob-style pattern matching
    private func matchesPattern(_ pattern: String, against value: String) -> Bool {
        // Convert glob to regex
        // * matches any characters
        // ? matches single character
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(
            pattern: "^" + regexPattern + "$",
            options: .caseInsensitive
        ) else {
            return pattern == value // Fallback to exact match
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
```

### SessionApprovalMemory

In-memory storage for session-scoped approvals.

```swift
@MainActor
final class SessionApprovalMemory {
    /// Tool names approved with "remember for session"
    private(set) var approvedToolNames: Set<String> = []

    /// Session identifier
    let sessionId: String

    /// When memory was created
    let createdAt: Date

    init(sessionId: String) {
        self.sessionId = sessionId
        self.createdAt = Date()
    }

    /// Record a tool as approved for this session
    func remember(toolName: String) {
        approvedToolNames.insert(toolName)
    }

    /// Check if tool was previously approved
    func isApproved(toolName: String) -> Bool {
        approvedToolNames.contains(toolName)
    }

    /// Clear all session approvals
    func clear() {
        approvedToolNames.removeAll()
    }
}
```

### ToolApprovalRequest

Transient object representing a pending approval.

```swift
struct ToolApprovalRequest: Identifiable {
    /// Unique identifier (matches tool call ID)
    let id: String

    /// The underlying tool call
    let toolCall: ToolCall

    /// UI-friendly representation
    let chatToolCall: ChatToolCall

    /// When approval was requested
    let requestedAt: Date

    /// Current state
    var state: ApprovalState

    /// Whether "remember for session" checkbox is checked
    var rememberForSession: Bool = false

    init(toolCall: ToolCall) {
        self.id = toolCall.id
        self.toolCall = toolCall
        self.chatToolCall = ChatToolCall.from(toolCall)
        self.requestedAt = Date()
        self.state = .pending
    }
}
```

### ApprovalDecision

Record of a user's decision for logging/audit.

```swift
struct ApprovalDecision: Codable, Identifiable {
    /// Unique identifier
    let id: UUID

    /// ID of the approval request
    let requestId: String

    /// Name of the tool
    let toolName: String

    /// Connector that provides the tool
    let connectorId: String

    /// What action was taken
    let action: ApprovalAction

    /// Whether user checked "remember for session"
    let rememberForSession: Bool

    /// When decision was made
    let decidedAt: Date

    /// Optional reason (for denied)
    let reason: String?

    init(
        request: ToolApprovalRequest,
        action: ApprovalAction,
        reason: String? = nil
    ) {
        self.id = UUID()
        self.requestId = request.id
        self.toolName = request.toolCall.toolName
        self.connectorId = request.toolCall.connectorID
        self.action = action
        self.rememberForSession = request.rememberForSession
        self.decidedAt = Date()
        self.reason = reason
    }
}
```

## Preferences Extension

```swift
extension Preferences {
    /// Whether tool approval is enabled (default: true)
    var toolApprovalEnabled: Bool

    /// User-defined approval rules
    var approvalRules: [ApprovalRule]
}
```

## State Transitions

### ToolCallState Transitions

```
                    ┌──────────────────┐
                    │ pendingApproval  │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
    ┌──────────┐      ┌──────────┐      ┌──────────┐
    │ approved │      │  denied  │      │ dismissed│
    └────┬─────┘      └──────────┘      └──────────┘
         │
         ▼
    ┌──────────┐
    │executing │
    └────┬─────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌──────┐
│completed│ │failed│
└────────┘ └──────┘
```

### ApprovalState Transitions

```
[Initial] → pending
pending → approved (user clicks approve)
pending → denied (user clicks deny)
pending → dismissed (user closes UI)
pending → autoApproved (rule matches)
pending → autoDenied (rule matches)
```

## Validation Rules

### ApprovalRule Validation
- `pattern` must be non-empty
- `pattern` must be valid glob syntax (no unbalanced brackets)
- Duplicate patterns with same scope are not allowed
- Maximum 100 rules per user

### Session Memory
- Automatically cleared when session ends
- Tool names stored as-is (case-sensitive)
- No persistence across app restarts

## Indexes & Lookups

### Rule Matching Priority
1. Deny rules checked first (safety)
2. Allow rules checked second
3. Session memory checked third
4. If no match, require manual approval

### Efficient Lookups
```swift
/// Manager maintains indexed rules for fast lookup
class ToolApprovalManager {
    /// Rules indexed by type for priority evaluation
    private var denyRules: [ApprovalRule] = []
    private var allowRules: [ApprovalRule] = []

    /// Rebuild indexes when rules change
    func rebuildIndexes(from rules: [ApprovalRule]) {
        let enabled = rules.filter { $0.isEnabled }
        denyRules = enabled.filter { $0.ruleType == .deny }
        allowRules = enabled.filter { $0.ruleType == .allow }
    }
}
```

## Migration Notes

### From Existing Preferences
- No existing approval fields to migrate
- New fields added with defaults:
  - `toolApprovalEnabled = true`
  - `approvalRules = []`

### Backwards Compatibility
- Apps without approval settings will require approval for all tools
- This is the secure default per spec clarification
