// MARK: - Tool Approval Manager
// Central service for human-in-loop tool approval
// Phase 1: Session-based approval only (rules deferred to Phase 2)

import Foundation

// MARK: - UI Delegate Protocol

/// Result from the UI delegate's approval callback
struct ApprovalUIResult {
    /// Individual decisions for each tool
    let decisions: [String: ApprovalDecision]
    /// Whether "Allow All Once" was used - skip approval for rest of this generation
    let allowAllOnce: Bool

    init(decisions: [String: ApprovalDecision], allowAllOnce: Bool = false) {
        self.decisions = decisions
        self.allowAllOnce = allowAllOnce
    }
}

/// Protocol for presenting approval UI
/// Implemented by PromptWindowController
@MainActor
protocol ToolApprovalUIDelegate: AnyObject {
    /// Show approval UI for pending requests
    /// - Parameters:
    ///   - requests: The approval requests to show
    ///   - sessionId: The chat session ID this approval belongs to (for UI isolation)
    ///   - completion: Called when user makes decisions, includes allowAllOnce flag
    func showApprovalUI(
        for requests: [ToolApprovalRequest],
        sessionId: UUID?,
        completion: @escaping (ApprovalUIResult) -> Void
    )

    /// Dismiss the approval UI for a specific session
    /// - Parameter sessionId: The session to dismiss approval UI for (nil dismisses all)
    func dismissApprovalUI(for sessionId: UUID?)

    /// Update a single request's state in the UI
    func updateApprovalState(requestId: String, state: ApprovalState)
}

// MARK: - Approval Result

/// Result of approval request
struct ApprovalResult {
    /// Tool call IDs that were approved
    let approvedIds: Set<String>

    /// Decisions for all tool calls (for logging/feedback)
    let decisions: [ApprovalDecision]

    /// Whether "Allow All Once" was used - skip approval for rest of this generation
    let allowAllOnce: Bool

    /// Whether all tools were approved
    var allApproved: Bool {
        decisions.allSatisfy { $0.action == .approved || $0.action == .sessionApproved }
    }

    /// Whether any tools were denied
    var anyDenied: Bool {
        decisions.contains { $0.action == .denied || $0.action == .dismissed }
    }

    /// Empty result (no tools)
    static let empty = ApprovalResult(approvedIds: [], decisions: [], allowAllOnce: false)

    /// Create result with default allowAllOnce = false
    init(approvedIds: Set<String>, decisions: [ApprovalDecision], allowAllOnce: Bool = false) {
        self.approvedIds = approvedIds
        self.decisions = decisions
        self.allowAllOnce = allowAllOnce
    }
}

// MARK: - Tool Approval Manager

/// Central service for managing tool approval workflow
/// Handles session memory and UI coordination
@MainActor
final class ToolApprovalManager {

    // MARK: - Singleton

    static let shared = ToolApprovalManager()

    // MARK: - Properties

    /// UI delegate for showing approval prompts
    weak var uiDelegate: ToolApprovalUIDelegate?

    /// All decisions made, keyed by chat session ID (for audit log)
    /// Each chat session has its own isolated decision history
    private(set) var sessionDecisions: [UUID: [ApprovalDecision]] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Approval Flow

    /// Request approval for tool calls
    /// - Parameters:
    ///   - toolCalls: The tool calls to approve
    ///   - sessionMemory: Session-scoped approval memory
    ///   - sessionId: The chat session ID for decision tracking (for isolation)
    /// - Returns: Result containing approved tool IDs and all decisions
    func requestApproval(
        for toolCalls: [ToolCall],
        sessionMemory: SessionApprovalMemory?,
        sessionId: UUID?
    ) async -> ApprovalResult {
        // Empty list → empty result
        guard !toolCalls.isEmpty else {
            return .empty
        }

        // Evaluate each tool call
        var sessionApprovedDecisions: [ApprovalDecision] = []
        var pendingRequests: [ToolApprovalRequest] = []

        for toolCall in toolCalls {
            // Check session memory first
            if let memory = sessionMemory, memory.isApproved(toolName: toolCall.toolName) {
                print("🔓 Tool '\(toolCall.toolName)' auto-approved from session memory")
                let decision = ApprovalDecision(
                    toolCall: toolCall,
                    action: .sessionApproved,
                    reason: "Previously approved this session"
                )
                sessionApprovedDecisions.append(decision)
            } else {
                // Needs user approval
                print("🔒 Tool '\(toolCall.toolName)' needs user approval")
                pendingRequests.append(ToolApprovalRequest(toolCall: toolCall))
            }
        }

        // If no pending requests, return session-approved decisions
        if pendingRequests.isEmpty {
            recordDecisions(sessionApprovedDecisions, for: sessionId)
            return ApprovalResult(
                approvedIds: Set(sessionApprovedDecisions.map(\.requestId)),
                decisions: sessionApprovedDecisions,
                allowAllOnce: false
            )
        }

        // Wait for user decisions via UI
        let (userDecisions, allowAllOnce) = await waitForUserDecisions(pendingRequests, sessionId: sessionId)

        // Combine session and user decisions
        let allDecisions = sessionApprovedDecisions + userDecisions.values
        recordDecisions(Array(userDecisions.values), for: sessionId)

        // Update session memory for tools approved with "remember"
        if let memory = sessionMemory {
            for decision in userDecisions.values where decision.action == .approved && decision.rememberForSession {
                memory.remember(toolName: decision.toolName)
                print("📝 Remembered tool '\(decision.toolName)' for session (memory now has \(memory.count) tools)")
            }
        }

        // Collect approved IDs
        var approvedIds = Set(sessionApprovedDecisions.map(\.requestId))
        for decision in userDecisions.values where decision.action == .approved {
            approvedIds.insert(decision.requestId)
        }

        return ApprovalResult(
            approvedIds: approvedIds,
            decisions: allDecisions,
            allowAllOnce: allowAllOnce
        )
    }

