// MARK: - ChatConversation Unit Tests
// Standalone test runner for ChatConversation retry functionality
// Tests the removeMessageAndFollowing method and related conversation management

import Foundation

/// Simple test framework for running without XCTest
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

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
            let message = "Expected nil but got '\(value!)'"
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

// MARK: - ChatRole and ChatMessage (inline for standalone test)

enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

// MARK: - ChatConversation (inline for standalone test)

final class ChatConversation {
    var messages: [ChatMessage] = []
    let maxMessages: Int
    /// Number of messages covered by the summary (0 means no summary)
    var summaryCoversCount: Int = 0

    init(maxMessages: Int = 20) {
        self.maxMessages = maxMessages
    }

    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }

    func addUserMessage(_ content: String) {
        addMessage(.user(content))
    }

    func addAssistantMessage(_ content: String) {
        addMessage(.assistant(content))
    }

    @discardableResult
    func removeMessageAndFollowing(id: UUID) -> ChatMessage? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        var precedingUserMessage: ChatMessage?
        if index > 0 {
            for i in stride(from: index - 1, through: 0, by: -1) {
                if messages[i].role == .user {
                    precedingUserMessage = messages[i]
                    break
                }
            }
        }

        messages.removeSubrange(index...)
        return precedingUserMessage
    }

    /// Check if a message at the given ID can be retried
    /// Messages within the summarized portion cannot be retried to avoid inconsistent state
    func canRetryMessage(id: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return false
        }
        // Can only retry messages AFTER the summarized portion
        return index >= summaryCoversCount
    }

    var lastAssistantMessage: ChatMessage? {
        messages.last { $0.role == .assistant }
    }

    var isEmpty: Bool { messages.isEmpty }
    var count: Int { messages.count }
}

// MARK: - Test Cases

func testRemoveMessageAndFollowing_BasicRemoval() {
    print("")
    print("📦 Remove Message And Following - Basic Tests")
    print("----------------------------------------")

    // Setup: user -> assistant -> user -> assistant
    let conv = ChatConversation()
    conv.addUserMessage("First question")
    conv.addAssistantMessage("First answer")
    conv.addUserMessage("Second question")
    conv.addAssistantMessage("Second answer")

    let secondAssistantId = conv.messages[3].id
    TestRunner.assertEqual(conv.count, 4, "Initial message count")

    // Remove second assistant message
    let precedingUser = conv.removeMessageAndFollowing(id: secondAssistantId)

    TestRunner.assertEqual(conv.count, 3, "Count after removal")
    TestRunner.assertNotNil(precedingUser, "Preceding user message found")
    TestRunner.assertEqual(precedingUser?.content, "Second question", "Correct preceding user message")
}

func testRemoveMessageAndFollowing_RemovesAllFollowing() {
    print("")
    print("📦 Remove Message And Following - Remove All Following")
    print("----------------------------------------")

    // Setup: user -> assistant -> user -> assistant -> user -> assistant
    let conv = ChatConversation()
    conv.addUserMessage("Q1")
    conv.addAssistantMessage("A1")
    conv.addUserMessage("Q2")
    conv.addAssistantMessage("A2")
    conv.addUserMessage("Q3")
    conv.addAssistantMessage("A3")

    let secondAssistantId = conv.messages[3].id // A2
    TestRunner.assertEqual(conv.count, 6, "Initial message count")

    // Remove A2 - should also remove Q3 and A3
    let _ = conv.removeMessageAndFollowing(id: secondAssistantId)

    TestRunner.assertEqual(conv.count, 3, "Count after removal (removed A2, Q3, A3)")
    TestRunner.assertEqual(conv.messages[0].content, "Q1", "Q1 preserved")
    TestRunner.assertEqual(conv.messages[1].content, "A1", "A1 preserved")
    TestRunner.assertEqual(conv.messages[2].content, "Q2", "Q2 preserved")
}

func testRemoveMessageAndFollowing_FirstAssistantMessage() {
    print("")
    print("📦 Remove Message And Following - First Assistant")
    print("----------------------------------------")

    // Setup: user -> assistant
    let conv = ChatConversation()
    conv.addUserMessage("Question")
    conv.addAssistantMessage("Answer")

    let assistantId = conv.messages[1].id
    let precedingUser = conv.removeMessageAndFollowing(id: assistantId)

    TestRunner.assertEqual(conv.count, 1, "Only user message remains")
    TestRunner.assertEqual(precedingUser?.content, "Question", "Preceding user found")
}

