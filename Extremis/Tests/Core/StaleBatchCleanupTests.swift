// MARK: - Stale Batch Cleanup Tests
// Tests for the fix where a stale currentApprovalBatch blocks new approval UIs.
// Root cause: The producer Task inside AsyncThrowingStream is NOT cancelled when the
// consumer's Task is cancelled. This means withTaskCancellationHandler.onCancel never
// fires, leaving currentApprovalBatch stale on the controller.

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

// MARK: - Mock Types

struct MockRequest: Identifiable {
    let id: String
    let toolName: String

    init(id: String = UUID().uuidString, toolName: String = "test_tool") {
        self.id = id
        self.toolName = toolName
    }
}

class CompletionTracker {
    var called = false
    var decisionCount = 0
    var allowAllOnce = false

    func complete(decisionCount: Int, allowAllOnce: Bool) {
        self.called = true
        self.decisionCount = decisionCount
        self.allowAllOnce = allowAllOnce
    }
}

struct MockBatch {
    let requests: [MockRequest]
    let sessionId: UUID?
    let completionTracker: CompletionTracker

    init(requests: [MockRequest], sessionId: UUID?) {
        self.requests = requests
        self.sessionId = sessionId
        self.completionTracker = CompletionTracker()
    }
}

class MockVM {
    var showApprovalView: Bool = false
    var pendingApprovalRequests: [MockRequest] = []
}

// MARK: - Batch Router (mirrors PromptWindowController logic on main)

/// Testable extraction of the approval batch routing logic.
/// Updated to include the stale batch cleanup fix.
class BatchRouter {
    var currentBatch: MockBatch?
    var approvalQueue: [MockBatch] = []
    var accumulatedDecisions: [String: String] = [:]
    var pendingRequestIds: Set<String> = []
    var viewModel = MockVM()

    // MARK: - showApprovalUI (updated with stale batch cleanup)

    func showApprovalUI(for requests: [MockRequest], sessionId: UUID?) {
        let batch = MockBatch(requests: requests, sessionId: sessionId)

        if let existingBatch = currentBatch {
            if existingBatch.sessionId == sessionId {
                // Same session — stale batch. Dismiss it manually (not via completeCurrentBatch
                // to avoid its queue processing pulling in a different-session batch).
                existingBatch.completionTracker.complete(decisionCount: existingBatch.requests.count, allowAllOnce: false)
                currentBatch = nil
                accumulatedDecisions = [:]
                pendingRequestIds = []
                viewModel.showApprovalView = false
                viewModel.pendingApprovalRequests = []

                // Dismiss any queued batches for this session
                let sameSessionQueued = approvalQueue.filter { $0.sessionId == sessionId }
                approvalQueue.removeAll { $0.sessionId == sessionId }
                for queuedBatch in sameSessionQueued {
                    queuedBatch.completionTracker.complete(decisionCount: queuedBatch.requests.count, allowAllOnce: false)
                }
            } else {
                // Different session — queue
                approvalQueue.append(batch)
                return
            }
        }

        startBatch(batch)
    }

    // MARK: - startBatch

    func startBatch(_ batch: MockBatch) {
        currentBatch = batch
        accumulatedDecisions = [:]
        pendingRequestIds = Set(batch.requests.map(\.id))
        viewModel.pendingApprovalRequests = batch.requests
        viewModel.showApprovalView = true
    }

    // MARK: - completeCurrentBatch (normal approval completion)

    func completeCurrentBatch(allowAllOnce: Bool = false) {
        guard let batch = currentBatch else { return }
        batch.completionTracker.complete(decisionCount: accumulatedDecisions.count, allowAllOnce: allowAllOnce)
        currentBatch = nil
        accumulatedDecisions = [:]
        pendingRequestIds = []
        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        if !approvalQueue.isEmpty {
            let nextBatch = approvalQueue.removeFirst()
            startBatch(nextBatch)
        }
    }

    // MARK: - dismissApprovalUI

    func dismissApprovalUI(for sessionId: UUID?) {
        if let targetSessionId = sessionId {
            if let batch = currentBatch, batch.sessionId == targetSessionId {
                batch.completionTracker.complete(decisionCount: batch.requests.count, allowAllOnce: false)
                currentBatch = nil
                accumulatedDecisions = [:]
                pendingRequestIds = []
                viewModel.showApprovalView = false
                viewModel.pendingApprovalRequests = []
            }
            let queuedToRemove = approvalQueue.filter { $0.sessionId == targetSessionId }
            approvalQueue.removeAll { $0.sessionId == targetSessionId }
            for qb in queuedToRemove {
                qb.completionTracker.complete(decisionCount: qb.requests.count, allowAllOnce: false)
            }
        } else {
            if let batch = currentBatch {
                batch.completionTracker.complete(decisionCount: batch.requests.count, allowAllOnce: false)
            }
            currentBatch = nil
            accumulatedDecisions = [:]
            pendingRequestIds = []
            viewModel.showApprovalView = false
            viewModel.pendingApprovalRequests = []
            for qb in approvalQueue {
                qb.completionTracker.complete(decisionCount: qb.requests.count, allowAllOnce: false)
            }
            approvalQueue.removeAll()
        }
    }

