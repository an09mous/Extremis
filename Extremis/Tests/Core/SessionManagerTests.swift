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
/// Updated for multi-session concurrent generation support
class GenerationStateTracker {
    private(set) var generatingSessionIds: Set<UUID> = []
    let maxConcurrentGenerations: Int = 3

    var isAnySessionGenerating: Bool { !generatingSessionIds.isEmpty }
    var canStartGeneration: Bool { generatingSessionIds.count < maxConcurrentGenerations }

    /// Register that a session is actively generating
    @discardableResult
    func registerActiveGeneration(sessionId: UUID) -> Bool {
        guard generatingSessionIds.count < maxConcurrentGenerations else { return false }
        generatingSessionIds.insert(sessionId)
        return true
    }

    /// Unregister when generation completes
    func unregisterActiveGeneration(sessionId: UUID) {
        generatingSessionIds.remove(sessionId)
    }

    /// Session switching is always allowed with concurrent sessions
    func canSwitchSession() -> Bool {
        true
    }

    /// New session creation is always allowed with concurrent sessions
    func canStartNewSession() -> Bool {
        true
    }

    /// Check if a specific session is generating
    func isSessionGenerating(_ sessionId: UUID) -> Bool {
        generatingSessionIds.contains(sessionId)
    }

    func reset() {
        generatingSessionIds.removeAll()
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
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "Initially no generating session IDs")
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
    TestRunner.assertTrue(tracker.isSessionGenerating(sessionId), "Session is generating")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can always switch with concurrent sessions")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can always start new with concurrent sessions")

    teardownTracker()
}

func testGenerationState_UnregisterGeneration() {
    TestRunner.setGroup("Generation State - Unregister Generation")
    setupTracker()

    let sessionId = UUID()
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.unregisterActiveGeneration(sessionId: sessionId)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Generation flag cleared")
    TestRunner.assertFalse(tracker.isSessionGenerating(sessionId), "Session no longer generating")
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
    TestRunner.assertTrue(tracker.isSessionGenerating(sessionId1), "Original session still generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(sessionId2), "Wrong session not generating")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can always switch with concurrent sessions")

    teardownTracker()
}

func testGenerationState_MultipleRegistersSameSession() {
    TestRunner.setGroup("Generation State - Multiple Registers Same Session")
    setupTracker()

    let sessionId = UUID()

    // Register multiple times (idempotent - Set ignores duplicates)
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.registerActiveGeneration(sessionId: sessionId)
    tracker.registerActiveGeneration(sessionId: sessionId)

    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Still generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(sessionId), "Session is generating")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 1, "Only one entry in set (idempotent)")

    // Single unregister should clear
    tracker.unregisterActiveGeneration(sessionId: sessionId)

    TestRunner.assertFalse(tracker.isAnySessionGenerating, "Generation cleared")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No generating sessions")

    teardownTracker()
}

// MARK: - Session Generating State Tests

