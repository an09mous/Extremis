// MARK: - Tool Approval Manager Tests
// Unit tests for ToolApprovalManager and related models
// Phase 1: Session-based approval only (rules deferred to Phase 2)

import Foundation

// MARK: - Test Runner

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0

    static func suite(_ name: String) {
        print("\n\u{1F4CB} \(name)")
        print(String(repeating: "-", count: 50))
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message)")
            print("     Expected: \(expected)")
            print("     Actual: \(actual)")
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String) {
        if condition {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message)")
        }
    }

    static func assertFalse(_ condition: Bool, _ message: String) {
        assertTrue(!condition, message)
    }

    static func assertNil<T>(_ value: T?, _ message: String) {
        if value == nil {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message) - Expected nil but got: \(value!)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ message: String) {
        if value != nil {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message) - Expected non-nil value")
        }
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST RESULTS")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - Minimal Type Definitions for Standalone Testing

/// State of an approval request
enum ApprovalState: Equatable {
    case pending
    case approved
    case denied(reason: String?)
    case dismissed

    var isTerminal: Bool {
        switch self {
        case .pending: return false
        default: return true
        }
    }

    var allowsExecution: Bool {
        switch self {
        case .approved: return true
        default: return false
        }
    }
}

/// User action on an approval request
enum ApprovalAction: String, Codable {
    case approved
    case denied
    case dismissed
    case sessionApproved
}

/// Errors that can occur during approval operations
enum ToolApprovalError: Error, LocalizedError {
    case approvalCancelled
    case approvalTimeout

    var errorDescription: String? {
        switch self {
        case .approvalCancelled: return "Approval was cancelled"
        case .approvalTimeout: return "Timed out waiting for approval"
        }
    }
}

// MARK: - Session Approval Memory

final class SessionApprovalMemory {
    private(set) var approvedToolNames: Set<String> = []
    let sessionId: String
    let createdAt: Date

    init(sessionId: String) {
        self.sessionId = sessionId
        self.createdAt = Date()
    }

    func remember(toolName: String) {
        approvedToolNames.insert(toolName)
    }

    func isApproved(toolName: String) -> Bool {
        approvedToolNames.contains(toolName)
    }

    func clear() {
        approvedToolNames.removeAll()
    }

    var count: Int {
        approvedToolNames.count
    }
}

// MARK: - Mock ToolCall for Testing

struct MockToolCall {
    let id: String
    let toolName: String
    let connectorID: String

    init(id: String = UUID().uuidString, toolName: String, connectorID: String) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
    }
}

// MARK: - Approval Decision for Testing

struct ApprovalDecision {
    let id: UUID
    let requestId: String
    let toolName: String
    let connectorId: String
    let action: ApprovalAction
    let rememberForSession: Bool
    let decidedAt: Date
    let reason: String?

    init(
        toolCall: MockToolCall,
        action: ApprovalAction,
        rememberForSession: Bool = false,
        reason: String? = nil
    ) {
        self.id = UUID()
        self.requestId = toolCall.id
        self.toolName = toolCall.toolName
        self.connectorId = toolCall.connectorID
        self.action = action
        self.rememberForSession = rememberForSession
        self.decidedAt = Date()
        self.reason = reason
    }
}

// MARK: - Test Approval Manager (Session-based only)

final class TestToolApprovalManager {
    private(set) var sessionDecisions: [ApprovalDecision] = []

    init() {}

    /// Evaluate a tool call - checks session memory only (Phase 1)
    func evaluateToolCall(
        _ toolCall: MockToolCall,
        sessionMemory: SessionApprovalMemory?
    ) -> EvaluationResult {
        // Check session memory
        if let memory = sessionMemory, memory.isApproved(toolName: toolCall.toolName) {
            let decision = ApprovalDecision(
                toolCall: toolCall,
                action: .sessionApproved,
                reason: "Previously approved this session"
            )
            return .sessionApproved(decision)
        }

        // Needs user approval
        return .needsApproval
    }

    enum EvaluationResult {
        case sessionApproved(ApprovalDecision)
        case needsApproval
    }

    func recordDecision(_ decision: ApprovalDecision) {
        sessionDecisions.append(decision)
    }

    func clearDecisionLog() {
        sessionDecisions.removeAll()
    }
}

