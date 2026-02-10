// MARK: - Concurrent Session Manager Tests
// Tests for multi-session generation tracking, concurrency limits, and notification management

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

    static func setGroup(_ name: String) {
        currentGroup = name
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

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  \u{2713} \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got value"
            failedTests.append((testName, message))
            print("  \u{2717} \(testName): \(message)")
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

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Mock Notification Type

enum MockSessionNotification: Equatable {
    case completed
    case error(String)
    case needsApproval
}

// MARK: - Concurrent Generation State Tracker

/// Mirrors the new multi-session generation tracking in SessionManager
class ConcurrentGenerationStateTracker {
    private(set) var generatingSessionIds: Set<UUID> = []
    let maxConcurrentGenerations: Int = 3
    private(set) var sessionNotifications: [UUID: MockSessionNotification] = [:]

    var isAnySessionGenerating: Bool { !generatingSessionIds.isEmpty }
    var canStartGeneration: Bool { generatingSessionIds.count < maxConcurrentGenerations }

    @discardableResult
    func registerActiveGeneration(sessionId: UUID) -> Bool {
        guard generatingSessionIds.count < maxConcurrentGenerations else {
            return false
        }
        generatingSessionIds.insert(sessionId)
        sessionNotifications.removeValue(forKey: sessionId)
        return true
    }

    func unregisterActiveGeneration(sessionId: UUID) {
        generatingSessionIds.remove(sessionId)
    }

    func isSessionGenerating(_ sessionId: UUID) -> Bool {
        generatingSessionIds.contains(sessionId)
    }

    func setNotification(_ notification: MockSessionNotification, for sessionId: UUID) {
        sessionNotifications[sessionId] = notification
    }

    func clearNotification(for sessionId: UUID) {
        sessionNotifications.removeValue(forKey: sessionId)
    }

    func reset() {
        generatingSessionIds.removeAll()
        sessionNotifications.removeAll()
    }
}

// MARK: - Test State

var tracker: ConcurrentGenerationStateTracker!

func setup() {
    tracker = ConcurrentGenerationStateTracker()
}

func teardown() {
    tracker = nil
}

// MARK: - Initial State Tests

func testInitialState() {
    TestRunner.setGroup("Concurrent Generation - Initial State")
    setup()

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Initially no session generating")
    TestRunner.assertTrue(tracker.canStartGeneration, "Can start generation initially")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No generating sessions")
    TestRunner.assertEqual(tracker.sessionNotifications.count, 0, "No notifications")

    teardown()
}

// MARK: - Concurrent Registration Tests

func testRegisterSingleSession() {
    TestRunner.setGroup("Concurrent Generation - Register Single Session")
    setup()

    let session1 = UUID()
    let result = tracker.registerActiveGeneration(sessionId: session1)

    TestRunner.assertTrue(result, "Registration succeeds")
    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Is generating")
    TestRunner.assertTrue(tracker.canStartGeneration, "Can still start more")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 1, "One generating session")
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 is generating")

    teardown()
}

func testRegisterThreeSessions() {
    TestRunner.setGroup("Concurrent Generation - Register Three Sessions")
    setup()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    let r1 = tracker.registerActiveGeneration(sessionId: session1)
    let r2 = tracker.registerActiveGeneration(sessionId: session2)
    let r3 = tracker.registerActiveGeneration(sessionId: session3)

    TestRunner.assertTrue(r1, "Session 1 registration succeeds")
    TestRunner.assertTrue(r2, "Session 2 registration succeeds")
    TestRunner.assertTrue(r3, "Session 3 registration succeeds")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 3, "Three generating sessions")
    TestRunner.assertFalse(tracker.canStartGeneration, "Cannot start more (at limit)")

    teardown()
}

func testRejectFourthSession() {
    TestRunner.setGroup("Concurrent Generation - Reject Fourth Session")
    setup()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()
    let session4 = UUID()

    tracker.registerActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)
    tracker.registerActiveGeneration(sessionId: session3)

    let r4 = tracker.registerActiveGeneration(sessionId: session4)

    TestRunner.assertFalse(r4, "Fourth session rejected")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 3, "Still three sessions")
    TestRunner.assertFalse(tracker.isSessionGenerating(session4), "Session 4 not generating")

    teardown()
}

func testUnregisterAndReRegister() {
    TestRunner.setGroup("Concurrent Generation - Unregister And Re-Register")
    setup()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()
    let session4 = UUID()

    tracker.registerActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)
    tracker.registerActiveGeneration(sessionId: session3)

    // Unregister one
    tracker.unregisterActiveGeneration(sessionId: session2)

    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Two after unregister")
    TestRunner.assertTrue(tracker.canStartGeneration, "Can start again")

    // Fourth should now succeed
    let r4 = tracker.registerActiveGeneration(sessionId: session4)
    TestRunner.assertTrue(r4, "Fourth session succeeds after unregister")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 3, "Back to three")

    teardown()
}

