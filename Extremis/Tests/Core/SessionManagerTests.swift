// MARK: - SessionManager Unit Tests
// Tests for generation state tracking and session switching blocking functionality

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
        print("📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got value"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
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

// MARK: - Mock Session Storage

/// In-memory storage for testing without disk I/O
class MockSessionStorage {
    var sessions: [UUID: MockPersistedSession] = [:]
    var activeSessionId: UUID?
    var indexEntries: [MockSessionIndexEntry] = []

    func saveSession(_ session: MockPersistedSession) {
        sessions[session.id] = session
        // Update or add index entry
        if let index = indexEntries.firstIndex(where: { $0.id == session.id }) {
            indexEntries[index] = MockSessionIndexEntry(
                id: session.id,
                title: session.title,
                updatedAt: session.updatedAt,
                messageCount: session.messages.count
            )
        } else {
            indexEntries.append(MockSessionIndexEntry(
                id: session.id,
                title: session.title,
                updatedAt: session.updatedAt,
                messageCount: session.messages.count
            ))
        }
    }

    func loadSession(id: UUID) -> MockPersistedSession? {
        sessions[id]
    }

    func deleteSession(id: UUID) {
        sessions.removeValue(forKey: id)
        indexEntries.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = nil
        }
    }

    func listSessions() -> [MockSessionIndexEntry] {
        indexEntries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func setActiveSessionId(_ id: UUID?) {
        activeSessionId = id
    }

    func getActiveSessionId() -> UUID? {
        activeSessionId
    }

    func clear() {
        sessions = [:]
        activeSessionId = nil
        indexEntries = []
    }
}

struct MockPersistedSession {
    let id: UUID
    var title: String
    var messages: [MockMessage]
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Session", messages: [MockMessage] = [], updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

struct MockSessionIndexEntry {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messageCount: Int
}

struct MockMessage {
    let id: UUID
    let role: String
    let content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Mock Generation State Tracker

/// Simplified version of SessionManager's generation state tracking for testing
class GenerationStateTracker {
    private(set) var isAnySessionGenerating: Bool = false
    private(set) var generatingSessionId: UUID? = nil

    /// Register that a session is actively generating (blocks session switching)
    func registerActiveGeneration(sessionId: UUID) {
        isAnySessionGenerating = true
        generatingSessionId = sessionId
    }

    /// Unregister when generation completes (re-enables session switching)
    func unregisterActiveGeneration(sessionId: UUID) {
        // Only clear if this is the session that was generating
        if generatingSessionId == sessionId {
            isAnySessionGenerating = false
            generatingSessionId = nil
        }
    }

    /// Check if session switching should be blocked
    func canSwitchSession() -> Bool {
        !isAnySessionGenerating
    }

    /// Check if starting a new session is allowed
    func canStartNewSession() -> Bool {
        !isAnySessionGenerating
    }

    /// Check if a specific session row should be disabled
    func isSessionRowDisabled(sessionId: UUID) -> Bool {
        isAnySessionGenerating && sessionId != generatingSessionId
    }

    func reset() {
        isAnySessionGenerating = false
        generatingSessionId = nil
    }
}

// MARK: - Test Cases

var tracker: GenerationStateTracker!

func setupTracker() {
    tracker = GenerationStateTracker()
}

func teardownTracker() {
    tracker = nil
}

// MARK: - Generation State Tests

func testGenerationState_InitialState() {
    TestRunner.setGroup("Generation State - Initial State")
    setupTracker()

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Initially no session generating")
    TestRunner.assertNil(tracker.generatingSessionId, "Initially no generating session ID")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch session initially")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new session initially")

    teardownTracker()
}

func testGenerationState_RegisterGeneration() {
    TestRunner.setGroup("Generation State - Register Generation")
    setupTracker()

    let sessionId = UUID()
    tracker.registerActiveGeneration(sessionId: sessionId)

    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Generation flag set")
    TestRunner.assertEqual(tracker.generatingSessionId, sessionId, "Generating session ID set")
    TestRunner.assertFalse(tracker.canSwitchSession(), "Cannot switch during generation")
    TestRunner.assertFalse(tracker.canStartNewSession(), "Cannot start new during generation")

    teardownTracker()
}

func testGenerationState_UnregisterGeneration() {
    TestRunner.setGroup("Generation State - Unregister Generation")
    setupTracker()

    let sessionId = UUID()
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.unregisterActiveGeneration(sessionId: sessionId)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Generation flag cleared")
    TestRunner.assertNil(tracker.generatingSessionId, "Generating session ID cleared")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after generation")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new after generation")

    teardownTracker()
}

func testGenerationState_UnregisterWrongSession() {
    TestRunner.setGroup("Generation State - Unregister Wrong Session")
    setupTracker()

    let sessionId1 = UUID()
    let sessionId2 = UUID()

    tracker.registerActiveGeneration(sessionId: sessionId1)
    tracker.unregisterActiveGeneration(sessionId: sessionId2)  // Wrong session

    // State should remain unchanged because the wrong session tried to unregister
    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Generation flag still set")
    TestRunner.assertEqual(tracker.generatingSessionId, sessionId1, "Original session ID preserved")
    TestRunner.assertFalse(tracker.canSwitchSession(), "Still cannot switch")

    teardownTracker()
}

func testGenerationState_MultipleRegistersSameSession() {
    TestRunner.setGroup("Generation State - Multiple Registers Same Session")
    setupTracker()

    let sessionId = UUID()

    // Register multiple times (shouldn't break anything)
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.registerActiveGeneration(sessionId: sessionId)

    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Still generating")
    TestRunner.assertEqual(tracker.generatingSessionId, sessionId, "Session ID correct")

    // Single unregister should clear
    tracker.unregisterActiveGeneration(sessionId: sessionId)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Generation cleared")
    TestRunner.assertNil(tracker.generatingSessionId, "Session ID cleared")

    teardownTracker()
}

// MARK: - Session Row Disabled State Tests

func testSessionRowDisabled_NoGeneration() {
    TestRunner.setGroup("Session Row Disabled - No Generation")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()

    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session1), "Session 1 not disabled")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session2), "Session 2 not disabled")

    teardownTracker()
}