// MARK: - ApprovalState Tests

func testApprovalState() {
    TestRunner.suite("ApprovalState Tests")

    // Test isTerminal
    TestRunner.assertFalse(ApprovalState.pending.isTerminal, "pending is not terminal")
    TestRunner.assertTrue(ApprovalState.approved.isTerminal, "approved is terminal")
    TestRunner.assertTrue(ApprovalState.denied(reason: nil).isTerminal, "denied is terminal")
    TestRunner.assertTrue(ApprovalState.dismissed.isTerminal, "dismissed is terminal")

    // Test allowsExecution
    TestRunner.assertFalse(ApprovalState.pending.allowsExecution, "pending doesn't allow execution")
    TestRunner.assertTrue(ApprovalState.approved.allowsExecution, "approved allows execution")
    TestRunner.assertFalse(ApprovalState.denied(reason: nil).allowsExecution, "denied doesn't allow execution")
    TestRunner.assertFalse(ApprovalState.dismissed.allowsExecution, "dismissed doesn't allow execution")

    // Test Equatable
    TestRunner.assertTrue(ApprovalState.pending == ApprovalState.pending, "pending equals pending")
    TestRunner.assertFalse(ApprovalState.pending == ApprovalState.approved, "pending not equals approved")
    TestRunner.assertTrue(ApprovalState.denied(reason: "test") == ApprovalState.denied(reason: "test"), "denied with same reason equals")
}

// MARK: - ApprovalAction Tests

func testApprovalAction() {
    TestRunner.suite("ApprovalAction Tests")

    // Test raw values
    TestRunner.assertEqual(ApprovalAction.approved.rawValue, "approved", "approved raw value")
    TestRunner.assertEqual(ApprovalAction.denied.rawValue, "denied", "denied raw value")
    TestRunner.assertEqual(ApprovalAction.dismissed.rawValue, "dismissed", "dismissed raw value")
    TestRunner.assertEqual(ApprovalAction.sessionApproved.rawValue, "sessionApproved", "sessionApproved raw value")

    // Test Codable encoding/decoding
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    if let encoded = try? encoder.encode(ApprovalAction.approved),
       let decoded = try? decoder.decode(ApprovalAction.self, from: encoded) {
        TestRunner.assertEqual(decoded, .approved, "Codable round-trip for approved")
    } else {
        TestRunner.assertTrue(false, "Codable round-trip for approved")
    }

    if let encoded = try? encoder.encode(ApprovalAction.sessionApproved),
       let decoded = try? decoder.decode(ApprovalAction.self, from: encoded) {
        TestRunner.assertEqual(decoded, .sessionApproved, "Codable round-trip for sessionApproved")
    } else {
        TestRunner.assertTrue(false, "Codable round-trip for sessionApproved")
    }
}

// MARK: - ToolApprovalError Tests

func testToolApprovalError() {
    TestRunner.suite("ToolApprovalError Tests")

    let cancelled = ToolApprovalError.approvalCancelled
    TestRunner.assertNotNil(cancelled.errorDescription, "approvalCancelled has error description")
    TestRunner.assertTrue(
        cancelled.errorDescription?.contains("cancelled") ?? false,
        "approvalCancelled description mentions cancelled"
    )

    let timeout = ToolApprovalError.approvalTimeout
    TestRunner.assertNotNil(timeout.errorDescription, "approvalTimeout has error description")
    TestRunner.assertTrue(
        timeout.errorDescription?.lowercased().contains("timeout") ?? false ||
        timeout.errorDescription?.lowercased().contains("timed out") ?? false,
        "approvalTimeout description mentions timeout"
    )
}

// MARK: - Session Approval Memory Tests