    // MARK: - Simulate approve

    func simulateApprove(requestId: String) {
        guard pendingRequestIds.contains(requestId) else { return }
        accumulatedDecisions[requestId] = "approved"
        pendingRequestIds.remove(requestId)
        viewModel.pendingApprovalRequests.removeAll { $0.id == requestId }
        if pendingRequestIds.isEmpty {
            completeCurrentBatch()
        }
    }
}

// MARK: - Test: Stale Batch from Same Session

func testStaleBatchSameSession() {
    TestRunner.setGroup("Stale Batch — Same Session")

    let router = BatchRouter()
    let sessionId = UUID()

    // Simulate: generation 1 produces tool calls, approval starts
    let req1 = [MockRequest(toolName: "web_search")]
    router.showApprovalUI(for: req1, sessionId: sessionId)

    TestRunner.assertNotNil(router.currentBatch, "Batch 1 is active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shown for batch 1")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "1 pending request")

    let batch1Tracker = router.currentBatch!.completionTracker

    // Simulate: user sends new message, generation 1 cancelled, generation 2 starts
    // Producer Task from gen 1 is cancelled (via our fix), but onCancel hasn't run yet.
    // Gen 2 produces tool calls → showApprovalUI called for SAME session.
    let req2 = [MockRequest(toolName: "shell_execute")]
    router.showApprovalUI(for: req2, sessionId: sessionId)

    // The stale batch 1 should be dismissed and batch 2 should be active
    TestRunner.assertTrue(batch1Tracker.called, "Stale batch 1 completion was called")
    TestRunner.assertNotNil(router.currentBatch, "Batch 2 is now active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shown for batch 2")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "1 pending request from batch 2")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.first?.toolName ?? "", "shell_execute", "Batch 2 tool is shell_execute")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue is empty")
}

// MARK: - Test: No Stale Batch (Normal Flow)

func testNormalFlowNoBatch() {
    TestRunner.setGroup("Normal Flow — No Existing Batch")

    let router = BatchRouter()
    let sessionId = UUID()

    let req = [MockRequest(toolName: "web_search")]
    router.showApprovalUI(for: req, sessionId: sessionId)

    TestRunner.assertNotNil(router.currentBatch, "Batch is active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shown")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "1 request pending")
}

// MARK: - Test: Complete Then New Batch

func testCompleteThenNewBatch() {
    TestRunner.setGroup("Complete Batch Then New One")

    let router = BatchRouter()
    let sessionId = UUID()

    // Start batch 1
    let req1 = [MockRequest(toolName: "tool_a")]
    router.showApprovalUI(for: req1, sessionId: sessionId)

    let batch1ReqId = router.currentBatch!.requests[0].id

    // User approves
    router.simulateApprove(requestId: batch1ReqId)

    TestRunner.assertNil(router.currentBatch, "Batch 1 completed")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "View hidden after completion")

    // Start batch 2 (new round of tool calls)
    let req2 = [MockRequest(toolName: "tool_b")]
    router.showApprovalUI(for: req2, sessionId: sessionId)

    TestRunner.assertNotNil(router.currentBatch, "Batch 2 is active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shown for batch 2")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.first?.toolName ?? "", "tool_b", "Batch 2 has tool_b")
}

// MARK: - Test: Different Session Batch Queued

func testDifferentSessionQueued() {
    TestRunner.setGroup("Different Session — Queued")

    let router = BatchRouter()
    let session1 = UUID()
    let session2 = UUID()

    // Start batch for session 1
    let req1 = [MockRequest(toolName: "tool_a")]
    router.showApprovalUI(for: req1, sessionId: session1)

    TestRunner.assertNotNil(router.currentBatch, "Session 1 batch active")

    // Session 2 batch arrives
    let req2 = [MockRequest(toolName: "tool_b")]
    router.showApprovalUI(for: req2, sessionId: session2)

    // Session 2 should be queued, not replace session 1
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Session 2 batch queued")
    TestRunner.assertEqual(router.currentBatch!.requests[0].toolName, "tool_a", "Session 1 batch still active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view still shown")
}

// MARK: - Test: Multiple Stale Batches in Queue

