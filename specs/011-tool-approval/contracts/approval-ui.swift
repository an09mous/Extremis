// MARK: - Tool Approval UI Contract
// Defines the view model and UI state for approval components

import Foundation

// MARK: - Approval View Model Protocol

/// Protocol for approval view model (used by SwiftUI views)
@MainActor
protocol ToolApprovalViewModel: ObservableObject {

    // MARK: - Published State

    /// Approval requests pending user decision
    var pendingRequests: [ToolApprovalRequest] { get }

    /// Whether approval UI should be visible
    var isShowingApproval: Bool { get }

    /// Currently focused request (for keyboard navigation)
    var focusedRequestId: String? { get set }

    /// Whether "remember for session" is checked globally
    var rememberForSession: Bool { get set }

    // MARK: - Actions

    /// Approve a single tool call
    /// - Parameter requestId: ID of request to approve
    func approve(requestId: String)

    /// Approve all pending tool calls
    func approveAll()

    /// Deny a single tool call
    /// - Parameters:
    ///   - requestId: ID of request to deny
    ///   - reason: Optional reason for denial
    func deny(requestId: String, reason: String?)

    /// Deny all pending tool calls
    /// - Parameter reason: Optional reason for denial
    func denyAll(reason: String?)

    /// Dismiss approval UI (treated as deny all)
    func dismiss()

    // MARK: - Keyboard Navigation

    /// Move focus to next request
    func focusNext()

    /// Move focus to previous request
    func focusPrevious()

    /// Approve the focused request
    func approveFocused()

    /// Deny the focused request
    func denyFocused()
}

// MARK: - Approval Request Display Model

/// View-friendly model for displaying an approval request
struct ApprovalRequestDisplayModel: Identifiable {
    let id: String
    let toolName: String
    let connectorId: String
    let connectorDisplayName: String
    let argumentsSummary: String
    let argumentsDetailed: [(key: String, value: String)]
    let requestedAt: Date
    let state: ApprovalState

    /// Icon name for current state
    var stateIcon: String {
        switch state {
        case .pending: return "questionmark.circle"
        case .approved, .autoApproved: return "checkmark.circle.fill"
        case .denied, .autoDenied: return "xmark.circle.fill"
        case .dismissed: return "minus.circle"
        }
    }

    /// Color name for current state
    var stateColor: String {
        switch state {
        case .pending: return "orange"
        case .approved, .autoApproved: return "green"
        case .denied, .autoDenied, .dismissed: return "red"
        }
    }

    /// Whether this request needs user action
    var needsAction: Bool {
        if case .pending = state { return true }
        return false
    }

    /// Formatted time since request
    var timeSinceRequest: String {
        let interval = Date().timeIntervalSince(requestedAt)
        if interval < 1 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }
}

// MARK: - Approval Rule Display Model

/// View-friendly model for displaying an approval rule in preferences
struct ApprovalRuleDisplayModel: Identifiable {
    let id: UUID
    let pattern: String
    let ruleType: ApprovalRuleType
    let scope: ApprovalRuleScope
    let createdAt: Date
    var isEnabled: Bool

    /// Human-readable description of the rule
    var description: String {
        let action = ruleType == .allow ? "Allow" : "Deny"
        let target = scope == .tool ? "tools matching" : "all tools from connector"
        return "\(action) \(target) '\(pattern)'"
    }

    /// Icon for rule type
    var icon: String {
        ruleType == .allow ? "checkmark.shield" : "xmark.shield"
    }

    /// Color for rule type
    var color: String {
        ruleType == .allow ? "green" : "red"
    }

    /// Formatted creation date
    var createdDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: createdAt)
    }

    /// Convert to ApprovalRule for saving
    func toApprovalRule() -> ApprovalRule {
        ApprovalRule(
            id: id,
            pattern: pattern,
            ruleType: ruleType,
            scope: scope,
            createdAt: createdAt,
            isEnabled: isEnabled
        )
    }

    /// Create from ApprovalRule
    static func from(_ rule: ApprovalRule) -> ApprovalRuleDisplayModel {
        ApprovalRuleDisplayModel(
            id: rule.id,
            pattern: rule.pattern,
            ruleType: rule.ruleType,
            scope: rule.scope,
            createdAt: rule.createdAt,
            isEnabled: rule.isEnabled
        )
    }
}

// MARK: - Approval Preferences View Model

/// Protocol for approval settings in preferences
@MainActor
protocol ApprovalPreferencesViewModel: ObservableObject {

    // MARK: - Published State

    /// Whether tool approval is enabled
    var isApprovalEnabled: Bool { get set }

    /// Configured approval rules
    var rules: [ApprovalRuleDisplayModel] { get }

    /// Pattern being entered for new rule
    var newRulePattern: String { get set }

    /// Type for new rule (allow/deny)
    var newRuleType: ApprovalRuleType { get set }

    /// Scope for new rule (tool/connector)
    var newRuleScope: ApprovalRuleScope { get set }

    /// Validation error for new rule
    var validationError: String? { get }

    /// Whether add button should be enabled
    var canAddRule: Bool { get }

    // MARK: - Actions

    /// Add a new rule with current settings
    func addRule()

    /// Delete a rule
    /// - Parameter id: ID of rule to delete
    func deleteRule(id: UUID)

    /// Toggle rule enabled state
    /// - Parameter id: ID of rule to toggle
    func toggleRule(id: UUID)

    /// Move rule in list (for reordering priority)
    /// - Parameters:
    ///   - fromIndex: Source index
    ///   - toIndex: Destination index
    func moveRule(from fromIndex: Int, to toIndex: Int)

    /// Reset to default settings
    func resetToDefaults()
}

// MARK: - Keyboard Shortcuts

/// Keyboard shortcuts for approval UI
enum ApprovalKeyboardShortcut {
    /// Primary approve action
    static let approve = "⏎"

    /// Approve all
    static let approveAll = "⌥⏎"

    /// Deny action
    static let deny = "⎋"

    /// Deny all
    static let denyAll = "⌥⎋"

    /// Toggle remember for session
    static let toggleRemember = "⌘R"

    /// Focus next
    static let focusNext = "⇥"

    /// Focus previous
    static let focusPrevious = "⇧⇥"
}

// MARK: - Accessibility

/// Accessibility labels for approval UI
enum ApprovalAccessibility {
    static let approveButton = "Approve tool execution"
    static let approveAllButton = "Approve all pending tool executions"
    static let denyButton = "Deny tool execution"
    static let denyAllButton = "Deny all pending tool executions"
    static let rememberCheckbox = "Remember approval for this session"
    static let dismissButton = "Dismiss approval dialog"

    static func toolDescription(_ request: ApprovalRequestDisplayModel) -> String {
        "Tool \(request.toolName) from \(request.connectorDisplayName) wants to execute with arguments: \(request.argumentsSummary)"
    }
}