func testSessionGenerating_NoGeneration() {
    TestRunner.setGroup("Session Generating - No Generation")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()

    TestRunner.assertFalse(tracker.isSessionGenerating(session1), "Session 1 not generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(session2), "Session 2 not generating")

    teardownTracker()
}

func testSessionGenerating_DuringGeneration() {
    TestRunner.setGroup("Session Generating - During Generation")
    setupTracker()

    let generatingSession = UUID()
    let otherSession1 = UUID()
    let otherSession2 = UUID()

    tracker.registerActiveGeneration(sessionId: generatingSession)

    // Only the generating session should report generating
    TestRunner.assertTrue(
        tracker.isSessionGenerating(generatingSession),
        "Generating session reports generating"
    )
    TestRunner.assertFalse(
        tracker.isSessionGenerating(otherSession1),
        "Other session 1 not generating"
    )
    TestRunner.assertFalse(
        tracker.isSessionGenerating(otherSession2),
        "Other session 2 not generating"
    )

    // All sessions are always clickable (no disabled state)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can always switch sessions")

    teardownTracker()
}

func testSessionGenerating_AfterGenerationComplete() {
    TestRunner.setGroup("Session Generating - After Generation Complete")
    setupTracker()

    let generatingSession = UUID()
    let otherSession = UUID()

    tracker.registerActiveGeneration(sessionId: generatingSession)
    tracker.unregisterActiveGeneration(sessionId: generatingSession)

    // No sessions should be generating
    TestRunner.assertFalse(
        tracker.isSessionGenerating(generatingSession),
        "Previous generating session no longer generating"
    )
    TestRunner.assertFalse(
        tracker.isSessionGenerating(otherSession),
        "Other session not generating"
    )

    teardownTracker()
}

// MARK: - Session Switching Block Tests

func testSessionSwitching_AllowedDuringGeneration() {
    TestRunner.setGroup("Session Switching - Allowed During Generation")
    setupTracker()

    let currentSession = UUID()

    // Start generation on current session
    tracker.registerActiveGeneration(sessionId: currentSession)

    // With concurrent sessions, switching is always allowed
    let canSwitch = tracker.canSwitchSession()

    TestRunner.assertTrue(canSwitch, "Switching allowed during generation (concurrent sessions)")

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

func testNewSession_AllowedDuringGeneration() {
    TestRunner.setGroup("New Session - Allowed During Generation")
    setupTracker()

    let currentSession = UUID()
    tracker.registerActiveGeneration(sessionId: currentSession)

    // With concurrent sessions, new session creation is always allowed
    TestRunner.assertTrue(tracker.canStartNewSession(), "New session allowed during generation (concurrent sessions)")

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
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No generating sessions after rapid sequence")
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
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No generating sessions")
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
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 0, "No generating sessions after double unregister")

    teardownTracker()
}

func testEdgeCase_RegisterMultipleSessionsConcurrently() {
    TestRunner.setGroup("Edge Case - Register Multiple Sessions Concurrently")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    // With concurrent sessions, multiple sessions can generate simultaneously
    tracker.registerActiveGeneration(sessionId: session1)
    tracker.registerActiveGeneration(sessionId: session2)

    TestRunner.assertTrue(tracker.isAnySessionGenerating, "Still generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 is generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(session2), "Session 2 is generating")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Two sessions generating")

    // Add a third
    tracker.registerActiveGeneration(sessionId: session3)
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 3, "Three sessions generating")

    // Unregister session2 — session1 and session3 remain
    tracker.unregisterActiveGeneration(sessionId: session2)
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 still generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(session2), "Session 2 no longer generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(session3), "Session 3 still generating")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Two sessions still generating")

    // Unregister remaining
    tracker.unregisterActiveGeneration(sessionId: session1)
    tracker.unregisterActiveGeneration(sessionId: session3)
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "No sessions generating")

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
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can still switch during generation (concurrent)")
    TestRunner.assertTrue(tracker.isSessionGenerating(sessionId), "Current session is generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(otherSession), "Other session not generating")

    // 3. Generation completes (unregister)
    tracker.unregisterActiveGeneration(sessionId: sessionId)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after generation")
    TestRunner.assertFalse(tracker.isSessionGenerating(sessionId), "Session no longer generating")

    teardownTracker()
}

func testWorkflow_ChatModeGenerationWithCancel() {
    TestRunner.setGroup("Workflow - Chat Mode Generation With Cancel")
    setupTracker()

    let sessionId = UUID()

    // 1. User sends message, generation starts
    tracker.registerActiveGeneration(sessionId: sessionId)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch during chat generation (concurrent)")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new during chat generation (concurrent)")

    // 2. User cancels generation
    tracker.unregisterActiveGeneration(sessionId: sessionId)
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after cancel")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new after cancel")

    teardownTracker()
}

func testWorkflow_MultipleSessionsGenerating() {
    TestRunner.setGroup("Workflow - Multiple Sessions Generating Concurrently")
    setupTracker()

    let session1 = UUID()
    let session2 = UUID()
    let session3 = UUID()

    // Session 2 starts generating
    tracker.registerActiveGeneration(sessionId: session2)

    // Check generating states — only session2 is generating
    TestRunner.assertFalse(tracker.isSessionGenerating(session1), "Session 1 not generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(session2), "Session 2 is generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(session3), "Session 3 not generating")

    // Can still create new session and switch
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new (concurrent)")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch (concurrent)")

    // Session 1 also starts generating
    tracker.registerActiveGeneration(sessionId: session1)
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 now generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(session2), "Session 2 still generating")
    TestRunner.assertEqual(tracker.generatingSessionIds.count, 2, "Two sessions generating")

    // Session 2 completes
    tracker.unregisterActiveGeneration(sessionId: session2)
    TestRunner.assertTrue(tracker.isSessionGenerating(session1), "Session 1 still generating")
    TestRunner.assertFalse(tracker.isSessionGenerating(session2), "Session 2 done")

    // Session 1 completes
    tracker.unregisterActiveGeneration(sessionId: session1)
    TestRunner.assertFalse(tracker.isAnySessionGenerating, "All done")

    teardownTracker()
}