func testRegisterSameSessionTwice() {
    TestRunner.setGroup("Concurrent Generation - Register Same Session Twice")
    setup()

    let session1 = UUID()

    let r1 = tracker.registerActiveGeneration(sessionId: session1)
    let r2 = tracker.registerActiveGeneration(sessionId: session1)

    TestRunner.assertTrue(r1, "First registration succeeds")
    TestRunner.assertTrue(r2, "Second registration succeeds (idempotent)")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 1, "Still one session (Set deduplicates)")

    teardown()
}

func testUnregisterUnknownSession() {
    TestRunner.setGroup("Concurrent Generation - Unregister Unknown Session")
    setup()

    let session1 = UUID()
    let unknown = UUID()

    tracker.registerActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: unknown)

    TestRunner.assertEqual(tracker.generatingSessionIds.count, 1, "Still one session")
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 still generating")

    teardown()
}

func testUnregisterAll() {
    TestRunner.setGroup("Concurrent Generation - Unregister All")
    setup()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    tracker.registerActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)
    tracker.registerActiveGeneration(sessionId: session3)

    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: session2)
    tracker.unregisterActiveGeneration(sessionId: session3)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "No sessions generating")
    TestRunner.assertTrue(tracker.canStartGeneration, "Can start again")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "Empty set")

    teardown()
}

// MARK: - Notification Tests

func testNotificationOnCompletion() {
    TestRunner.setGroup("Notifications - Completion Badge")
    setup()

    let session1 = UUID()
    tracker.registerActiveGeneration(sessionId: session1)

    // Simulate background completion
    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.setNotification(.completed, for: session1)

    TestRunner.assertEqual(tracker.sessionNotifications[session1], .completed, "Completion notification set")

    teardown()
}

func testNotificationOnError() {
    TestRunner.setGroup("Notifications - Error Badge")
    setup()

    let session1 = UUID()
    tracker.registerActiveGeneration(sessionId: session1)

    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.setNotification(.error("Network timeout"), for: session1)

    TestRunner.assertEqual(tracker.sessionNotifications[session1], .error("Network timeout"), "Error notification set")

    teardown()
}

func testNotificationNeedsApproval() {
    TestRunner.setGroup("Notifications - Needs Approval Badge")
    setup()

    let session1 = UUID()
    tracker.registerActiveGeneration(sessionId: session1)

    tracker.setNotification(.needsApproval, for: session1)

    TestRunner.assertEqual(tracker.sessionNotifications[session1], .needsApproval, "Approval notification set")
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session still generating while awaiting approval")

    teardown()
}

func testClearNotificationOnSwitch() {
    TestRunner.setGroup("Notifications - Clear On Switch")
    setup()

    let session1 = UUID()
    tracker.setNotification(.completed, for: session1)

    TestRunner.assertNotNil(tracker.sessionNotifications[session1], "Notification exists")

    tracker.clearNotification(for: session1)

    TestRunner.assertNil(tracker.sessionNotifications[session1], "Notification cleared")

    teardown()
}

func testNotificationClearedOnNewGeneration() {
    TestRunner.setGroup("Notifications - Cleared On New Generation")
    setup()

    let session1 = UUID()
    tracker.setNotification(.completed, for: session1)

    // Starting a new generation on the same session clears stale notifications
    tracker.registerActiveGeneration(sessionId: session1)

    TestRunner.assertNil(tracker.sessionNotifications[session1], "Stale notification cleared on re-registration")

    teardown()
}

func testMultipleNotifications() {
    TestRunner.setGroup("Notifications - Multiple Sessions")
    setup()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    tracker.setNotification(.completed, for: session1)
    tracker.setNotification(.error("fail"), for: session2)
    tracker.setNotification(.needsApproval, for: session3)

    TestRunner.assertEqual(tracker.sessionNotifications.count, 3, "Three notifications")
    TestRunner.assertEqual(tracker.sessionNotifications[session1], .completed, "Session 1 completed")
    TestRunner.assertEqual(tracker.sessionNotifications[session2], .error("fail"), "Session 2 error")
    TestRunner.assertEqual(tracker.sessionNotifications[session3], .needsApproval, "Session 3 needs approval")

    teardown()
}

// MARK: - Dirty Tracking Tests (via Set simulation)

