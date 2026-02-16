// MARK: - Approval Batch Routing Tests
// Tests for parking, queuing, and routing approval batches across concurrent sessions
// Validates fix for: approval buttons not showing after session switch

import Foundation

// MARK: - Test Runner

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
    }

    static func setGroup(_ name: String) {
        print("")
        print("\u{1F4E6} \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  \u{2713} \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  \u{2717} \(testName): \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  \u{2713} \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  \u{2717} \(testName): Expected true but got false")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  \u{2713} \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected nil but got value"))
            print("  \u{2717} \(testName): Expected nil but got value")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  \u{2713} \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  \u{2717} \(testName): Expected non-nil but got nil")
        }
    }

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        print("==================================================")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  \u{2717} \(name): \(message)")
            }
        }
    }
}

// MARK: - Minimal Types for Standalone Testing

/// Simulates a tool approval request
struct MockApprovalRequest: Identifiable {
    let id: String
    let toolName: String
    let connectorId: String

    init(id: String = UUID().uuidString, toolName: String = "test_tool", connectorId: String = "test_connector") {
        self.id = id
        self.toolName = toolName
        self.connectorId = connectorId
    }
}

/// Simulates a pending approval batch
struct MockApprovalBatch {
    let requests: [MockApprovalRequest]
    let sessionId: UUID?
    let completionCalled: CompletionTracker

    /// Tracks whether the completion callback was called
    class CompletionTracker {
        var called = false
        var allowAllOnce = false
        var decisionCount = 0

        func complete(decisionCount: Int, allowAllOnce: Bool) {
            self.called = true
            self.decisionCount = decisionCount
            self.allowAllOnce = allowAllOnce
        }
    }

    init(requests: [MockApprovalRequest], sessionId: UUID?) {
        self.requests = requests
        self.sessionId = sessionId
        self.completionCalled = CompletionTracker()
    }
}

/// Simulates the PromptViewModel approval state
class MockViewModel {
    var showApprovalView: Bool = false
    var pendingApprovalRequests: [MockApprovalRequest] = []
    var onApproveRequest: ((String, Bool) -> Void)?
    var onDenyRequest: ((String) -> Void)?
    var onApproveAll: (() -> Void)?
}

// MARK: - Approval Batch Router (mirrors PromptWindowController logic)

/// Testable extraction of the approval batch routing logic from PromptWindowController.
/// This mirrors the actual batch queue, park, route, and process logic.
class ApprovalBatchRouter {
    var currentApprovalBatch: MockApprovalBatch?
    var approvalQueue: [MockApprovalBatch] = []
    var accumulatedDecisions: [String: String] = [:]  // requestId -> action
    var pendingRequestIds: Set<String> = []
    var viewModel = MockViewModel()

    /// Current session ID (simulates SessionManager.shared.currentSessionId)
    var currentSessionId: UUID?

    // MARK: - showApprovalUI (mirrors PromptWindowController.showApprovalUI)

    func showApprovalUI(for requests: [MockApprovalRequest], sessionId: UUID?) {
        let batch = MockApprovalBatch(requests: requests, sessionId: sessionId)

        let isCurrentSession = sessionId == currentSessionId

        if isCurrentSession {
            if currentApprovalBatch != nil {
                approvalQueue.append(batch)
                return
            }
            startApprovalBatch(batch)
        } else {
            // Background session — queue
            approvalQueue.append(batch)
        }
    }

    // MARK: - parkActiveApprovalBatch (mirrors PromptWindowController.parkActiveApprovalBatch)

    func parkActiveApprovalBatch() {
        guard let batch = currentApprovalBatch else { return }

        approvalQueue.insert(batch, at: 0)

        currentApprovalBatch = nil
        accumulatedDecisions = [:]
        pendingRequestIds = []

        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []
    }

    // MARK: - processQueuedApprovals (mirrors PromptWindowController.processQueuedApprovals)