// MARK: - Draft Session State Tracker

/// Simplified version of SessionManager's draft session tracking for testing
class DraftSessionTracker {
    private(set) var hasDraftSession: Bool = false
    private(set) var currentSessionId: UUID? = nil
    private(set) var sessionMessageCount: Int = 0

    /// Start a new session (creates a draft)
    func startNewSession() -> UUID {
        let sessionId = UUID()
        currentSessionId = sessionId
        hasDraftSession = true
        sessionMessageCount = 0
        return sessionId
    }

    /// Add a message to the current session
    func addMessage() {
        sessionMessageCount += 1
        // Draft becomes real session once it has content
        if hasDraftSession && sessionMessageCount > 0 {
            hasDraftSession = false
        }
    }

    /// Load an existing session
    func loadSession(id: UUID, messageCount: Int) {
        // Discard any existing draft
        hasDraftSession = false
        currentSessionId = id
        sessionMessageCount = messageCount
    }

    /// Set current session with existing data
    func setCurrentSession(id: UUID, messageCount: Int) {
        currentSessionId = id
        sessionMessageCount = messageCount
        hasDraftSession = messageCount == 0
    }

    /// Clear the current session
    func clearCurrentSession() {
        currentSessionId = nil
        hasDraftSession = false
        sessionMessageCount = 0
    }

    func reset() {
        hasDraftSession = false
        currentSessionId = nil
        sessionMessageCount = 0
    }
}

// MARK: - Draft Session Tests

var draftTracker: DraftSessionTracker!

func setupDraftTracker() {
    draftTracker = DraftSessionTracker()
}

func teardownDraftTracker() {
    draftTracker = nil
}

func testDraftSession_InitialState() {
    TestRunner.setGroup("Draft Session - Initial State")
    setupDraftTracker()

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft initially")
    TestRunner.assertNil(draftTracker.currentSessionId, "No session ID initially")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages initially")

    teardownDraftTracker()
}

func testDraftSession_AfterStartNewSession() {
    TestRunner.setGroup("Draft Session - After Start New Session")
    setupDraftTracker()

    let sessionId = draftTracker.startNewSession()

    TestRunner.assertTrue(draftTracker.hasDraftSession, "Should be draft after starting new session")
    TestRunner.assertNotNil(draftTracker.currentSessionId, "Should have session ID")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Session ID matches")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages yet")

    teardownDraftTracker()
}

func testDraftSession_AfterFirstMessage() {
    TestRunner.setGroup("Draft Session - After First Message")
    setupDraftTracker()

    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft before message")

    draftTracker.addMessage()

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No longer draft after first message")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 1, "One message")

    teardownDraftTracker()
}

func testDraftSession_AfterLoadSession() {
    TestRunner.setGroup("Draft Session - After Load Session")
    setupDraftTracker()

    // Start with a draft
    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    // Load an existing session
    let existingSessionId = UUID()
    draftTracker.loadSession(id: existingSessionId, messageCount: 5)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after loading session")
    TestRunner.assertEqual(draftTracker.currentSessionId, existingSessionId, "Loaded session is current")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 5, "Has existing messages")

    teardownDraftTracker()
}

func testDraftSession_AfterClearSession() {
    TestRunner.setGroup("Draft Session - After Clear Session")
    setupDraftTracker()

    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    draftTracker.clearCurrentSession()

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after clear")
    TestRunner.assertNil(draftTracker.currentSessionId, "No session ID after clear")

    teardownDraftTracker()
}