    // MARK: - UI Coordination

    /// Timeout for user approval decisions (5 minutes)
    private static let approvalTimeoutSeconds: UInt64 = 300

    /// Wait for user decisions on pending requests
    /// - Parameters:
    ///   - requests: The approval requests to wait for
    ///   - sessionId: The chat session ID for UI isolation
    /// - Note: Has a timeout to prevent infinite hangs if UI callback never fires
    /// - Returns: Tuple of decisions dictionary and allowAllOnce flag
    private func waitForUserDecisions(
        _ requests: [ToolApprovalRequest],
        sessionId: UUID?
    ) async -> (decisions: [String: ApprovalDecision], allowAllOnce: Bool) {
        // Update UI state to pending approval
        for request in requests {
            uiDelegate?.updateApprovalState(requestId: request.id, state: .pending)
        }

        // Check for UI delegate early
        guard let delegate = uiDelegate else {
            // No UI delegate - deny all by default
            var decisions: [String: ApprovalDecision] = [:]
            for request in requests {
                decisions[request.id] = ApprovalDecision(
                    request: request,
                    action: .denied,
                    reason: "No approval UI available"
                )
            }
            return (decisions: decisions, allowAllOnce: false)
        }

        // Use actor to safely track resume state (async-safe alternative to NSLock)
        actor ResumeTracker {
            private var hasResumed = false

            func tryResume() -> Bool {
                if hasResumed { return false }
                hasResumed = true
                return true
            }
        }

        let tracker = ResumeTracker()

        // Use continuation with timeout to prevent infinite hangs
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Set up timeout task
                let timeoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.approvalTimeoutSeconds * 1_000_000_000)

                    guard !Task.isCancelled else { return }

                    let canResume = await tracker.tryResume()
                    if canResume {
                        // Timeout - deny all pending
                        var decisions: [String: ApprovalDecision] = [:]
                        for request in requests {
                            decisions[request.id] = ApprovalDecision(
                                request: request,
                                action: .denied,
                                reason: "Approval timed out"
                            )
                        }
                        continuation.resume(returning: (decisions: decisions, allowAllOnce: false))
                        print("⏱️ Tool approval timed out after \(Self.approvalTimeoutSeconds) seconds")
                    }
                }

                delegate.showApprovalUI(for: requests, sessionId: sessionId) { uiResult in
                    Task {
                        let canResume = await tracker.tryResume()
                        if canResume {
                            timeoutTask.cancel()
                            continuation.resume(returning: (decisions: uiResult.decisions, allowAllOnce: uiResult.allowAllOnce))
                        }
                    }
                }
            }
        } onCancel: {
            // If the task is cancelled, dismiss the UI for this session only
            Task { @MainActor in
                self.uiDelegate?.dismissApprovalUI(for: sessionId)
            }
        }
    }

    // MARK: - Decision Recording

    /// Record decisions for audit log, associated with a specific chat session
    /// - Parameters:
    ///   - decisions: The decisions to record
    ///   - sessionId: The chat session ID to associate decisions with (nil uses a default key)
    func recordDecisions(_ decisions: [ApprovalDecision], for sessionId: UUID?) {
        let key = sessionId ?? UUID()  // Use provided sessionId or generate one for orphan decisions

        if sessionDecisions[key] == nil {
            sessionDecisions[key] = []
        }
        sessionDecisions[key]?.append(contentsOf: decisions)

        // Log for debugging
        for decision in decisions {
            let emoji = decision.action == .approved || decision.action == .sessionApproved ? "✅" : "❌"
            print("\(emoji) \(decision.action.rawValue): \(decision.toolName) (\(decision.connectorId)) [session: \(sessionId?.uuidString.prefix(8) ?? "none")]")
        }
    }

    /// Clear decision log for a specific session
    func clearDecisionLog(for sessionId: UUID) {
        sessionDecisions.removeValue(forKey: sessionId)
        print("📋 Cleared approval decision log for session \(sessionId.uuidString.prefix(8))")
    }

    /// Clear all decision logs (e.g., on app restart)
    func clearAllDecisionLogs() {
        sessionDecisions.removeAll()
        print("📋 Cleared all approval decision logs")
    }

    // MARK: - Session Memory

    /// Remember approval for session
    func rememberApproval(toolName: String, in memory: SessionApprovalMemory) {
        memory.remember(toolName: toolName)
    }

    /// Clear session memory
    func clearSessionMemory(_ memory: SessionApprovalMemory) {
        let previousCount = memory.count
        memory.clear()
        print("📋 Cleared session approval memory (had \(previousCount) entries)")
    }
}