func testRemoveMessageAndFollowing_NonExistentId() {
    print("")
    print("📦 Remove Message And Following - Non-Existent ID")
    print("----------------------------------------")

    let conv = ChatConversation()
    conv.addUserMessage("Question")
    conv.addAssistantMessage("Answer")

    let fakeId = UUID()
    let result = conv.removeMessageAndFollowing(id: fakeId)

    TestRunner.assertNil(result, "Returns nil for non-existent ID")
    TestRunner.assertEqual(conv.count, 2, "Messages unchanged")
}

func testRemoveMessageAndFollowing_NoPrecedingUser() {
    print("")
    print("📦 Remove Message And Following - No Preceding User")
    print("----------------------------------------")

    // Setup: assistant only (edge case)
    let conv = ChatConversation()
    conv.addAssistantMessage("Answer without question")

    let assistantId = conv.messages[0].id
    let precedingUser = conv.removeMessageAndFollowing(id: assistantId)

    TestRunner.assertNil(precedingUser, "No preceding user returns nil")
    TestRunner.assertEqual(conv.count, 0, "Message removed")
}

func testRemoveMessageAndFollowing_SystemMessageSkipped() {
    print("")
    print("📦 Remove Message And Following - System Message Skipped")
    print("----------------------------------------")

    // Setup: system -> user -> assistant
    let conv = ChatConversation()
    conv.addMessage(.system("You are helpful"))
    conv.addUserMessage("Question")
    conv.addAssistantMessage("Answer")

    let assistantId = conv.messages[2].id
    let precedingUser = conv.removeMessageAndFollowing(id: assistantId)

    TestRunner.assertEqual(precedingUser?.content, "Question", "User message found (skipped system)")
    TestRunner.assertEqual(precedingUser?.role, .user, "Role is user")
    TestRunner.assertEqual(conv.count, 2, "System and user remain")
}

func testRemoveMessageAndFollowing_MultipleAssistantsBetweenUsers() {
    print("")
    print("📦 Remove Message And Following - Multiple Assistants")
    print("----------------------------------------")

    // Setup: user -> assistant -> assistant -> user -> assistant (edge case - shouldn't happen normally)
    let conv = ChatConversation()
    conv.addUserMessage("Q1")
    conv.addAssistantMessage("A1 part 1")
    conv.addAssistantMessage("A1 part 2")
    conv.addUserMessage("Q2")
    conv.addAssistantMessage("A2")

    let secondPartId = conv.messages[2].id // A1 part 2
    let precedingUser = conv.removeMessageAndFollowing(id: secondPartId)

    TestRunner.assertEqual(precedingUser?.content, "Q1", "Found original user question")
    TestRunner.assertEqual(conv.count, 2, "Only Q1 and A1 part 1 remain")
}

func testRemoveMessageAndFollowing_RetryWorkflow() {
    print("")
    print("📦 Remove Message And Following - Full Retry Workflow")
    print("----------------------------------------")

    // Simulate a full retry workflow
    let conv = ChatConversation()
    conv.addUserMessage("Write a poem")
    conv.addAssistantMessage("Roses are red...")

    // User wants to retry
    let assistantId = conv.messages[1].id
    let userMessage = conv.removeMessageAndFollowing(id: assistantId)

    TestRunner.assertNotNil(userMessage, "Got user message for retry")
    TestRunner.assertEqual(conv.count, 1, "Only original user message")

    // Re-add user message and new response (simulating retry)
    conv.addUserMessage(userMessage!.content)
    conv.addAssistantMessage("Violets are blue...")

    TestRunner.assertEqual(conv.count, 3, "New conversation flow established")
    TestRunner.assertEqual(conv.messages[2].content, "Violets are blue...", "New response added")
}

// MARK: - canRetryMessage Tests

func testCanRetryMessage_WithinSummarizedPortion_ReturnsFalse() {
    print("")
    print("📦 canRetryMessage - Within Summarized Portion")
    print("----------------------------------------")

    // Setup: 10 messages, 6 summarized (indices 0-5), 4 recent (indices 6-9)
    let conv = ChatConversation()
    for i in 0..<5 {
        conv.addUserMessage("Q\(i)")
        conv.addAssistantMessage("A\(i)")
    }
    conv.summaryCoversCount = 6  // First 6 messages are summarized

    // Message at index 1 (A0) is within summarized portion
    let summarizedMessageId = conv.messages[1].id
    TestRunner.assertTrue(!conv.canRetryMessage(id: summarizedMessageId), "Cannot retry message at index 1 (within summarized)")

    // Message at index 5 (A2) is within summarized portion
    let boundaryMessageId = conv.messages[5].id
    TestRunner.assertTrue(!conv.canRetryMessage(id: boundaryMessageId), "Cannot retry message at index 5 (within summarized)")
}