func testDraftSession_SetCurrentSessionWithMessages() {
    TestRunner.setGroup("Draft Session - Set Current Session With Messages")
    setupDraftTracker()

    let sessionId = UUID()
    draftTracker.setCurrentSession(id: sessionId, messageCount: 10)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "Not draft when has messages")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Correct session ID")

    teardownDraftTracker()
}

func testDraftSession_SetCurrentSessionEmpty() {
    TestRunner.setGroup("Draft Session - Set Current Session Empty")
    setupDraftTracker()

    let sessionId = UUID()
    draftTracker.setCurrentSession(id: sessionId, messageCount: 0)

    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft when no messages")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Correct session ID")

    teardownDraftTracker()
}

func testDraftSession_LoadSessionDiscardsDraft() {
    TestRunner.setGroup("Draft Session - Load Session Discards Draft")
    setupDraftTracker()

    // Create draft
    let draftId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    // Load different session
    let existingId = UUID()
    draftTracker.loadSession(id: existingId, messageCount: 3)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "Draft discarded")
    TestRunner.assertEqual(draftTracker.currentSessionId, existingId, "Loaded session is current")
    TestRunner.assertFalse(draftTracker.currentSessionId == draftId, "Not the draft anymore")

    teardownDraftTracker()
}

func testDraftSession_MultipleNewSessions() {
    TestRunner.setGroup("Draft Session - Multiple New Sessions")
    setupDraftTracker()

    // Start first draft
    let first = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "First draft")

    // Start second draft (replaces first)
    let second = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Still have draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, second, "Second session is current")
    TestRunner.assertFalse(draftTracker.currentSessionId == first, "First session replaced")

    teardownDraftTracker()
}

// MARK: - Edge Case Tests for Draft Session

func testDraftSession_TransitionOnFirstMessage() {
    TestRunner.setGroup("Draft Session - Transition On First Message")
    setupDraftTracker()

    // Create new session (draft)
    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft before message")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages")

    // Add first message - should transition from draft to saved
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No longer draft after first message")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 1, "One message")

    // Adding more messages should not change draft state
    draftTracker.addMessage()
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Still not draft after more messages")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 3, "Three messages")

    teardownDraftTracker()
}

func testDraftSession_LoadSessionDiscardsDraftWithZeroMessages() {
    TestRunner.setGroup("Draft Session - Load Session Discards Draft (Zero Messages)")
    setupDraftTracker()

    // Create draft with no messages
    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "Zero messages in draft")

    // Load an existing session - draft should be discarded
    let existingId = UUID()
    draftTracker.loadSession(id: existingId, messageCount: 5)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "Draft discarded after load")
    TestRunner.assertEqual(draftTracker.currentSessionId, existingId, "Loaded session is current")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 5, "Has existing messages")

    teardownDraftTracker()
}

func testDraftSession_ClearSessionClearsDraft() {
    TestRunner.setGroup("Draft Session - Clear Session Clears Draft")
    setupDraftTracker()

    // Create draft
    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    // Clear session
    draftTracker.clearCurrentSession()

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after clear")
    TestRunner.assertNil(draftTracker.currentSessionId, "No session ID after clear")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages after clear")

    teardownDraftTracker()
}

func testDraftSession_DeleteCurrentSessionClearsDraft() {
    TestRunner.setGroup("Draft Session - Delete Current Session Clears Draft")
    setupDraftTracker()

    // Create draft
    let draftId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    // Simulate deleting current session (same as clear)
    if draftTracker.currentSessionId == draftId {
        draftTracker.clearCurrentSession()
    }

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after delete")
    TestRunner.assertNil(draftTracker.currentSessionId, "No session after delete")

    teardownDraftTracker()
}

func testDraftSession_SetSessionWithZeroMessagesIsDraft() {
    TestRunner.setGroup("Draft Session - Set Session With Zero Messages Is Draft")
    setupDraftTracker()

    let sessionId = UUID()
    draftTracker.setCurrentSession(id: sessionId, messageCount: 0)

    TestRunner.assertTrue(draftTracker.hasDraftSession, "Zero messages = draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Session ID set")

    // Add message - should transition
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No longer draft after message")

    teardownDraftTracker()
}