    func processQueuedApprovals(for sessionId: UUID) {
        let matchingBatches = approvalQueue.filter { $0.sessionId == sessionId }
        approvalQueue.removeAll { $0.sessionId == sessionId }

        guard !matchingBatches.isEmpty else { return }

        if currentApprovalBatch == nil, let first = matchingBatches.first {
            startApprovalBatch(first)
            for batch in matchingBatches.dropFirst() {
                approvalQueue.insert(batch, at: 0)
            }
        } else {
            for batch in matchingBatches.reversed() {
                approvalQueue.insert(batch, at: 0)
            }
        }
    }

    // MARK: - startApprovalBatch (mirrors PromptWindowController.startApprovalBatch)

    func startApprovalBatch(_ batch: MockApprovalBatch) {
        currentApprovalBatch = batch
        accumulatedDecisions = [:]
        pendingRequestIds = Set(batch.requests.map(\.id))

        viewModel.pendingApprovalRequests = batch.requests
        viewModel.showApprovalView = true
    }

    // MARK: - completeCurrentBatch (mirrors PromptWindowController.completeCurrentBatch)

    func completeCurrentBatch(allowAllOnce: Bool = false) {
        guard let batch = currentApprovalBatch else { return }

        let decisionCount = accumulatedDecisions.count
        currentApprovalBatch = nil
        accumulatedDecisions = [:]
        pendingRequestIds = []

        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        batch.completionCalled.complete(decisionCount: decisionCount, allowAllOnce: allowAllOnce)

        // Process next batch
        if !approvalQueue.isEmpty {
            let nextBatch = approvalQueue.removeFirst()
            startApprovalBatch(nextBatch)
        }
    }

    // MARK: - dismissApprovalUI (mirrors PromptWindowController.dismissApprovalUI)

    func dismissApprovalUI(for sessionId: UUID?) {
        if let targetSessionId = sessionId {
            // Dismiss only this session
            if let batch = currentApprovalBatch, batch.sessionId == targetSessionId {
                batch.completionCalled.complete(decisionCount: batch.requests.count, allowAllOnce: false)
                currentApprovalBatch = nil
                accumulatedDecisions = [:]
                pendingRequestIds = []
                viewModel.showApprovalView = false
                viewModel.pendingApprovalRequests = []
            }

            let batchesToDismiss = approvalQueue.filter { $0.sessionId == targetSessionId }
            approvalQueue.removeAll { $0.sessionId == targetSessionId }
            for batch in batchesToDismiss {
                batch.completionCalled.complete(decisionCount: batch.requests.count, allowAllOnce: false)
            }
        } else {
            // Dismiss everything (the old buggy path when sessionId is nil)
            if let batch = currentApprovalBatch {
                batch.completionCalled.complete(decisionCount: batch.requests.count, allowAllOnce: false)
                currentApprovalBatch = nil
                accumulatedDecisions = [:]
                pendingRequestIds = []
            }

            while !approvalQueue.isEmpty {
                let batch = approvalQueue.removeFirst()
                batch.completionCalled.complete(decisionCount: batch.requests.count, allowAllOnce: false)
            }

            viewModel.showApprovalView = false
            viewModel.pendingApprovalRequests = []
        }
    }

    // MARK: - Simulate session operations

    /// Simulates selectSession flow (with fix applied)
    func simulateSelectSession(id: UUID) {
        parkActiveApprovalBatch()
        // disconnectFromSession clears UI state (but parkActiveApprovalBatch already does this)
        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        currentSessionId = id
        processQueuedApprovals(for: id)
    }

    /// Simulates the OLD buggy selectSession flow (for regression comparison)
    func simulateOldSelectSession(id: UUID) {
        // disconnectFromSession sets session to nil
        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        // cancelGeneration() with session = nil → dismissApprovalUI(for: nil) — DESTROYS ALL
        dismissApprovalUI(for: nil)

        currentSessionId = id
        processQueuedApprovals(for: id)
    }

    /// Simulates startNewSession flow (with fix applied)
    func simulateStartNewSession() -> UUID {
        parkActiveApprovalBatch()
        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        let newId = UUID()
        currentSessionId = newId
        return newId
    }
}

// MARK: - Tests

func testParkNoActiveBatch() {
    TestRunner.setGroup("Park: No active batch (no-op)")

    let router = ApprovalBatchRouter()
    router.parkActiveApprovalBatch()

    TestRunner.assertNil(router.currentApprovalBatch, "No active batch remains nil")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue stays empty")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI stays hidden")
}