func testSessionRowDisabled_DuringGeneration() {
    TestRunner.setGroup("Session Row Disabled - During Generation")
    setupTracker()

    let generatingSession = UUID()
    let otherSession1 = UUID()
    let otherSession2 = UUID()

    tracker.registerActiveGeneration(sessionId: generatingSession)

    // Generating session should NOT be disabled (it's the active one)
    TestRunner.assertFalse(
        tracker.isSessionRowDisabled(sessionId: generatingSession),
        "Generating session not disabled"
    )

    // Other sessions SHOULD be disabled
    TestRunner.assertTrue(
        tracker.isSessionRowDisabled(sessionId: otherSession1),
        "Other session 1 is disabled"
    )
    TestRunner.assertTrue(
        tracker.isSessionRowDisabled(sessionId: otherSession2),
        "Other session 2 is disabled"
    )

    teardownTracker()
}

func testSessionRowDisabled_AfterGenerationComplete() {
    TestRunner.setGroup("Session Row Disabled - After Generation Complete")
    setupTracker()

    let generatingSession = UUID()
    let otherSession = UUID()

    tracker.registerActiveGeneration(sessionId: generatingSession)
    tracker.unregisterActiveGeneration(sessionId: generatingSession)

    // All sessions should be enabled again
    TestRunner.assertFalse(
        tracker.isSessionRowDisabled(sessionId: generatingSession),
        "Previous generating session not disabled"
    )
    TestRunner.assertFalse(
        tracker.isSessionRowDisabled(sessionId: otherSession),
        "Other session not disabled"
    )

    teardownTracker()
}

// MARK: - Session Switching Block Tests

func testSessionSwitching_BlockedDuringGeneration() {
    TestRunner.setGroup("Session Switching - Blocked During Generation")
    setupTracker()

    let currentSession = UUID()
    _ = UUID()  // Target session we'd try to switch to

    // Start generation on current session
    tracker.registerActiveGeneration(sessionId: currentSession)

    // Simulate trying to switch to another session
    let canSwitch = tracker.canSwitchSession()

    TestRunner.assertFalse(canSwitch, "Switching blocked during generation")

    teardownTracker()
}

