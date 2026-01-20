// MARK: - Tool Approval Service Contract
// Defines the public interface for the ToolApprovalManager service

import Foundation

// MARK: - Protocol Definition

/// Protocol defining the tool approval service interface
@MainActor
protocol ToolApprovalService {

    // MARK: - Approval Request

    /// Request approval for a batch of tool calls
    /// - Parameters:
    ///   - toolCalls: The tool calls requiring approval
    ///   - sessionMemory: Current session's approval memory
    /// - Returns: Set of tool call IDs that were approved
    func requestApproval(
        for toolCalls: [ToolCall],
        sessionMemory: SessionApprovalMemory
    ) async -> Set<String>

    /// Check if a single tool call would be auto-approved
    /// - Parameters:
    ///   - toolCall: The tool call to check
    ///   - sessionMemory: Current session's approval memory
    /// - Returns: True if tool would be auto-approved
    func wouldAutoApprove(
        _ toolCall: ToolCall,
        sessionMemory: SessionApprovalMemory
    ) -> Bool

    // MARK: - Rule Management

    /// Add a new approval rule
    /// - Parameter rule: The rule to add
    /// - Throws: If rule is invalid or duplicate
    func addRule(_ rule: ApprovalRule) throws

    /// Remove an approval rule by ID
    /// - Parameter ruleId: ID of rule to remove
    func removeRule(id: UUID)

    /// Update an existing rule
    /// - Parameter rule: The updated rule
    /// - Throws: If rule doesn't exist
    func updateRule(_ rule: ApprovalRule) throws

    /// Get all configured rules
    var rules: [ApprovalRule] { get }

    // MARK: - Session Memory

    /// Record approval decision in session memory
    /// - Parameters:
    ///   - toolName: Name of the approved tool
    ///   - sessionMemory: Session memory to update
    func rememberApproval(
        toolName: String,
        in sessionMemory: SessionApprovalMemory
    )

    /// Clear session approval memory
    /// - Parameter sessionMemory: Session memory to clear
    func clearSessionMemory(_ sessionMemory: SessionApprovalMemory)

    // MARK: - Decision Logging

    /// Record an approval decision for audit
    /// - Parameter decision: The decision to record
    func recordDecision(_ decision: ApprovalDecision)

    /// Get decisions for current session
    var sessionDecisions: [ApprovalDecision] { get }

    /// Clear decision log
    func clearDecisionLog()
}

// MARK: - Approval UI Delegate

/// Delegate protocol for approval UI interactions
@MainActor
protocol ToolApprovalUIDelegate: AnyObject {

    /// Show approval UI for pending tool calls
    /// - Parameters:
    ///   - requests: The approval requests to display
    ///   - completion: Called with approved tool IDs when user decides
    func showApprovalUI(
        for requests: [ToolApprovalRequest],
        completion: @escaping (Set<String>) -> Void
    )

    /// Dismiss approval UI
    func dismissApprovalUI()

    /// Update state of a specific approval request
    /// - Parameters:
    ///   - requestId: ID of the request to update
    ///   - state: New state
    func updateApprovalState(
        requestId: String,
        state: ApprovalState
    )
}

// MARK: - Approval Events

/// Events emitted during approval flow
enum ToolApprovalEvent {
    /// Approval is required for tool calls
    case approvalRequired([ToolApprovalRequest])

    /// User approved specific tools
    case approved(toolIds: Set<String>, rememberForSession: Bool)

    /// User denied specific tools
    case denied(toolIds: Set<String>, reason: String?)

    /// All pending approvals dismissed
    case dismissed

    /// Tool was auto-approved by rule
    case autoApproved(toolId: String, ruleId: UUID)

    /// Tool was auto-denied by rule
    case autoDenied(toolId: String, ruleId: UUID)

    /// Tool was approved via session memory
    case sessionApproved(toolId: String)
}

// MARK: - Error Types

/// Errors that can occur during approval operations
enum ToolApprovalError: Error, LocalizedError {
    /// Rule pattern is invalid
    case invalidPattern(String)

    /// Rule already exists with same pattern and scope
    case duplicateRule

    /// Rule not found for update
    case ruleNotFound(UUID)

    /// Maximum rule count exceeded
    case maximumRulesExceeded(limit: Int)

    /// Approval was cancelled
    case approvalCancelled

    /// Timeout waiting for approval
    case approvalTimeout

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let pattern):
            return "Invalid pattern: \(pattern)"
        case .duplicateRule:
            return "A rule with this pattern already exists"
        case .ruleNotFound(let id):
            return "Rule not found: \(id)"
        case .maximumRulesExceeded(let limit):
            return "Maximum of \(limit) rules allowed"
        case .approvalCancelled:
            return "Approval was cancelled"
        case .approvalTimeout:
            return "Timed out waiting for approval"
        }
    }
}

// MARK: - Constants

enum ToolApprovalConstants {
    /// Maximum number of approval rules allowed
    static let maximumRules = 100

    /// Default state for new installations
    static let defaultApprovalEnabled = true

    /// Key for storing approval settings in UserDefaults
    static let preferencesKey = "toolApprovalSettings"
}