func testParkActiveBatch() {
    TestRunner.setGroup("Park: Active batch moved to queue")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let request = MockApprovalRequest(toolName: "web_search")
    let batch = MockApprovalBatch(requests: [request], sessionId: sessionA)

    router.startApprovalBatch(batch)
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown before park")
    TestRunner.assertNotNil(router.currentApprovalBatch, "Active batch set before park")

    router.parkActiveApprovalBatch()

    TestRunner.assertNil(router.currentApprovalBatch, "Active batch cleared after park")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch moved to queue")
    TestRunner.assertEqual(router.approvalQueue[0].sessionId, sessionA, "Queued batch has correct session")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI hidden after park")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 0, "Pending requests cleared")
    TestRunner.assertTrue(router.pendingRequestIds.isEmpty, "Pending IDs cleared")
    TestRunner.assertTrue(router.accumulatedDecisions.isEmpty, "Accumulated decisions cleared")
    TestRunner.assertFalse(batch.completionCalled.called, "Completion NOT called (continuation stays suspended)")
}

func testParkDoesNotCallCompletion() {
    TestRunner.setGroup("Park: Completion callback NOT invoked (critical)")

    let router = ApprovalBatchRouter()
    let batch = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: UUID())

    router.startApprovalBatch(batch)
    router.parkActiveApprovalBatch()

    TestRunner.assertFalse(batch.completionCalled.called, "Completion not called — continuation stays suspended")
}

func testParkPreservesPartialDecisions() {
    TestRunner.setGroup("Park: Partial accumulated decisions are discarded")

    // When we park, we discard accumulated decisions. When the batch is re-activated,
    // it starts fresh. This is correct because the completion hasn't been called yet —
    // all decisions need to be re-collected.
    let router = ApprovalBatchRouter()
    let req1 = MockApprovalRequest(toolName: "tool_a")
    let req2 = MockApprovalRequest(toolName: "tool_b")
    let batch = MockApprovalBatch(requests: [req1, req2], sessionId: UUID())

    router.startApprovalBatch(batch)
    // Simulate user approving one tool before switching
    router.accumulatedDecisions[req1.id] = "approved"
    router.pendingRequestIds.remove(req1.id)

    router.parkActiveApprovalBatch()

    TestRunner.assertEqual(router.accumulatedDecisions.count, 0, "Accumulated decisions cleared on park")
    TestRunner.assertTrue(router.pendingRequestIds.isEmpty, "Pending IDs cleared on park")

    // When re-activated, ALL requests show as pending again
    router.processQueuedApprovals(for: batch.sessionId!)
    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch re-activated")
    TestRunner.assertEqual(router.pendingRequestIds.count, 2, "All requests are pending again")
}

func testSessionSwitchPreservesQueuedBatches() {
    TestRunner.setGroup("Session switch: Queued batches survive (fix validation)")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    // Background session B gets a tool call → queued
    let request = MockApprovalRequest(toolName: "web_search_fetch")
    router.showApprovalUI(for: [request], sessionId: sessionB)

    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch queued for background session")
    TestRunner.assertNil(router.currentApprovalBatch, "No active batch (different session)")

    // User switches to session B (new fixed flow)
    router.simulateSelectSession(id: sessionB)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch activated for session B")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval UI shown")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "One pending request shown")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue drained")
}

func testOldFlowDestroyedQueuedBatches() {
    TestRunner.setGroup("Regression: Old flow destroyed queued batches")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    // Background session B gets a tool call → queued
    let request = MockApprovalRequest(toolName: "web_search_fetch")
    router.showApprovalUI(for: [request], sessionId: sessionB)

    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch queued before old switch")

    // Old buggy flow: cancelGeneration with nil sessionId
    router.simulateOldSelectSession(id: sessionB)

    TestRunner.assertNil(router.currentApprovalBatch, "No active batch (destroyed)")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "Approval UI NOT shown (bug)")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty (batch was destroyed)")
}