func testSessionSwitching_AllowedAfterCancellation() {
    TestRunner.setGroup("Session Switching - Allowed After Cancellation")
    setupTracker()

    let currentSession = UUID()

    // Start and then cancel generation
    tracker.registerActiveGeneration(sessionId: currentSession)
    tracker.unregisterActiveGeneration(sessionId: currentSession)  // Simulates cancel

    TestRunner.assertTrue(tracker.canSwitchSession(), "Switching allowed after cancellation")

    teardownTracker()
}

func testSessionSwitching_AllowedAfterCompletion() {
    TestRunner.setGroup("Session Switching - Allowed After Completion")
    setupTracker()

    let currentSession = UUID()

    // Start and complete generation
    tracker.registerActiveGeneration(sessionId: currentSession)
    tracker.unregisterActiveGeneration(sessionId: currentSession)  // Simulates completion

    TestRunner.assertTrue(tracker.canSwitchSession(), "Switching allowed after completion")

    teardownTracker()
}

// MARK: - New Session Block Tests

func testNewSession_BlockedDuringGeneration() {
    TestRunner.setGroup("New Session - Blocked During Generation")
    setupTracker()

    let currentSession = UUID()
    tracker.registerActiveGeneration(sessionId: currentSession)

    TestRunner.assertFalse(tracker.canStartNewSession(), "New session blocked during generation")

    teardownTracker()
}

func testNewSession_AllowedAfterGeneration() {
    TestRunner.setGroup("New Session - Allowed After Generation")
    setupTracker()

    let currentSession = UUID()
    tracker.registerActiveGeneration(sessionId: currentSession)
    tracker.unregisterActiveGeneration(sessionId: currentSession)

    TestRunner.assertTrue(tracker.canStartNewSession(), "New session allowed after generation")

    teardownTracker()
}

// MARK: - Edge Cases

func testEdgeCase_RapidRegisterUnregister() {
    TestRunner.setGroup("Edge Case - Rapid Register/Unregister")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()

    // Rapid sequence of operations
    tracker.registerActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)
    tracker.unregisterActiveGeneration(sessionId: session2)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "No generation after rapid sequence")
    TestRunner.assertNil(tracker.generatingSessionId, "No session ID after rapid sequence")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after rapid sequence")

    teardownTracker()
}

func testEdgeCase_UnregisterWithoutRegister() {
    TestRunner.setGroup("Edge Case - Unregister Without Register")
    setupTracker()

    let randomSession = UUID()

    // Unregister without ever registering
    tracker.unregisterActiveGeneration(sessionId: randomSession)

    // Should remain in initial state
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Still not generating")
    TestRunner.assertNil(tracker.generatingSessionId, "Still no session ID")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Still can switch")

    teardownTracker()
}

func testEdgeCase_DoubleUnregister() {
    TestRunner.setGroup("Edge Case - Double Unregister")
    setupTracker()

    let sessionId = UUID()

    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.unregisterActiveGeneration(sessionId: sessionId)
    tracker.unregisterActiveGeneration(sessionId: sessionId)  // Second unregister

    // Should remain in cleared state
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Not generating after double unregister")
    TestRunner.assertNil(tracker.generatingSessionId, "No session ID after double unregister")

    teardownTracker()
}

func testEdgeCase_RegisterDifferentSessionWhileGenerating() {
    TestRunner.setGroup("Edge Case - Register Different Session While Generating")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()

    // This edge case tests what happens if (incorrectly) another session tries to register
    // In practice, this shouldn't happen due to UI blocking, but test the behavior
    tracker.registerActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)  // Overwrites session1

    // The second registration overwrites (this is the current implementation)
    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Still generating")
    TestRunner.assertEqual(tracker.generatingSessionId, session2, "Session 2 is now the generating one")

    // Unregister session2 should clear
    tracker.unregisterActiveGeneration(sessionId: session2)
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Generation cleared")

    // But session1's unregister won't do anything now
    tracker.unregisterActiveGeneration(sessionId: session1)
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Still not generating")

    teardownTracker()
}