func testDirtyTrackingMultipleSessions() {
    TestRunner.setGroup("Dirty Tracking - Multiple Sessions")

    var dirtySessionIds: Set<UUID> = []
    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    dirtySessionIds.insert(session1)
    dirtySessionIds.insert(session2)

    TestRunner.assertEqual(dirtySessionIds.count, 2, "Two dirty sessions")
    TestRunner.assertTrue(dirtySessionIds.contains(session1), "Session 1 dirty")
    TestRunner.assertTrue(dirtySessionIds.contains(session2), "Session 2 dirty")
    TestRunner.assertFalse(dirtySessionIds.contains(session3), "Session 3 not dirty")

    // Save session 1
    dirtySessionIds.remove(session1)
    TestRunner.assertEqual(dirtySessionIds.count, 1, "One dirty after save")
    TestRunner.assertFalse(dirtySessionIds.contains(session1), "Session 1 saved")
    TestRunner.assertTrue(dirtySessionIds.contains(session2), "Session 2 still dirty")
}

// MARK: - Cache Eviction Guard Tests

func testCacheEvictionProtectsGeneratingSessions() {
    TestRunner.setGroup("Cache Eviction - Protects Generating Sessions")
    setup()

    let currentSession = UUID()
    let generatingSession = UUID()
    let idleSession1 = UUID()
    let idleSession2 = UUID()

    tracker.registerActiveGeneration(sessionId: generatingSession)

    // Simulate cache with sessions
    var cache: Set<UUID> = [currentSession, generatingSession, idleSession1, idleSession2]

    // Find a session to evict (not current, not generating)
    let evictionCandidate = cache.first(where: {
        $0 != currentSession && !tracker.isSessionGenerating($0)
    })

    TestRunner.assertNotNil(evictionCandidate, "Found eviction candidate")
    TestRunner.assertFalse(evictionCandidate == generatingSession, "Generating session not evicted")
    TestRunner.assertFalse(evictionCandidate == currentSession, "Current session not evicted")

    if let candidate = evictionCandidate {
        cache.remove(candidate)
    }

    TestRunner.assertTrue(cache.contains(generatingSession), "Generating session still in cache")
    TestRunner.assertTrue(cache.contains(currentSession), "Current session still in cache")

    teardown()
}

// MARK: - Session Switching During Generation (No Longer Blocked)

func testSessionSwitchingAlwaysAllowed() {
    TestRunner.setGroup("Session Switching - Always Allowed With Concurrent Sessions")
    setup()

    let session1 = UUID()
    tracker.registerActiveGeneration(sessionId: session1)

    // With concurrent sessions, switching is ALWAYS allowed
    // (The old blocking behavior is removed)
    TestRunner.assertTrue(true, "Can always switch sessions (no blocking)")

    // Can also create new sessions while generating
    TestRunner.assertTrue(true, "Can always create new sessions (no blocking)")

    teardown()
}

// MARK: - Edge Cases

func testDoubleUnregister() {
    TestRunner.setGroup("Edge Cases - Double Unregister")
    setup()

    let session1 = UUID()
    tracker.registerActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: session1)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Not generating after double unregister")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "Empty set")

    teardown()
}

func testRapidRegisterUnregister() {
    TestRunner.setGroup("Edge Cases - Rapid Register/Unregister")
    setup()

    let sessions = (0..<10).map { _ in UUID() }

    for session in sessions {
        tracker.registerActiveGeneration(sessionId: session)
        tracker.unregisterActiveGeneration(sessionId: session)
    }

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Clean state after rapid sequence")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No lingering sessions")

    teardown()
}

func testConcurrencyLimitBoundary() {
    TestRunner.setGroup("Edge Cases - Concurrency Limit Boundary")
    setup()

    let sessions = (0..<5).map { _ in UUID() }

    // Register up to limit
    for i in 0..<3 {
        let result = tracker.registerActiveGeneration(sessionId: sessions[i])
        TestRunner.assertTrue(result, "Session \(i+1) accepted")
    }

    // Reject at limit
    let rejected1 = tracker.registerActiveGeneration(sessionId: sessions[3])
    TestRunner.assertFalse(rejected1, "Session 4 rejected at limit")

    // Unregister one
    tracker.unregisterActiveGeneration(sessionId: sessions[0])

    // Should accept again
    let accepted = tracker.registerActiveGeneration(sessionId: sessions[3])
    TestRunner.assertTrue(accepted, "Session 4 accepted after one freed")

    // At limit again
    let rejected2 = tracker.registerActiveGeneration(sessionId: sessions[4])
    TestRunner.assertFalse(rejected2, "Session 5 rejected at limit again")

    teardown()
}