func testSessionApprovalMemory() {
    TestRunner.suite("SessionApprovalMemory Tests")

    // Test initial state
    let memory = SessionApprovalMemory(sessionId: "test-session")
    TestRunner.assertEqual(memory.count, 0, "New memory is empty")
    TestRunner.assertFalse(memory.isApproved(toolName: "github_search"), "Tool not approved initially")

    // Test remember function
    memory.remember(toolName: "github_search")
    TestRunner.assertTrue(memory.isApproved(toolName: "github_search"), "Tool is approved after remember")
    TestRunner.assertEqual(memory.count, 1, "Memory has 1 entry")

    // Test different tool not approved
    TestRunner.assertFalse(memory.isApproved(toolName: "slack_post"), "Different tool not approved")

    // Test multiple remembers
    memory.remember(toolName: "slack_post")
    memory.remember(toolName: "github_create")
    TestRunner.assertEqual(memory.count, 3, "Memory has 3 entries")
    TestRunner.assertTrue(memory.isApproved(toolName: "slack_post"), "Second tool approved")
    TestRunner.assertTrue(memory.isApproved(toolName: "github_create"), "Third tool approved")

    // Test duplicate remember (set behavior)
    memory.remember(toolName: "github_search")
    TestRunner.assertEqual(memory.count, 3, "Duplicate remember doesn't increase count")

    // Test clear function
    memory.clear()
    TestRunner.assertEqual(memory.count, 0, "Memory is empty after clear")
    TestRunner.assertFalse(memory.isApproved(toolName: "github_search"), "Tool not approved after clear")

    // Test session scoping (new memory doesn't have old approvals)
    let memory1 = SessionApprovalMemory(sessionId: "session-1")
    memory1.remember(toolName: "github_search")

    let memory2 = SessionApprovalMemory(sessionId: "session-2")
    TestRunner.assertFalse(memory2.isApproved(toolName: "github_search"), "New session memory doesn't have old approvals")
    TestRunner.assertTrue(memory1.isApproved(toolName: "github_search"), "Original memory still has approval")
}

// MARK: - Session-Based Evaluation Tests

func testSessionBasedEvaluation() {
    TestRunner.suite("Session-Based Evaluation Tests")

    let manager = TestToolApprovalManager()

    // Test with no session memory - needs approval
    let toolCall1 = MockToolCall(toolName: "github_search", connectorID: "github-mcp")
    let result1 = manager.evaluateToolCall(toolCall1, sessionMemory: nil)
    if case .needsApproval = result1 {
        TestRunner.assertTrue(true, "Tool without session memory needs approval")
    } else {
        TestRunner.assertTrue(false, "Tool without session memory needs approval")
    }

    // Test with empty session memory - needs approval
    let memory = SessionApprovalMemory(sessionId: "test")
    let result2 = manager.evaluateToolCall(toolCall1, sessionMemory: memory)
    if case .needsApproval = result2 {
        TestRunner.assertTrue(true, "Tool with empty session memory needs approval")
    } else {
        TestRunner.assertTrue(false, "Tool with empty session memory needs approval")
    }

    // Test session memory auto-approval
    memory.remember(toolName: "github_search")
    let result3 = manager.evaluateToolCall(toolCall1, sessionMemory: memory)
    if case .sessionApproved(let decision) = result3 {
        TestRunner.assertEqual(decision.action, .sessionApproved, "Session memory auto-approves")
        TestRunner.assertEqual(decision.toolName, "github_search", "Decision has correct tool name")
    } else {
        TestRunner.assertTrue(false, "Session memory auto-approves")
    }

    // Test different tool still needs approval
    let toolCall2 = MockToolCall(toolName: "slack_post", connectorID: "slack-mcp")
    let result4 = manager.evaluateToolCall(toolCall2, sessionMemory: memory)
    if case .needsApproval = result4 {
        TestRunner.assertTrue(true, "Different tool still needs approval")
    } else {
        TestRunner.assertTrue(false, "Different tool still needs approval")
    }

    // Approve second tool and verify
    memory.remember(toolName: "slack_post")
    let result5 = manager.evaluateToolCall(toolCall2, sessionMemory: memory)
    if case .sessionApproved = result5 {
        TestRunner.assertTrue(true, "Second tool auto-approved after remember")
    } else {
        TestRunner.assertTrue(false, "Second tool auto-approved after remember")
    }
}

// MARK: - Approval State Transition Tests

