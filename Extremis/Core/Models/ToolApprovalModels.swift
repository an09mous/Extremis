// MARK: - Tool Approval Models
// Data models for human-in-loop tool approval system
// Phase 1: Session-based approval only (rules deferred to Phase 2)

import Foundation

// MARK: - Enumerations

/// State of an approval request
enum ApprovalState: Equatable {
    /// Waiting for user decision
    case pending
    /// User approved execution
    case approved
    /// User denied execution
    case denied(reason: String?)
    /// Request was dismissed (treated as denied)
    case dismissed

    /// Whether this state represents a completed decision
    var isTerminal: Bool {
        switch self {
        case .pending:
            return false
        case .approved, .denied, .dismissed:
            return true
        }
    }

    /// Whether this state allows execution
    var allowsExecution: Bool {
        switch self {
        case .approved:
            return true
        case .pending, .denied, .dismissed:
            return false
        }
    }
}

/// User action on an approval request
enum ApprovalAction: String, Codable {
    /// User clicked approve/allow
    case approved
    /// User clicked deny/reject
    case denied
    /// User dismissed without deciding
    case dismissed
    /// Approved via session memory
    case sessionApproved
}

// MARK: - Core Entities

/// Transient object representing a pending approval
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
    var rememberForSession: Bool

    init(toolCall: ToolCall) {
        self.id = toolCall.id
        self.toolCall = toolCall
        self.chatToolCall = ChatToolCall.from(toolCall)
        self.requestedAt = Date()
        self.state = .pending
        self.rememberForSession = false
    }

    /// Create multiple requests from tool calls
    static func from(_ toolCalls: [ToolCall]) -> [ToolApprovalRequest] {
        toolCalls.map { ToolApprovalRequest(toolCall: $0) }
    }
}

/// Record of a user's decision for logging/audit
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

    /// Create from tool call directly (for session-approved)
    init(
        toolCall: ToolCall,
        action: ApprovalAction,
        reason: String? = nil
    ) {
        self.id = UUID()
        self.requestId = toolCall.id
        self.toolName = toolCall.toolName
        self.connectorId = toolCall.connectorID
        self.action = action
        self.rememberForSession = false
        self.decidedAt = Date()
        self.reason = reason
    }
}

/// In-memory storage for session-scoped approvals
@MainActor
final class SessionApprovalMemory {
    /// Tool names approved with "remember for session"
    private(set) var approvedToolNames: Set<String> = []

    /// Shell command patterns approved with "remember for session"
    /// Patterns like "df *", "ls *" that match command executables
    private(set) var approvedShellPatterns: Set<String> = []

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

    // MARK: - Shell Pattern Support

    /// Record a shell command pattern as approved for this session
    /// - Parameter pattern: A pattern like "df *" or "ls *"
    func rememberShellPattern(_ pattern: String) {
        approvedShellPatterns.insert(pattern)
    }

    /// Check if a shell command matches an approved pattern
    /// - Parameter command: The full command string (e.g., "df -h")
    /// - Returns: Whether the command matches an approved pattern
    ///
    /// SECURITY: This is a critical security function. Pattern matching rules:
    /// 1. Commands requiring explicit approval (operators, destructive) are NEVER auto-approved
    /// 2. Destructive commands (rm, mv, kill, etc.) require EXACT command match
    /// 3. Safe/read commands can use wildcard patterns (executable matches executable)
    /// 4. Pattern must have been explicitly approved for this session
    /// 5. Never allow cross-executable matching (df approval cannot approve rm)
    func isShellCommandApproved(_ command: String) -> Bool {
        // Extract executable from command
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // SECURITY: Commands with dangerous operators ALWAYS require explicit approval
        // Never auto-approve via session memory or "Allow All Once"
        if ShellCommandClassifier.requiresExplicitApproval(trimmed) {
            print("🔐 Command requires explicit approval (has operators or is destructive) - not auto-approving")
            return false
        }

        let executable = extractShellExecutable(from: trimmed)

        // SECURITY: Destructive commands require EXACT match only
        // Never allow wildcard patterns for dangerous operations
        let destructiveExecutables: Set<String> = [
            "rm", "rmdir", "mv", "kill", "killall", "pkill",
            "sudo", "su", "dscl", "security"  // Also block privileged
        ]

        if destructiveExecutables.contains(executable) {
            // ONLY exact command match for destructive commands
            // Do NOT check wildcard patterns - this is critical for security
            let isApproved = approvedShellPatterns.contains(trimmed)
            if isApproved {
                print("🔐 Destructive command '\(executable)' matched exact pattern")
            }
            return isApproved
        }

        // For non-destructive commands, check wildcard pattern first
        let wildcardPattern = "\(executable) *"
        if approvedShellPatterns.contains(wildcardPattern) {
            print("🔓 Command '\(executable)' matched wildcard pattern '\(wildcardPattern)'")
            return true
        }

        // Also check exact command match (handles edge cases and exact approvals)
        if approvedShellPatterns.contains(trimmed) {
            print("🔓 Command matched exact pattern")
            return true
        }

        return false
    }

    /// Extract the executable name from a shell command
    private func extractShellExecutable(from command: String) -> String {
        let firstWord = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command

        // Handle path prefixes (e.g., /usr/bin/ls -> ls)
        if firstWord.contains("/") {
            return (firstWord as NSString).lastPathComponent
        }

        return firstWord
    }

    /// Clear all session approvals
    func clear() {
        approvedToolNames.removeAll()
        approvedShellPatterns.removeAll()
    }

    /// Number of remembered tools
    var count: Int {
        approvedToolNames.count
    }

    /// Number of remembered shell patterns
    var shellPatternCount: Int {
        approvedShellPatterns.count
    }
}

// MARK: - Error Types

/// Errors that can occur during approval operations
enum ToolApprovalError: Error, LocalizedError {
    /// Approval was cancelled
    case approvalCancelled

    /// Timeout waiting for approval
    case approvalTimeout

    var errorDescription: String? {
        switch self {
        case .approvalCancelled:
            return "Approval was cancelled"
        case .approvalTimeout:
            return "Timed out waiting for approval"
        }
    }
}