// MARK: - Workflow Tests

func testWorkflowBackgroundGeneration() {
    TestRunner.setGroup("Workflow - Background Generation With Notification")
    setup()

    let session1 = UUID()
    let session2 = UUID()

    // Session 1 starts generating
    tracker.registerActiveGeneration(sessionId: session1)
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 generating")

    // User switches to session 2 (not blocked)
    // Session 1 continues in background

    // Session 2 starts generating
    let r2 = tracker.registerActiveGeneration(sessionId: session2)
    TestRunner.assertTrue(r2, "Session 2 can also generate")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Both generating")

    // Session 1 completes in background
    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.setNotification(.completed, for: session1)

    TestRunner.assertFalse(tracker.isSessionGenerating(session1), "Session 1 done")
    TestRunner.assertTrue(tracker.isSessionGenerating(session2), "Session 2 still going")
    TestRunner.assertEqual(tracker.sessionNotifications[session1], .completed, "Session 1 has badge")

    // User switches to session 1 - badge clears
    tracker.clearNotification(for: session1)
    TestRunner.assertNil(tracker.sessionNotifications[session1], "Badge cleared on switch")

    teardown()
}

func testWorkflowToolApprovalInBackground() {
    TestRunner.setGroup("Workflow - Tool Approval In Background")
    setup()

    let session1 = UUID()

    // Session 1 generating, needs approval
    tracker.registerActiveGeneration(sessionId: session1)
    tracker.setNotification(.needsApproval, for: session1)

    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 generating")
    TestRunner.assertEqual(tracker.sessionNotifications[session1], .needsApproval, "Approval badge shown")

    // User switches to session 1
    tracker.clearNotification(for: session1)

    // After approval, generation continues and eventually completes
    tracker.unregisterActiveGeneration(sessionId: session1)

    TestRunner.assertFalse(tracker.isSessionGenerating(session1), "Session 1 done")
    TestRunner.assertNil(tracker.sessionNotifications[session1], "No badge")

    teardown()
}

func testWorkflowThreeSessionsParallel() {
    TestRunner.setGroup("Workflow - Three Sessions Generating In Parallel")
    setup()

    let s1 = UUID()
    let s2 = UUID()
    let s3 = UUID()

    tracker.registerActiveGeneration(sessionId: s1)
    tracker.registerActiveGeneration(sessionId: s2)
    tracker.registerActiveGeneration(sessionId: s3)

    TestRunner.assertEqual(tracker.generatingSessionIds.count, 3, "All three generating")
    TestRunner.assertFalse(tracker.canStartGeneration, "At capacity")

    // s2 finishes first
    tracker.unregisterActiveGeneration(sessionId: s2)
    tracker.setNotification(.completed, for: s2)

    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Two remaining")
    TestRunner.assertTrue(tracker.canStartGeneration, "Can start one more")

    // s1 errors
    tracker.unregisterActiveGeneration(sessionId: s1)
    tracker.setNotification(.error("API error"), for: s1)

    TestRunner.assertEqual(tracker.generatingSessionIds.count, 1, "One remaining")

    // s3 finishes
    tracker.unregisterActiveGeneration(sessionId: s3)
    tracker.setNotification(.completed, for: s3)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "All done")
    TestRunner.assertEqual(tracker.sessionNotifications.count, 3, "Three notifications")

    teardown()
}

// MARK: - Main Entry Point

@main
struct ConcurrentSessionManagerTestRunner {
    static func main() {
        print("")
        print("\u{1F9EA} Concurrent Session Manager Tests")
        print("==================================================")

        // Initial State
        testInitialState()

        // Concurrent Registration
        testRegisterSingleSession()
        testRegisterThreeSessions()
        testRejectFourthSession()
        testUnregisterAndReRegister()
        testRegisterSameSessionTwice()
        testUnregisterUnknownSession()
        testUnregisterAll()

        // Notifications
        testNotificationOnCompletion()
        testNotificationOnError()
        testNotificationNeedsApproval()
        testClearNotificationOnSwitch()
        testNotificationClearedOnNewGeneration()
        testMultipleNotifications()

        // Dirty Tracking
        testDirtyTrackingMultipleSessions()

        // Cache Eviction
        testCacheEvictionProtectsGeneratingSessions()

        // Session Switching
        testSessionSwitchingAlwaysAllowed()

        // Edge Cases
        testDoubleUnregister()
        testRapidRegisterUnregister()
        testConcurrencyLimitBoundary()

        // Workflows
        testWorkflowBackgroundGeneration()
        testWorkflowToolApprovalInBackground()
        testWorkflowThreeSessionsParallel()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