func testApprovalStateTransitions() {
    TestRunner.suite("Approval State Transitions Tests")

    // Test pending -> approved
    let state1 = ApprovalState.pending
    TestRunner.assertFalse(state1.isTerminal, "Pending is not terminal")
    TestRunner.assertFalse(state1.allowsExecution, "Pending doesn't allow execution")

    // Simulate transition to approved
    let approvedState = ApprovalState.approved
    TestRunner.assertTrue(approvedState.isTerminal, "Approved is terminal")
    TestRunner.assertTrue(approvedState.allowsExecution, "Approved allows execution")

    // Test pending -> denied
    let deniedState = ApprovalState.denied(reason: "User rejected")
    TestRunner.assertTrue(deniedState.isTerminal, "Denied is terminal")
    TestRunner.assertFalse(deniedState.allowsExecution, "Denied doesn't allow execution")

    // Test pending -> dismissed
    let dismissedState = ApprovalState.dismissed
    TestRunner.assertTrue(dismissedState.isTerminal, "Dismissed is terminal")
    TestRunner.assertFalse(dismissedState.allowsExecution, "Dismissed doesn't allow execution")

    // Cannot transition from terminal states (documented behavior)
    TestRunner.assertTrue(
        ApprovalState.approved.isTerminal &&
        ApprovalState.denied(reason: nil).isTerminal &&
        ApprovalState.dismissed.isTerminal,
        "Terminal states cannot transition"
    )
}

// MARK: - Decision Recording Tests

func testDecisionRecording() {
    TestRunner.suite("Decision Recording Tests")

    let manager = TestToolApprovalManager()

    TestRunner.assertEqual(manager.sessionDecisions.count, 0, "Initially no decisions")

    let toolCall = MockToolCall(toolName: "github_search", connectorID: "github-mcp")
    let decision = ApprovalDecision(toolCall: toolCall, action: .approved)
    manager.recordDecision(decision)

    TestRunner.assertEqual(manager.sessionDecisions.count, 1, "Decision recorded")
    TestRunner.assertEqual(manager.sessionDecisions.first?.action, .approved, "Correct action recorded")
    TestRunner.assertEqual(manager.sessionDecisions.first?.toolName, "github_search", "Correct tool name recorded")

    // Record another decision
    let toolCall2 = MockToolCall(toolName: "slack_post", connectorID: "slack-mcp")
    let decision2 = ApprovalDecision(toolCall: toolCall2, action: .denied, reason: "User denied")
    manager.recordDecision(decision2)

    TestRunner.assertEqual(manager.sessionDecisions.count, 2, "Second decision recorded")
    TestRunner.assertEqual(manager.sessionDecisions.last?.action, .denied, "Correct action for second decision")

    // Record session approved decision
    let decision3 = ApprovalDecision(toolCall: toolCall, action: .sessionApproved)
    manager.recordDecision(decision3)

    TestRunner.assertEqual(manager.sessionDecisions.count, 3, "Third decision recorded")
    TestRunner.assertEqual(manager.sessionDecisions.last?.action, .sessionApproved, "Session approved recorded")

    // Clear decision log
    manager.clearDecisionLog()
    TestRunner.assertEqual(manager.sessionDecisions.count, 0, "Decisions cleared")
}

// MARK: - ApprovalDecision Tests

func testApprovalDecision() {
    TestRunner.suite("ApprovalDecision Tests")

    let toolCall = MockToolCall(id: "test-id", toolName: "github_search", connectorID: "github-mcp")

    // Test basic decision creation
    let decision1 = ApprovalDecision(toolCall: toolCall, action: .approved)
    TestRunner.assertEqual(decision1.requestId, "test-id", "Request ID matches tool call ID")
    TestRunner.assertEqual(decision1.toolName, "github_search", "Tool name captured")
    TestRunner.assertEqual(decision1.connectorId, "github-mcp", "Connector ID captured")
    TestRunner.assertEqual(decision1.action, .approved, "Action captured")
    TestRunner.assertFalse(decision1.rememberForSession, "rememberForSession defaults to false")
    TestRunner.assertNil(decision1.reason, "Reason is nil by default")

    // Test decision with remember for session
    let decision2 = ApprovalDecision(toolCall: toolCall, action: .approved, rememberForSession: true)
    TestRunner.assertTrue(decision2.rememberForSession, "rememberForSession can be set to true")

    // Test denied decision with reason
    let decision3 = ApprovalDecision(toolCall: toolCall, action: .denied, reason: "Not allowed")
    TestRunner.assertEqual(decision3.action, .denied, "Denied action captured")
    TestRunner.assertEqual(decision3.reason, "Not allowed", "Reason captured for denied")

    // Test session approved decision
    let decision4 = ApprovalDecision(toolCall: toolCall, action: .sessionApproved, reason: "Previously approved")
    TestRunner.assertEqual(decision4.action, .sessionApproved, "Session approved action captured")
    TestRunner.assertEqual(decision4.reason, "Previously approved", "Reason captured")
}