func testSwitchAwayAndBackPreservesActiveBatch() {
    TestRunner.setGroup("Switch away and back: Active batch preserved via park")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    // Session A has an active approval batch
    let request = MockApprovalRequest(toolName: "shell_execute")
    router.showApprovalUI(for: [request], sessionId: sessionA)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Active batch for session A")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown for session A")

    // User switches to session B
    router.simulateSelectSession(id: sessionB)

    TestRunner.assertNil(router.currentApprovalBatch, "Active batch cleared")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI hidden")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Parked batch in queue")

    // User switches back to session A
    router.simulateSelectSession(id: sessionA)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch re-activated for session A")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI re-shown")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "One request shown")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue drained")
}

func testMultipleSessionsWithQueuedBatches() {
    TestRunner.setGroup("Multiple sessions: Correct batch routing")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    let sessionC = UUID()
    router.currentSessionId = sessionA

    // Session B and C each get tool calls in background
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "github_search")], sessionId: sessionB)
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "web_fetch")], sessionId: sessionC)

    TestRunner.assertEqual(router.approvalQueue.count, 2, "Two batches queued")

    // Switch to session B — only B's batch should activate
    router.simulateSelectSession(id: sessionB)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Session B batch activated")
    TestRunner.assertEqual(router.currentApprovalBatch?.sessionId, sessionB, "Correct session")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Session C batch still queued")
    TestRunner.assertEqual(router.approvalQueue[0].sessionId, sessionC, "Session C in queue")
}

func testProcessQueuedWithActiveFromDifferentSession() {
    TestRunner.setGroup("processQueuedApprovals: Active batch from different session")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()

    // Session A has active batch (shouldn't happen after park, but test the guard)
    let batchA = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA)
    router.startApprovalBatch(batchA)

    // Session B has queued batch
    let batchB = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionB)
    router.approvalQueue.append(batchB)

    // Process session B's queued batches — should re-queue since A is active
    router.processQueuedApprovals(for: sessionB)

    TestRunner.assertEqual(router.currentApprovalBatch?.sessionId, sessionA, "Session A batch still active")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Session B re-queued at front")
    TestRunner.assertEqual(router.approvalQueue[0].sessionId, sessionB, "Session B in queue")
}

func testProcessQueuedNoMatchingBatches() {
    TestRunner.setGroup("processQueuedApprovals: No matching batches (no-op)")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()

    // Queue has batch for session A only
    router.approvalQueue.append(MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA))

    // Process for session B — should find nothing
    router.processQueuedApprovals(for: sessionB)

    TestRunner.assertNil(router.currentApprovalBatch, "No batch activated")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI stays hidden")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Session A batch untouched")
}

func testMultipleQueuedBatchesSameSession() {
    TestRunner.setGroup("Multiple queued batches for same session")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = UUID() // Different session is current

    // Two batches queued for session A (e.g., multi-round tool calls)
    let req1 = MockApprovalRequest(toolName: "tool_round_1")
    let req2 = MockApprovalRequest(toolName: "tool_round_2")
    router.showApprovalUI(for: [req1], sessionId: sessionA)
    router.showApprovalUI(for: [req2], sessionId: sessionA)

    TestRunner.assertEqual(router.approvalQueue.count, 2, "Two batches queued")

    // Switch to session A
    router.simulateSelectSession(id: sessionA)

    TestRunner.assertNotNil(router.currentApprovalBatch, "First batch activated")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "First batch shown")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Second batch still queued")

    // Complete first batch → second should auto-activate
    router.completeCurrentBatch()

    TestRunner.assertNotNil(router.currentApprovalBatch, "Second batch auto-activated")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown for second batch")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue drained")
}

func testShowApprovalForCurrentSession() {
    TestRunner.setGroup("showApprovalUI: Current session shows immediately")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = sessionA

    let request = MockApprovalRequest(toolName: "shell_execute")
    router.showApprovalUI(for: [request], sessionId: sessionA)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch activated immediately")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown immediately")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "Request displayed")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Nothing queued")
}