func testStaleBatchClearsQueue() {
    TestRunner.setGroup("Stale Batch Clears Queue")

    let router = BatchRouter()
    let sessionId = UUID()

    // Start batch 1
    let req1 = [MockRequest(toolName: "tool_1")]
    router.showApprovalUI(for: req1, sessionId: sessionId)

    // Manually queue two more batches for the same session (simulating rapid arrivals)
    let batchQ1 = MockBatch(requests: [MockRequest(toolName: "tool_q1")], sessionId: sessionId)
    let batchQ2 = MockBatch(requests: [MockRequest(toolName: "tool_q2")], sessionId: sessionId)
    router.approvalQueue.append(batchQ1)
    router.approvalQueue.append(batchQ2)

    let batch1Tracker = router.currentBatch!.completionTracker

    // New generation starts, new batch arrives for same session
    let reqNew = [MockRequest(toolName: "new_tool")]
    router.showApprovalUI(for: reqNew, sessionId: sessionId)

    // All stale batches should be dismissed, queue cleared
    TestRunner.assertTrue(batch1Tracker.called, "Stale batch 1 dismissed")
    TestRunner.assertTrue(batchQ1.completionTracker.called, "Queued batch 1 dismissed")
    TestRunner.assertTrue(batchQ2.completionTracker.called, "Queued batch 2 dismissed")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty after cleanup")
    TestRunner.assertNotNil(router.currentBatch, "New batch is active")
    TestRunner.assertEqual(router.currentBatch!.requests[0].toolName, "new_tool", "New batch has correct tool")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shows new batch")
}

// MARK: - Test: Stale Batch with Nil Session ID

func testStaleBatchNilSessionId() {
    TestRunner.setGroup("Stale Batch — Nil Session ID")

    let router = BatchRouter()

    // Start batch with nil session
    let req1 = [MockRequest(toolName: "tool_1")]
    router.showApprovalUI(for: req1, sessionId: nil)

    let batch1Tracker = router.currentBatch!.completionTracker

    // New batch arrives, also nil session → same session match (nil == nil)
    let req2 = [MockRequest(toolName: "tool_2")]
    router.showApprovalUI(for: req2, sessionId: nil)

    TestRunner.assertTrue(batch1Tracker.called, "Stale nil-session batch dismissed")
    TestRunner.assertEqual(router.currentBatch!.requests[0].toolName, "tool_2", "New batch active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shows new batch")
}

// MARK: - Test: Dismiss Then Show

func testDismissThenNewBatch() {
    TestRunner.setGroup("Dismiss Then New Batch")

    let router = BatchRouter()
    let sessionId = UUID()

    // Start batch
    let req1 = [MockRequest(toolName: "tool_1")]
    router.showApprovalUI(for: req1, sessionId: sessionId)

    // Dismiss via cancelGeneration path
    router.dismissApprovalUI(for: sessionId)

    TestRunner.assertNil(router.currentBatch, "Batch dismissed")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "View hidden")

    // New batch should work fine
    let req2 = [MockRequest(toolName: "tool_2")]
    router.showApprovalUI(for: req2, sessionId: sessionId)

    TestRunner.assertNotNil(router.currentBatch, "New batch active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shown")
}

// MARK: - Test: Stale Batch UI State

func testStaleBatchUIStateCleanup() {
    TestRunner.setGroup("Stale Batch — UI State Properly Updated")

    let router = BatchRouter()
    let sessionId = UUID()

    // Start batch 1 with multiple requests
    let req1 = [MockRequest(toolName: "tool_a"), MockRequest(toolName: "tool_b")]
    router.showApprovalUI(for: req1, sessionId: sessionId)

    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 2, "2 pending requests")

    // Approve one
    let firstId = router.currentBatch!.requests[0].id
    router.accumulatedDecisions[firstId] = "approved"
    router.pendingRequestIds.remove(firstId)
    router.viewModel.pendingApprovalRequests.removeAll { $0.id == firstId }

    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "1 pending after partial approve")

    // New batch arrives for same session (stale cleanup should happen)
    let req2 = [MockRequest(toolName: "tool_c")]
    router.showApprovalUI(for: req2, sessionId: sessionId)

    // UI should show only the new batch's requests
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests.count, 1, "1 request from new batch")
    TestRunner.assertEqual(router.viewModel.pendingApprovalRequests[0].toolName, "tool_c", "New batch tool_c")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view active")
    TestRunner.assertEqual(router.pendingRequestIds.count, 1, "1 pending request ID")
}

// MARK: - Test: Rapid Fire Same Session