// MARK: - Multiple Sessions Test

func testMultipleSessions() {
    TestRunner.suite("Multiple Sessions Tests")

    // Create two sessions
    let session1Memory = SessionApprovalMemory(sessionId: "session-1")
    let session2Memory = SessionApprovalMemory(sessionId: "session-2")

    // Approve tool in session 1
    session1Memory.remember(toolName: "github_search")
    session1Memory.remember(toolName: "slack_post")

    // Approve different tool in session 2
    session2Memory.remember(toolName: "jira_create")

    let manager = TestToolApprovalManager()

    // Verify session 1 has its approvals
    let toolGithub = MockToolCall(toolName: "github_search", connectorID: "github-mcp")
    if case .sessionApproved = manager.evaluateToolCall(toolGithub, sessionMemory: session1Memory) {
        TestRunner.assertTrue(true, "github_search approved in session 1")
    } else {
        TestRunner.assertTrue(false, "github_search approved in session 1")
    }

    // Verify session 2 does NOT have session 1's approvals
    if case .needsApproval = manager.evaluateToolCall(toolGithub, sessionMemory: session2Memory) {
        TestRunner.assertTrue(true, "github_search NOT approved in session 2")
    } else {
        TestRunner.assertTrue(false, "github_search NOT approved in session 2")
    }

    // Verify session 2 has its own approvals
    let toolJira = MockToolCall(toolName: "jira_create", connectorID: "jira-mcp")
    if case .sessionApproved = manager.evaluateToolCall(toolJira, sessionMemory: session2Memory) {
        TestRunner.assertTrue(true, "jira_create approved in session 2")
    } else {
        TestRunner.assertTrue(false, "jira_create approved in session 2")
    }

    // Verify session counts
    TestRunner.assertEqual(session1Memory.count, 2, "Session 1 has 2 approvals")
    TestRunner.assertEqual(session2Memory.count, 1, "Session 2 has 1 approval")
}

// MARK: - Edge Cases Tests

func testEdgeCases() {
    TestRunner.suite("Edge Cases Tests")

    let memory = SessionApprovalMemory(sessionId: "test")

    // Test empty tool name
    memory.remember(toolName: "")
    TestRunner.assertTrue(memory.isApproved(toolName: ""), "Empty tool name can be remembered")
    TestRunner.assertEqual(memory.count, 1, "Empty tool name counted")

    // Test tool name with special characters
    memory.remember(toolName: "tool-with-dashes_and_underscores.and.dots")
    TestRunner.assertTrue(
        memory.isApproved(toolName: "tool-with-dashes_and_underscores.and.dots"),
        "Special characters in tool name"
    )

    // Test case sensitivity
    memory.remember(toolName: "GitHub_Search")
    TestRunner.assertTrue(memory.isApproved(toolName: "GitHub_Search"), "Exact case matches")
    TestRunner.assertFalse(memory.isApproved(toolName: "github_search"), "Different case doesn't match")

    // Test unicode tool names
    memory.remember(toolName: "工具_测试")
    TestRunner.assertTrue(memory.isApproved(toolName: "工具_测试"), "Unicode tool name works")

    // Test very long tool name
    let longToolName = String(repeating: "a", count: 1000)
    memory.remember(toolName: longToolName)
    TestRunner.assertTrue(memory.isApproved(toolName: longToolName), "Very long tool name works")
}

// MARK: - Main Entry Point

@main
struct ToolApprovalManagerTests {
    static func main() {
        print("\u{1F9EA} Tool Approval Manager Tests (Phase 1: Session-based)")
        print(String(repeating: "=", count: 50))

        testApprovalState()
        testApprovalAction()
        testToolApprovalError()
        testSessionApprovalMemory()
        testSessionBasedEvaluation()
        testApprovalStateTransitions()
        testDecisionRecording()
        testApprovalDecision()
        testMultipleSessions()
        testEdgeCases()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