func testShowApprovalForCurrentSessionWithActiveBatch() {
    TestRunner.setGroup("showApprovalUI: Current session queues if batch already active")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = sessionA

    // First batch activates
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "tool_1")], sessionId: sessionA)
    // Second batch for same session queues
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "tool_2")], sessionId: sessionA)

    TestRunner.assertNotNil(router.currentApprovalBatch, "First batch active")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Second batch queued")

    // Complete first → second activates
    router.completeCurrentBatch()

    TestRunner.assertNotNil(router.currentApprovalBatch, "Second batch now active")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

func testShowApprovalForBackgroundSession() {
    TestRunner.setGroup("showApprovalUI: Background session queues without showing UI")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    router.showApprovalUI(for: [MockApprovalRequest(toolName: "web_fetch")], sessionId: sessionB)

    TestRunner.assertNil(router.currentApprovalBatch, "No active batch (background session)")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI NOT shown")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch queued")
    TestRunner.assertEqual(router.approvalQueue[0].sessionId, sessionB, "Correct session in queue")
}

func testShowApprovalWithNilSessionId() {
    TestRunner.setGroup("showApprovalUI: nil sessionId treated as background")

    let router = ApprovalBatchRouter()
    router.currentSessionId = UUID()

    // nil sessionId != currentSessionId (UUID), so goes to background path
    router.showApprovalUI(for: [MockApprovalRequest()], sessionId: nil)

    TestRunner.assertNil(router.currentApprovalBatch, "No active batch")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch queued")
    TestRunner.assertNil(router.approvalQueue[0].sessionId, "nil sessionId preserved in queue")
}

func testShowApprovalWithNilSessionIdAndNilCurrent() {
    TestRunner.setGroup("showApprovalUI: Both nil — matches as current session")

    let router = ApprovalBatchRouter()
    router.currentSessionId = nil  // No current session

    // nil == nil → treated as current session
    router.showApprovalUI(for: [MockApprovalRequest()], sessionId: nil)

    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch activated (nil == nil)")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown")
}

func testDismissForSpecificSessionPreservesOthers() {
    TestRunner.setGroup("dismissApprovalUI(sessionId): Only dismisses target session")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()

    // Session A active, Session B queued
    let batchA = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA)
    router.startApprovalBatch(batchA)
    let batchB = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionB)
    router.approvalQueue.append(batchB)

    // Dismiss session A only
    router.dismissApprovalUI(for: sessionA)

    TestRunner.assertNil(router.currentApprovalBatch, "Session A batch dismissed")
    TestRunner.assertTrue(batchA.completionCalled.called, "Session A completion called")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Session B batch preserved")
    TestRunner.assertFalse(batchB.completionCalled.called, "Session B completion NOT called")
}

func testDismissForNilSessionIdDestroysAll() {
    TestRunner.setGroup("dismissApprovalUI(nil): Destroys everything")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()

    let batchA = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA)
    router.startApprovalBatch(batchA)
    let batchB = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionB)
    router.approvalQueue.append(batchB)

    router.dismissApprovalUI(for: nil)

    TestRunner.assertNil(router.currentApprovalBatch, "Active batch cleared")
    TestRunner.assertTrue(batchA.completionCalled.called, "Batch A completion called")
    TestRunner.assertTrue(batchB.completionCalled.called, "Batch B completion called")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

func testStartNewSessionParksActiveBatch() {
    TestRunner.setGroup("startNewSession: Parks active batch")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = sessionA

    // Session A has active approval
    let request = MockApprovalRequest(toolName: "shell_execute")
    router.showApprovalUI(for: [request], sessionId: sessionA)
    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch active before new session")

    let completionTracker = router.currentApprovalBatch!.completionCalled

    // Start new session
    _ = router.simulateStartNewSession()

    TestRunner.assertNil(router.currentApprovalBatch, "Batch parked")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI hidden")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Batch in queue")
    TestRunner.assertFalse(completionTracker.called, "Completion NOT called (parked, not dismissed)")
}