func testDraftSession_SetSessionWithMessagesNotDraft() {
    TestRunner.setGroup("Draft Session - Set Session With Messages Not Draft")
    setupDraftTracker()

    let sessionId = UUID()
    draftTracker.setCurrentSession(id: sessionId, messageCount: 5)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "Has messages = not draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Session ID set")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 5, "Message count set")

    teardownDraftTracker()
}

func testDraftSession_RapidNewSessionCreation() {
    TestRunner.setGroup("Draft Session - Rapid New Session Creation")
    setupDraftTracker()

    // Rapidly create multiple new sessions
    let id1 = draftTracker.startNewSession()
    let id2 = draftTracker.startNewSession()
    let id3 = draftTracker.startNewSession()

    // Should still have exactly one draft (the last one)
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, id3, "Last session is current")
    TestRunner.assertFalse(draftTracker.currentSessionId == id1, "First replaced")
    TestRunner.assertFalse(draftTracker.currentSessionId == id2, "Second replaced")

    // Add message to finalize
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after message")
    TestRunner.assertEqual(draftTracker.currentSessionId, id3, "Still the third session")

    teardownDraftTracker()
}

func testDraftSession_LoadSessionThenNewSession() {
    TestRunner.setGroup("Draft Session - Load Session Then New Session")
    setupDraftTracker()

    // Load existing session
    let existingId = UUID()
    draftTracker.loadSession(id: existingId, messageCount: 10)
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Not draft after load")

    // Create new session
    let newId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft after new session")
    TestRunner.assertEqual(draftTracker.currentSessionId, newId, "New session is current")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages in new session")

    teardownDraftTracker()
}

func testDraftSession_ResetToInitialState() {
    TestRunner.setGroup("Draft Session - Reset To Initial State")
    setupDraftTracker()

    // Create session and add messages
    _ = draftTracker.startNewSession()
    draftTracker.addMessage()
    draftTracker.addMessage()

    // Reset
    draftTracker.reset()

    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after reset")
    TestRunner.assertNil(draftTracker.currentSessionId, "No session after reset")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 0, "No messages after reset")

    teardownDraftTracker()
}

// MARK: - Combined Draft + Generation State Tests

func testCombined_DraftSessionWithConcurrentGeneration() {
    TestRunner.setGroup("Combined - Draft Session With Concurrent Generation")
    setupDraftTracker()
    setupTracker()

    // Create draft session
    let draftId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new before generation")

    // Start generation on the draft
    tracker.registerActiveGeneration(sessionId: draftId)
    // With concurrent sessions, switching and new sessions are always allowed
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new during generation (concurrent)")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch during generation (concurrent)")

    // Add message during generation - draft becomes real session
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No longer draft after message")

    // Can still switch and create new sessions
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch during generation (concurrent)")

    // End generation
    tracker.unregisterActiveGeneration(sessionId: draftId)
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new after generation")
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch after generation")

    teardownDraftTracker()
    teardownTracker()
}

func testCombined_SwitchFromDraftToSavedSession() {
    TestRunner.setGroup("Combined - Switch From Draft To Saved Session")
    setupDraftTracker()
    setupTracker()

    // Create draft
    _ = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have draft")

    // Simulate switching to saved session
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch when not generating")

    let savedSessionId = UUID()
    draftTracker.loadSession(id: savedSessionId, messageCount: 5)

    TestRunner.assertFalse(draftTracker.hasDraftSession, "Draft discarded")
    TestRunner.assertEqual(draftTracker.currentSessionId, savedSessionId, "Saved session is current")

    teardownDraftTracker()
    teardownTracker()
}

func testCombined_SwitchFromDraftDuringGeneration() {
    TestRunner.setGroup("Combined - Can Switch From Draft During Generation")
    setupDraftTracker()
    setupTracker()

    // Create draft and start generation
    let draftId = draftTracker.startNewSession()
    tracker.registerActiveGeneration(sessionId: draftId)

    // With concurrent sessions, switching is always allowed
    TestRunner.assertTrue(tracker.canSwitchSession(), "Can switch during generation (concurrent)")

    // Only the generating session shows as generating
    let otherSession = UUID()
    TestRunner.assertFalse(tracker.isSessionGenerating(otherSession), "Other session not generating")
    TestRunner.assertTrue(tracker.isSessionGenerating(draftId), "Draft session is generating")

    teardownDraftTracker()
    teardownTracker()
}