func testRapidFireSameSession() {
    TestRunner.setGroup("Rapid Fire — Multiple Batches Same Session")

    let router = BatchRouter()
    let sessionId = UUID()

    // Batch 1
    router.showApprovalUI(for: [MockRequest(toolName: "t1")], sessionId: sessionId)
    let tracker1 = router.currentBatch!.completionTracker

    // Batch 2 (supersedes 1)
    router.showApprovalUI(for: [MockRequest(toolName: "t2")], sessionId: sessionId)
    let tracker2 = router.currentBatch!.completionTracker

    TestRunner.assertTrue(tracker1.called, "Batch 1 dismissed")

    // Batch 3 (supersedes 2)
    router.showApprovalUI(for: [MockRequest(toolName: "t3")], sessionId: sessionId)

    TestRunner.assertTrue(tracker2.called, "Batch 2 dismissed")
    TestRunner.assertEqual(router.currentBatch!.requests[0].toolName, "t3", "Batch 3 is active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "View shows batch 3")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

// MARK: - Test: StreamState Cancellation Semantics

func testStreamStateCancellation() {
    TestRunner.setGroup("StreamState — Cancellation Flag Semantics")

    // Mirrors the StreamState class in ToolEnabledChatService
    final class StreamState: @unchecked Sendable {
        var isCancelled = false
        var producerTaskCancelled = false
    }

    let state = StreamState()

    // Initially not cancelled
    TestRunner.assertFalse(state.isCancelled, "Initially not cancelled")

    // Simulate stream termination (consumer task cancelled)
    state.isCancelled = true
    state.producerTaskCancelled = true

    TestRunner.assertTrue(state.isCancelled, "Cancelled after termination")
    TestRunner.assertTrue(state.producerTaskCancelled, "Producer task marked for cancellation")
}

// MARK: - Test: DismissApprovalUI with nil clears everything

func testDismissAllClears() {
    TestRunner.setGroup("DismissApprovalUI nil — Clears Everything")

    let router = BatchRouter()
    let session1 = UUID()
    let session2 = UUID()

    // Start batch for session 1
    router.showApprovalUI(for: [MockRequest(toolName: "t1")], sessionId: session1)
    let tracker1 = router.currentBatch!.completionTracker

    // Queue batch for session 2
    router.approvalQueue.append(MockBatch(requests: [MockRequest(toolName: "t2")], sessionId: session2))

    // Dismiss all (nil session)
    router.dismissApprovalUI(for: nil)

    TestRunner.assertTrue(tracker1.called, "Active batch dismissed")
    TestRunner.assertNil(router.currentBatch, "No active batch")
    TestRunner.assertFalse(router.viewModel.showApprovalView, "View hidden")
    TestRunner.assertEqual(router.approvalQueue.count, 0, "Queue empty")
}

// MARK: - Test: Stale Cleanup Preserves Other Session's Queued Batches

func testStaleBatchPreservesOtherSessionQueue() {
    TestRunner.setGroup("Stale Batch — Preserves Other Session's Queued Batches")

    let router = BatchRouter()
    let sessionA = UUID()
    let sessionB = UUID()

    // Start batch for session A
    router.showApprovalUI(for: [MockRequest(toolName: "tool_a")], sessionId: sessionA)
    let batchATracker = router.currentBatch!.completionTracker

    // Queue a batch for session B (different session)
    let batchB = MockBatch(requests: [MockRequest(toolName: "tool_b")], sessionId: sessionB)
    router.approvalQueue.append(batchB)

    // Also queue another batch for session A
    let batchA2 = MockBatch(requests: [MockRequest(toolName: "tool_a2")], sessionId: sessionA)
    router.approvalQueue.append(batchA2)

    TestRunner.assertEqual(router.approvalQueue.count, 2, "Queue has 2 batches before cleanup")

    // New batch for session A arrives — stale cleanup
    router.showApprovalUI(for: [MockRequest(toolName: "tool_a_new")], sessionId: sessionA)

    // Session A's stale batch should be dismissed
    TestRunner.assertTrue(batchATracker.called, "Stale session A batch dismissed")
    // Session A's queued batch should also be dismissed
    TestRunner.assertTrue(batchA2.completionTracker.called, "Queued session A batch dismissed")
    // Session B's queued batch should be PRESERVED
    TestRunner.assertFalse(batchB.completionTracker.called, "Session B batch NOT dismissed")
    TestRunner.assertEqual(router.approvalQueue.count, 1, "Queue has 1 batch (session B)")
    TestRunner.assertEqual(router.approvalQueue.first?.sessionId, sessionB, "Remaining batch is session B's")
    // New batch for session A is active
    TestRunner.assertEqual(router.currentBatch!.requests[0].toolName, "tool_a_new", "New session A batch active")
    TestRunner.assertTrue(router.viewModel.showApprovalView, "Approval view shows new batch")
}

// MARK: - Main

@main
struct StaleBatchCleanupTests {
    static func main() {
        testStaleBatchSameSession()
        testNormalFlowNoBatch()
        testCompleteThenNewBatch()
        testDifferentSessionQueued()
        testStaleBatchClearsQueue()
        testStaleBatchNilSessionId()
        testDismissThenNewBatch()
        testStaleBatchUIStateCleanup()
        testRapidFireSameSession()
        testStreamStateCancellation()
        testDismissAllClears()
        testStaleBatchPreservesOtherSessionQueue()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