// MARK: - Integration-like Tests (Simulating Full Workflows)

func testWorkflow_QuickModeGeneration() {
    TestRunner.setGroup("Workflow - Quick Mode Generation")
    setupTracker()

    let sessionId = UUID()
    let otherSession = UUID()

    // 1. Before generation starts
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch before generation")

    // 2. Generation starts (register)
    tracker.registerActiveGeneration(sessionId: sessionId)
    TestRunner.assertFalse(tracker.canSwitchSession(), "Cannot switch during generation")
    TestRunner.assertTrue(tracker.isSessionRowDisabled(sessionId: otherSession), "Other session disabled")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: sessionId), "Current session not disabled")

    // 3. Generation completes (unregister)
    tracker.unregisterActiveGeneration(sessionId: sessionId)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after generation")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: otherSession), "Other session re-enabled")

    teardownTracker()
}

func testWorkflow_ChatModeGenerationWithCancel() {
    TestRunner.setGroup("Workflow - Chat Mode Generation With Cancel")
    setupTracker()

    let sessionId = UUID()

    // 1. User sends message, generation starts
    tracker.registerActiveGeneration(sessionId: sessionId)
    TestRunner.assertFalse(tracker.canSwitchSession(), "Cannot switch during chat generation")
    TestRunner.assertFalse(tracker.canStartNewSession(), "Cannot start new during chat generation")

    // 2. User cancels generation
    tracker.unregisterActiveGeneration(sessionId: sessionId)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after cancel")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new after cancel")

    teardownTracker()
}

func testWorkflow_MultipleSessionsOneGenerating() {
    TestRunner.setGroup("Workflow - Multiple Sessions One Generating")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    // Session 2 starts generating
    tracker.registerActiveGeneration(sessionId: session2)

    // Check disabled states
    TestRunner.assertTrue(tracker.isSessionRowDisabled(sessionId: session1), "Session 1 disabled")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session2), "Session 2 (generating) not disabled")
    TestRunner.assertTrue(tracker.isSessionRowDisabled(sessionId: session3), "Session 3 disabled")

    // Cannot create new session
    TestRunner.assertFalse(tracker.canStartNewSession(), "Cannot start new")

    // Generation completes
    tracker.unregisterActiveGeneration(sessionId: session2)

    // All sessions should be enabled
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session1), "Session 1 enabled")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session2), "Session 2 enabled")
    TestRunner.assertFalse(tracker.isSessionRowDisabled(sessionId: session3), "Session 3 enabled")

    teardownTracker()
}

// MARK: - Main Entry Point

@main
struct SessionManagerTestRunner {
    static func main() {
        print("")
        print("🧪 SessionManager Generation State Tests")
        print("==================================================")

        // Initial State Tests
        testGenerationState_InitialState()

        // Generation State Tests
        testGenerationState_RegisterGeneration()
        testGenerationState_UnregisterGeneration()
        testGenerationState_UnregisterWrongSession()
        testGenerationState_MultipleRegistersSameSession()

        // Session Row Disabled Tests
        testSessionRowDisabled_NoGeneration()
        testSessionRowDisabled_DuringGeneration()
        testSessionRowDisabled_AfterGenerationComplete()

        // Session Switching Block Tests
        testSessionSwitching_BlockedDuringGeneration()
        testSessionSwitching_AllowedAfterCancellation()
        testSessionSwitching_AllowedAfterCompletion()

        // New Session Block Tests
        testNewSession_BlockedDuringGeneration()
        testNewSession_AllowedAfterGeneration()

        // Edge Case Tests
        testEdgeCase_RapidRegisterUnregister()
        testEdgeCase_UnregisterWithoutRegister()
        testEdgeCase_DoubleUnregister()
        testEdgeCase_RegisterDifferentSessionWhileGenerating()

        // Workflow Tests
        testWorkflow_QuickModeGeneration()
        testWorkflow_ChatModeGenerationWithCancel()
        testWorkflow_MultipleSessionsOneGenerating()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