func testCombined_NewSessionAllowedDuringGeneration() {
    TestRunner.setGroup("Combined - New Session Allowed During Generation")
    setupDraftTracker()
    setupTracker()

    // Load existing session
    let existingId = UUID()
    draftTracker.loadSession(id: existingId, messageCount: 3)

    // Start generation
    tracker.registerActiveGeneration(sessionId: existingId)

    // With concurrent sessions, new session creation is always allowed
    TestRunner.assertTrue(tracker.canStartNewSession(), "Can start new during generation (concurrent)")

    // Create new session while existing one generates
    let newId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Have new draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, newId, "New session is current")

    // Existing session still generating in background
    TestRunner.assertTrue(tracker.isSessionGenerating(existingId), "Existing session still generating")

    // End generation
    tracker.unregisterActiveGeneration(sessionId: existingId)
    TestRunner.assertFalse(tracker.isSessionGenerating(existingId), "Generation complete")

    teardownDraftTracker()
    teardownTracker()
}

// MARK: - Workflow Tests for Draft Session

func testWorkflow_QuickModeCreatesAndFinalizesSession() {
    TestRunner.setGroup("Workflow - Quick Mode Creates And Finalizes Session")
    setupDraftTracker()

    // User triggers Quick Mode (with selection)
    // 1. If no session exists, one is created (but NOT marked as draft in Quick Mode)
    //    Quick Mode uses ensureSession() which sets hasDraftSession based on message count
    let sessionId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft before user message")

    // 2. User submits instruction - message added
    draftTracker.addMessage()  // User message
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after user message")

    // 3. Assistant responds
    draftTracker.addMessage()  // Assistant message
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Still not draft")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 2, "Two messages")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Same session")

    teardownDraftTracker()
}

func testWorkflow_ChatModeCreatesAndFinalizesSession() {
    TestRunner.setGroup("Workflow - Chat Mode Creates And Finalizes Session")
    setupDraftTracker()

    // User opens Chat Mode (no selection)
    // Session may already exist from SessionManager, but if not, sendChatMessage creates one
    let sessionId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft before chat message")

    // User types and sends message
    draftTracker.addMessage()  // User message
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after user message")

    // Assistant responds
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Still not draft")

    // Multiple follow-up exchanges
    draftTracker.addMessage()  // User
    draftTracker.addMessage()  // Assistant
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 4, "Four messages total")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Same session throughout")

    teardownDraftTracker()
}

func testWorkflow_SummarizeCreatesAndFinalizesSession() {
    TestRunner.setGroup("Workflow - Summarize Creates And Finalizes Session")
    setupDraftTracker()

    // User triggers summarization
    let sessionId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft before summarize")

    // Summarization adds user message (implicit "Summarize this text")
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after summarize message")

    // Summary response added
    draftTracker.addMessage()
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 2, "Two messages")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Same session")

    teardownDraftTracker()
}

func testWorkflow_HideAndShowPreservesDraftState() {
    TestRunner.setGroup("Workflow - Hide And Show Preserves Draft State")
    setupDraftTracker()

    // Create new session (draft)
    let sessionId = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft created")

    // Simulate hide (no changes to state)
    // Draft state should persist

    // Simulate show again
    // Check state is preserved
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft preserved after hide/show")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Session ID preserved")

    // Now add message
    draftTracker.addMessage()
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft after message")

    // Hide and show again
    // Non-draft state should also persist
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Non-draft preserved after hide/show")
    TestRunner.assertEqual(draftTracker.currentSessionId, sessionId, "Session ID still preserved")

    teardownDraftTracker()
}

func testWorkflow_NewSessionButtonWhenDraftExists() {
    TestRunner.setGroup("Workflow - New Session Button When Draft Exists")
    setupDraftTracker()

    // Create first draft
    let first = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "First draft")

    // User clicks "New Session" button - creates new draft, discards old
    let second = draftTracker.startNewSession()
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Still have draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, second, "Second is current")
    TestRunner.assertFalse(draftTracker.currentSessionId == first, "First discarded")

    // Original draft was never saved (had no messages)
    // New draft is active

    teardownDraftTracker()
}

