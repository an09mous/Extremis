// MARK: - Tool Fallback Tests
// Tests for the tool fallback path: empty message filtering and fallback message construction
// Covers the fix for hallucination in weaker models (e.g., DeepSeek) when tools are unavailable

import Foundation

// MARK: - Test Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentSuite = ""

    static func suite(_ name: String) {
        currentSuite = name
        print("\n📦 \(name)")
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
        if !condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected false but got true"))
            print("  ✗ \(testName): Expected false but got true")
        }
    }

    static func printSummary() {
        print("\n==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Inline Types (minimal copies for standalone test)

enum ChatRole: String {
    case user
    case assistant
    case system
}

struct ChatMessage {
    let role: ChatRole
    let content: String

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

// MARK: - Logic Under Test (extracted from ToolEnabledChatService)

/// Mirrors the empty assistant message filter used in fallback paths
func filterEmptyAssistantMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
    messages.filter { msg in
        !(msg.role == .assistant && msg.content.isEmpty)
    }
}

/// Mirrors buildToolFallbackMessage from ToolEnabledChatService
func buildToolFallbackMessage(requestedNames: [String]) -> String {
    return "You attempted to call tools that do not exist: \(requestedNames.joined(separator: ", ")). " +
        "These names do not match any available tool. " +
        "Do NOT attempt to call tools again. " +
        "Respond to the user's request directly using your own knowledge."
}

// MARK: - Empty Assistant Message Filter Tests

func testFilterEmptyAssistantMessages() {
    TestRunner.suite("Empty Assistant Message Filter")

    // Basic case: empty assistant message is removed
    let messages1 = [
        ChatMessage.user("hello"),
        ChatMessage.assistant(""),
        ChatMessage.system("tools not available")
    ]
    let filtered1 = filterEmptyAssistantMessages(messages1)
    TestRunner.assertEqual(filtered1.count, 2, "Removes empty assistant message")
    TestRunner.assertEqual(filtered1[0].role, .user, "User message preserved")
    TestRunner.assertEqual(filtered1[1].role, .system, "System message preserved")

    // Non-empty assistant message is kept
    let messages2 = [
        ChatMessage.user("hello"),
        ChatMessage.assistant("I can help with that"),
        ChatMessage.system("tools not available")
    ]
    let filtered2 = filterEmptyAssistantMessages(messages2)
    TestRunner.assertEqual(filtered2.count, 3, "Non-empty assistant message kept")
    TestRunner.assertEqual(filtered2[1].content, "I can help with that", "Assistant content preserved")

    // Multiple empty assistant messages are all removed
    let messages3 = [
        ChatMessage.user("question 1"),
        ChatMessage.assistant(""),
        ChatMessage.user("question 2"),
        ChatMessage.assistant(""),
        ChatMessage.system("correction")
    ]
    let filtered3 = filterEmptyAssistantMessages(messages3)
    TestRunner.assertEqual(filtered3.count, 3, "All empty assistant messages removed")
    TestRunner.assertEqual(filtered3[0].role, .user, "First user message preserved")
    TestRunner.assertEqual(filtered3[1].role, .user, "Second user message preserved")
    TestRunner.assertEqual(filtered3[2].role, .system, "System message preserved")

    // No assistant messages at all — nothing changes
    let messages4 = [
        ChatMessage.user("hello"),
        ChatMessage.system("system prompt")
    ]
    let filtered4 = filterEmptyAssistantMessages(messages4)
    TestRunner.assertEqual(filtered4.count, 2, "No assistant messages — unchanged")

    // Empty user/system messages are NOT filtered
    let messages5 = [
        ChatMessage.user(""),
        ChatMessage.system(""),
        ChatMessage.assistant("")
    ]
    let filtered5 = filterEmptyAssistantMessages(messages5)
    TestRunner.assertEqual(filtered5.count, 2, "Only empty assistant removed, not user/system")
    TestRunner.assertEqual(filtered5[0].role, .user, "Empty user message kept")
    TestRunner.assertEqual(filtered5[1].role, .system, "Empty system message kept")

    // Whitespace-only assistant message is NOT filtered (only truly empty)
    let messages6 = [
        ChatMessage.user("hello"),
        ChatMessage.assistant(" ")
    ]
    let filtered6 = filterEmptyAssistantMessages(messages6)
    TestRunner.assertEqual(filtered6.count, 2, "Whitespace assistant message kept")

    // Empty array stays empty
    let filtered7 = filterEmptyAssistantMessages([])
    TestRunner.assertEqual(filtered7.count, 0, "Empty input returns empty output")

    // Mix of empty and non-empty assistant messages
    let messages8 = [
        ChatMessage.user("q1"),
        ChatMessage.assistant("answer 1"),
        ChatMessage.user("q2"),
        ChatMessage.assistant(""),
        ChatMessage.user("q3"),
        ChatMessage.assistant("answer 3")
    ]
    let filtered8 = filterEmptyAssistantMessages(messages8)
    TestRunner.assertEqual(filtered8.count, 5, "Only the empty assistant removed from mixed list")
    TestRunner.assertEqual(filtered8[2].role, .user, "User q2 at correct position")
    TestRunner.assertEqual(filtered8[3].role, .user, "User q3 follows directly after q2")
    TestRunner.assertEqual(filtered8[4].content, "answer 3", "Last assistant preserved")
}

// MARK: - Fallback Message Construction Tests

func testBuildToolFallbackMessage() {
    TestRunner.suite("Tool Fallback Message Construction")

    // Single hallucinated tool name
    let msg1 = buildToolFallbackMessage(requestedNames: ["github_list_pullrequests"])
    TestRunner.assertTrue(
        msg1.contains("github_list_pullrequests"),
        "Message includes hallucinated tool name"
    )
    TestRunner.assertTrue(
        msg1.contains("do not exist"),
        "Message says tools don't exist"
    )
    TestRunner.assertTrue(
        msg1.contains("Do NOT attempt to call tools again"),
        "Message includes firm instruction not to retry"
    )
    TestRunner.assertTrue(
        msg1.contains("using your own knowledge"),
        "Message directs model to use own knowledge"
    )

    // Multiple hallucinated tool names
    let msg2 = buildToolFallbackMessage(requestedNames: ["search_web", "read_file", "execute_code"])
    TestRunner.assertTrue(
        msg2.contains("search_web"),
        "Contains first tool name"
    )
    TestRunner.assertTrue(
        msg2.contains("read_file"),
        "Contains second tool name"
    )
    TestRunner.assertTrue(
        msg2.contains("execute_code"),
        "Contains third tool name"
    )
    TestRunner.assertTrue(
        msg2.contains("search_web, read_file, execute_code"),
        "Tool names are comma-separated"
    )

    // Single tool name
    let msg3 = buildToolFallbackMessage(requestedNames: ["only_tool"])
    TestRunner.assertFalse(
        msg3.contains(","),
        "Single tool name has no comma separator"
    )

    // Empty tool names (edge case — shouldn't happen but shouldn't crash)
    let msg4 = buildToolFallbackMessage(requestedNames: [])
    TestRunner.assertTrue(
        msg4.contains("do not exist"),
        "Empty names still produces valid message"
    )
}

// MARK: - Simulated Fallback Flow Tests

func testFallbackFlowSimulation() {
    TestRunner.suite("Fallback Flow Simulation")

    // Simulate the exact scenario from the DeepSeek bug:
    // User sends first message, conversation has an empty assistant from prior turn
    let conversationHistory = [
        ChatMessage.user("review the latest extremis PR"),
        ChatMessage.assistant("")  // stale empty message from prior failed generation
    ]

    // Step 1: Filter empty assistant messages
    let filtered = filterEmptyAssistantMessages(conversationHistory)

    // Step 2: Append fallback system message
    let fallbackMsg = buildToolFallbackMessage(requestedNames: ["github_list_pullrequests"])
    var fallbackMessages = filtered
    fallbackMessages.append(ChatMessage.system(fallbackMsg))

    // Verify final message array is clean
    TestRunner.assertEqual(fallbackMessages.count, 2, "Final messages: user + system (no empty assistant)")
    TestRunner.assertEqual(fallbackMessages[0].role, .user, "First message is user")
    TestRunner.assertEqual(fallbackMessages[1].role, .system, "Second message is system fallback")
    TestRunner.assertTrue(
        fallbackMessages[1].content.contains("do not exist"),
        "System message explains hallucination"
    )

    // Simulate multi-turn conversation with a valid prior assistant response
    let multiTurnHistory = [
        ChatMessage.user("What can you do?"),
        ChatMessage.assistant("I can help with many tasks including reviewing code."),
        ChatMessage.user("review the latest extremis PR")
    ]
    let filteredMulti = filterEmptyAssistantMessages(multiTurnHistory)
    TestRunner.assertEqual(filteredMulti.count, 3, "Multi-turn: all messages preserved (no empty assistant)")
    TestRunner.assertEqual(filteredMulti[1].content, "I can help with many tasks including reviewing code.", "Prior assistant response preserved")

    // Simulate conversation where prior turn had empty assistant AND a valid one before that
    let mixedHistory = [
        ChatMessage.user("Hello"),
        ChatMessage.assistant("Hi! How can I help?"),
        ChatMessage.user("Search for bugs"),
        ChatMessage.assistant(""),  // prior failed tool attempt
        ChatMessage.user("Try again without tools")
    ]
    let filteredMixed = filterEmptyAssistantMessages(mixedHistory)
    TestRunner.assertEqual(filteredMixed.count, 4, "Mixed: empty assistant removed, rest preserved")
    TestRunner.assertEqual(filteredMixed[0].role, .user, "First user preserved")
    TestRunner.assertEqual(filteredMixed[1].role, .assistant, "Valid assistant preserved")
    TestRunner.assertEqual(filteredMixed[2].role, .user, "Second user preserved")
    TestRunner.assertEqual(filteredMixed[3].role, .user, "Third user preserved (consecutive users OK)")
}

// MARK: - Entry Point

@main
struct ToolFallbackTests {
    static func main() {
        testFilterEmptyAssistantMessages()
        testBuildToolFallbackMessage()
        testFallbackFlowSimulation()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