func testRapidSessionSwitching() {
    TestRunner.setGroup("Rapid switching: A→B→C→A preserves all batches")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    let sessionC = UUID()
    router.currentSessionId = sessionA

    // Each session gets a tool call
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "tool_a")], sessionId: sessionA)
    let trackerA = router.currentApprovalBatch!.completionCalled

    // A has active batch. B and C get background batches.
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "tool_b")], sessionId: sessionB)
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "tool_c")], sessionId: sessionC)

    TestRunner.assertEqual(router.approvalQueue.count, 2, "B and C queued")

    // Switch A→B
    router.simulateSelectSession(id: sessionB)
    let trackerB = router.currentApprovalBatch!.completionCalled
    TestRunner.assertNotNil(router.currentApprovalBatch, "B batch active")
    // Queue: [A, C]
    TestRunner.assertEqual(router.approvalQueue.count, 2, "A (parked) and C in queue")

    // Switch B→C
    router.simulateSelectSession(id: sessionC)
    let trackerC = router.currentApprovalBatch!.completionCalled
    TestRunner.assertNotNil(router.currentApprovalBatch, "C batch active")
    // Queue: [B, A]
    TestRunner.assertEqual(router.approvalQueue.count, 2, "B (parked) and A in queue")

    // Switch C→A
    router.simulateSelectSession(id: sessionA)
    TestRunner.assertNotNil(router.currentApprovalBatch, "A batch re-activated")
    TestRunner.assertEqual(router.currentApprovalBatch?.sessionId, sessionA, "Correct session")
    // Queue: [C, B]
    TestRunner.assertEqual(router.approvalQueue.count, 2, "C (parked) and B in queue")

    // Verify no completions were called during all the switching
    TestRunner.assertFalse(trackerA.called, "A completion never called")
    TestRunner.assertFalse(trackerB.called, "B completion never called")
    TestRunner.assertFalse(trackerC.called, "C completion never called")
}

func testParkIdempotent() {
    TestRunner.setGroup("Park: Calling twice is idempotent (no duplicate in queue)")

    let router = ApprovalBatchRouter()
    let batch = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: UUID())
    router.startApprovalBatch(batch)

    router.parkActiveApprovalBatch()
    TestRunner.assertEqual(router.approvalQueue.count, 1, "One batch in queue after first park")

    router.parkActiveApprovalBatch()  // No active batch, should be no-op
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Still one batch after second park")
}

func testCompleteCurrentBatchAutoActivatesNextForSameSession() {
    TestRunner.setGroup("Complete batch: Auto-activates next queued batch")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = sessionA

    // Two batches for session A (first activates, second queues)
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "round_1")], sessionId: sessionA)
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "round_2")], sessionId: sessionA)

    let firstTracker = router.currentApprovalBatch!.completionCalled
    router.completeCurrentBatch()

    TestRunner.assertTrue(firstTracker.called, "First batch completed")
    TestRunner.assertNotNil(router.currentApprovalBatch, "Second batch auto-started")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI stays shown for next batch")
}

func testCompleteCurrentBatchActivatesNextFromDifferentSession() {
    TestRunner.setGroup("Complete batch: Next batch from different session")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    // Session A active, session B queued
    router.showApprovalUI(for: [MockApprovalRequest()], sessionId: sessionA)
    let batchB = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionB)
    router.approvalQueue.append(batchB)

    router.completeCurrentBatch()

    // Session B's batch auto-activates (completeCurrentBatch takes next from queue regardless)
    TestRunner.assertNotNil(router.currentApprovalBatch, "Next batch activated")
    TestRunner.assertEqual(router.currentApprovalBatch?.sessionId, sessionB, "Session B batch active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown")
}

func testQueueOrderPreservedAcrossParks() {
    TestRunner.setGroup("Queue FIFO: Order preserved across park operations")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    let sessionC = UUID()

    // Queue: [B, C]
    router.approvalQueue.append(MockApprovalBatch(requests: [MockApprovalRequest(toolName: "b")], sessionId: sessionB))
    router.approvalQueue.append(MockApprovalBatch(requests: [MockApprovalRequest(toolName: "c")], sessionId: sessionC))

    // Start and park session A → inserted at front: [A, B, C]
    let batchA = MockApprovalBatch(requests: [MockApprovalRequest(toolName: "a")], sessionId: sessionA)
    router.startApprovalBatch(batchA)
    router.parkActiveApprovalBatch()

    TestRunner.assertEqual(router.approvalQueue.count, 3, "Three batches in queue")
    TestRunner.assertEqual(router.approvalQueue[0].sessionId, sessionA, "A at front (parked with priority)")
    TestRunner.assertEqual(router.approvalQueue[1].sessionId, sessionB, "B second")
    TestRunner.assertEqual(router.approvalQueue[2].sessionId, sessionC, "C third")
}