func testCanRetryMessage_OutsideSummarizedPortion_ReturnsTrue() {
    print("")
    print("📦 canRetryMessage - Outside Summarized Portion")
    print("----------------------------------------")

    // Setup: 10 messages, 6 summarized (indices 0-5), 4 recent (indices 6-9)
    let conv = ChatConversation()
    for i in 0..<5 {
        conv.addUserMessage("Q\(i)")
        conv.addAssistantMessage("A\(i)")
    }
    conv.summaryCoversCount = 6  // First 6 messages are summarized

    // Message at index 7 (A3) is outside summarized portion
    let recentMessageId = conv.messages[7].id
    TestRunner.assertTrue(conv.canRetryMessage(id: recentMessageId), "Can retry message at index 7 (recent)")

    // Message at index 9 (A4) is outside summarized portion
    let lastMessageId = conv.messages[9].id
    TestRunner.assertTrue(conv.canRetryMessage(id: lastMessageId), "Can retry message at index 9 (most recent)")
}

func testCanRetryMessage_AtBoundary_ReturnsTrue() {
    print("")
    print("📦 canRetryMessage - At Boundary")
    print("----------------------------------------")

    // Setup: 10 messages, 6 summarized
    let conv = ChatConversation()
    for i in 0..<5 {
        conv.addUserMessage("Q\(i)")
        conv.addAssistantMessage("A\(i)")
    }
    conv.summaryCoversCount = 6

    // Message at index 6 (Q3) is exactly at boundary - should be retryable
    let boundaryMessageId = conv.messages[6].id
    TestRunner.assertTrue(conv.canRetryMessage(id: boundaryMessageId), "Can retry message at exact boundary (index 6)")
}

func testCanRetryMessage_NoSummary_AllMessagesRetryable() {
    print("")
    print("📦 canRetryMessage - No Summary")
    print("----------------------------------------")

    // Setup: 6 messages, no summary (summaryCoversCount = 0)
    let conv = ChatConversation()
    for i in 0..<3 {
        conv.addUserMessage("Q\(i)")
        conv.addAssistantMessage("A\(i)")
    }
    // summaryCoversCount defaults to 0

    // All messages should be retryable
    TestRunner.assertTrue(conv.canRetryMessage(id: conv.messages[0].id), "Can retry first message (no summary)")
    TestRunner.assertTrue(conv.canRetryMessage(id: conv.messages[1].id), "Can retry second message (no summary)")
    TestRunner.assertTrue(conv.canRetryMessage(id: conv.messages[5].id), "Can retry last message (no summary)")
}

func testCanRetryMessage_NonExistentId_ReturnsFalse() {
    print("")
    print("📦 canRetryMessage - Non-Existent ID")
    print("----------------------------------------")

    let conv = ChatConversation()
    conv.addUserMessage("Q1")
    conv.addAssistantMessage("A1")

    let fakeId = UUID()
    TestRunner.assertTrue(!conv.canRetryMessage(id: fakeId), "Cannot retry non-existent message")
}

// MARK: - Main Entry Point

@main
struct ChatConversationTestRunner {
    static func main() {
        print("")
        print("🧪 ChatConversation Unit Tests")
        print("==================================================")

        // removeMessageAndFollowing tests
        testRemoveMessageAndFollowing_BasicRemoval()
        testRemoveMessageAndFollowing_RemovesAllFollowing()
        testRemoveMessageAndFollowing_FirstAssistantMessage()
        testRemoveMessageAndFollowing_NonExistentId()
        testRemoveMessageAndFollowing_NoPrecedingUser()
        testRemoveMessageAndFollowing_SystemMessageSkipped()
        testRemoveMessageAndFollowing_MultipleAssistantsBetweenUsers()
        testRemoveMessageAndFollowing_RetryWorkflow()

        // canRetryMessage tests
        testCanRetryMessage_WithinSummarizedPortion_ReturnsFalse()
        testCanRetryMessage_OutsideSummarizedPortion_ReturnsTrue()
        testCanRetryMessage_AtBoundary_ReturnsTrue()
        testCanRetryMessage_NoSummary_AllMessagesRetryable()
        testCanRetryMessage_NonExistentId_ReturnsFalse()

        TestRunner.printSummary()

        // Exit with appropriate code
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