func testWorkflow_RestoreSessionOnAppLaunchNotDraft() {
    TestRunner.setGroup("Workflow - Restore Session On App Launch Not Draft")
    setupDraftTracker()

    // Simulate restoring a session on app launch
    let restoredId = UUID()
    draftTracker.loadSession(id: restoredId, messageCount: 10)

    // Restored sessions are NOT drafts
    TestRunner.assertFalse(draftTracker.hasDraftSession, "Restored session not draft")
    TestRunner.assertEqual(draftTracker.currentSessionId, restoredId, "Restored session is current")
    TestRunner.assertEqual(draftTracker.sessionMessageCount, 10, "Has restored messages")

    teardownDraftTracker()
}

func testWorkflow_SidebarShowsDraftRow() {
    TestRunner.setGroup("Workflow - Sidebar Shows Draft Row")
    setupDraftTracker()

    // No draft, no sessions
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft initially")

    // Create draft
    _ = draftTracker.startNewSession()

    // Sidebar should show draft row
    // (Simulated by checking hasDraftSession)
    TestRunner.assertTrue(draftTracker.hasDraftSession, "Draft exists - sidebar shows draft row")

    // Add message - draft becomes saved
    draftTracker.addMessage()

    // Sidebar should now show regular session row, not draft
    TestRunner.assertFalse(draftTracker.hasDraftSession, "No draft - sidebar shows regular row")

    teardownDraftTracker()
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

        // Session Generating State Tests
        testSessionGenerating_NoGeneration()
        testSessionGenerating_DuringGeneration()
        testSessionGenerating_AfterGenerationComplete()

        // Session Switching Tests
        testSessionSwitching_AllowedDuringGeneration()
        testSessionSwitching_AllowedAfterCancellation()
        testSessionSwitching_AllowedAfterCompletion()

        // New Session Tests
        testNewSession_AllowedDuringGeneration()
        testNewSession_AllowedAfterGeneration()

        // Edge Case Tests
        testEdgeCase_RapidRegisterUnregister()
        testEdgeCase_UnregisterWithoutRegister()
        testEdgeCase_DoubleUnregister()
        testEdgeCase_RegisterMultipleSessionsConcurrently()

        // Workflow Tests
        testWorkflow_QuickModeGeneration()
        testWorkflow_ChatModeGenerationWithCancel()
        testWorkflow_MultipleSessionsGenerating()

        // Draft Session Tests (Basic)
        testDraftSession_InitialState()
        testDraftSession_AfterStartNewSession()
        testDraftSession_AfterFirstMessage()
        testDraftSession_AfterLoadSession()
        testDraftSession_AfterClearSession()
        testDraftSession_SetCurrentSessionWithMessages()
        testDraftSession_SetCurrentSessionEmpty()
        testDraftSession_LoadSessionDiscardsDraft()
        testDraftSession_MultipleNewSessions()

        // Draft Session Edge Cases
        testDraftSession_TransitionOnFirstMessage()
        testDraftSession_LoadSessionDiscardsDraftWithZeroMessages()
        testDraftSession_ClearSessionClearsDraft()
        testDraftSession_DeleteCurrentSessionClearsDraft()
        testDraftSession_SetSessionWithZeroMessagesIsDraft()
        testDraftSession_SetSessionWithMessagesNotDraft()
        testDraftSession_RapidNewSessionCreation()
        testDraftSession_LoadSessionThenNewSession()
        testDraftSession_ResetToInitialState()

        // Combined Draft + Generation State Tests
        testCombined_DraftSessionWithConcurrentGeneration()
        testCombined_SwitchFromDraftToSavedSession()
        testCombined_SwitchFromDraftDuringGeneration()
        testCombined_NewSessionAllowedDuringGeneration()

        // Workflow Tests for Draft Session
        testWorkflow_QuickModeCreatesAndFinalizesSession()
        testWorkflow_ChatModeCreatesAndFinalizesSession()
        testWorkflow_SummarizeCreatesAndFinalizesSession()
        testWorkflow_HideAndShowPreservesDraftState()
        testWorkflow_NewSessionButtonWhenDraftExists()
        testWorkflow_RestoreSessionOnAppLaunchNotDraft()
        testWorkflow_SidebarShowsDraftRow()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