func testSwitchToSessionWithNoApprovals() {
    TestRunner.setGroup("Switch to clean session: No approvals processed")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()
    router.currentSessionId = sessionA

    // No batches for session B
    router.simulateSelectSession(id: sessionB)

    TestRunner.assertNil(router.currentApprovalBatch, "No batch activated")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI stays hidden")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

func testDismissSpecificSessionAlsoClearsQueuedBatches() {
    TestRunner.setGroup("Dismiss specific session: Clears active AND queued")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()

    // Two batches for session A — one active, one queued
    let batch1 = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA)
    router.startApprovalBatch(batch1)
    let batch2 = MockApprovalBatch(requests: [MockApprovalRequest()], sessionId: sessionA)
    router.approvalQueue.append(batch2)

    router.dismissApprovalUI(for: sessionA)

    TestRunner.assertNil(router.currentApprovalBatch, "Active batch cleared")
    TestRunner.assertTrue(batch1.completionCalled.called, "Batch 1 completion called")
    TestRunner.assertTrue(batch2.completionCalled.called, "Batch 2 completion called")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

func testNewSessionThenSwitchBack() {
    TestRunner.setGroup("New session then switch back: Full roundtrip")

    let router = ApprovalBatchRouter()
    let sessionA = UUID()
    router.currentSessionId = sessionA

    // Session A has active approval
    router.showApprovalUI(for: [MockApprovalRequest(toolName: "web_search")], sessionId: sessionA)
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI shown initially")

    let completionTracker = router.currentApprovalBatch!.completionCalled

    // Start new session (parks A's batch)
    _ = router.simulateStartNewSession()
    TestRunner.assertFalse(router.viewModel.showApprovalView, "UI hidden after new session")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "A's batch parked")

    // Switch back to session A
    router.simulateSelectSession(id: sessionA)
    TestRunner.assertTrue(router.viewModel.showApprovalView, "UI re-shown after switching back")
    TestRunner.assertNotNil(router.currentApprovalBatch, "Batch re-activated")
    TestRunner.assertFalse(completionTracker.called, "Completion never called during roundtrip")
}

// MARK: - Main

@main
struct ApprovalBatchRoutingTests {
    static func main() {
        // Park tests
        testParkNoActiveBatch()
        testParkActiveBatch()
        testParkDoesNotCallCompletion()
        testParkPreservesPartialDecisions()
        testParkIdempotent()

        // Session switch fix validation
        testSessionSwitchPreservesQueuedBatches()
        testOldFlowDestroyedQueuedBatches()
        testSwitchAwayAndBackPreservesActiveBatch()
        testStartNewSessionParksActiveBatch()
        testNewSessionThenSwitchBack()
        testRapidSessionSwitching()

        // showApprovalUI routing
        testShowApprovalForCurrentSession()
        testShowApprovalForCurrentSessionWithActiveBatch()
        testShowApprovalForBackgroundSession()
        testShowApprovalWithNilSessionId()
        testShowApprovalWithNilSessionIdAndNilCurrent()

        // processQueuedApprovals
        testProcessQueuedNoMatchingBatches()
        testProcessQueuedWithActiveFromDifferentSession()
        testMultipleQueuedBatchesSameSession()
        testMultipleSessionsWithQueuedBatches()

        // completeCurrentBatch chaining
        testCompleteCurrentBatchAutoActivatesNextForSameSession()
        testCompleteCurrentBatchActivatesNextFromDifferentSession()

        // Queue order
        testQueueOrderPreservedAcrossParks()

        // Dismiss
        testDismissForSpecificSessionPreservesOthers()
        testDismissForNilSessionIdDestroysAll()
        testDismissSpecificSessionAlsoClearsQueuedBatches()

        // Clean session
        testSwitchToSessionWithNoApprovals()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
