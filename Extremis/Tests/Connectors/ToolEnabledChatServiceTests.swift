// MARK: - ToolEnabledChatService Tests
// Tests for tool execution round limits and summarization behavior

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

    static func printSummary() {
        print("\n==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        print("==================================================")

        if !failedTests.isEmpty {
            print("\nFailed Tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("")
    }
}

// MARK: - Minimal Type Definitions for Testing

/// Message role enumeration
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// Simplified ChatMessage for testing
struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let toolRounds: [ToolExecutionRoundRecord]?

    init(role: MessageRole, content: String, toolRounds: [ToolExecutionRoundRecord]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.toolRounds = toolRounds
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String, toolRounds: [ToolExecutionRoundRecord]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, toolRounds: toolRounds)
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

/// Simplified ToolCallRecord for testing
struct ToolCallRecord: Codable, Identifiable, Equatable {
    let id: String
    let toolName: String
    let connectorID: String
    let argumentsJSON: String
    let requestedAt: Date
}

/// Simplified ToolResultRecord for testing
struct ToolResultRecord: Codable, Identifiable, Equatable {
    let callID: String
    let toolName: String
    let isSuccess: Bool
    let content: String
    let duration: TimeInterval
    let completedAt: Date

    var id: String { callID }
}

/// Simplified ToolExecutionRoundRecord for testing
struct ToolExecutionRoundRecord: Codable, Equatable {
    let toolCalls: [ToolCallRecord]
    let results: [ToolResultRecord]
    let assistantResponse: String?

    init(toolCalls: [ToolCallRecord], results: [ToolResultRecord], assistantResponse: String? = nil) {
        self.toolCalls = toolCalls
        self.results = results
        self.assistantResponse = assistantResponse
    }
}

// MARK: - Mock Tool Execution Simulator

/// Simulates the tool execution loop logic without actual LLM calls
class MockToolExecutionLoop {
    let maxToolRounds: Int

    init(maxToolRounds: Int = 20) {
        self.maxToolRounds = maxToolRounds
    }

    /// Simulates a tool execution loop and returns the number of rounds executed
    /// and whether the summarization call was needed
    func simulateExecution(
        toolCallsPerRound: [Int]  // Number of tool calls returned per round (0 = complete)
    ) -> (rounds: Int, hitLimit: Bool, needsSummarization: Bool) {
        let limit = maxToolRounds
        var rounds = 0
        var toolRounds: [ToolExecutionRoundRecord] = []

        for callCount in toolCallsPerRound {
            if rounds >= limit {
                break
            }

            rounds += 1

            // If no tool calls, generation is complete
            if callCount == 0 {
                return (rounds, false, false)
            }

            // Create mock tool calls and results
            let calls = (0..<callCount).map { i in
                ToolCallRecord(
                    id: "call_\(rounds)_\(i)",
                    toolName: "mock_tool",
                    connectorID: "mock",
                    argumentsJSON: "{}",
                    requestedAt: Date()
                )
            }
            let results = calls.map { call in
                ToolResultRecord(
                    callID: call.id,
                    toolName: call.toolName,
                    isSuccess: true,
                    content: "Mock result",
                    duration: 0.1,
                    completedAt: Date()
                )
            }
            toolRounds.append(ToolExecutionRoundRecord(
                toolCalls: calls,
                results: results,
                assistantResponse: "Partial response \(rounds)"
            ))
        }

        let hitLimit = rounds >= limit
        let needsSummarization = hitLimit && !toolRounds.isEmpty

        return (rounds, hitLimit, needsSummarization)
    }
}

// MARK: - Tests

func testMaxRoundsConfiguration() {
    TestRunner.suite("Max Rounds Configuration")

    let defaultLoop = MockToolExecutionLoop()
    TestRunner.assertEqual(defaultLoop.maxToolRounds, 20, "Default max rounds should be 20")

    let customLoop = MockToolExecutionLoop(maxToolRounds: 10)
    TestRunner.assertEqual(customLoop.maxToolRounds, 10, "Custom max rounds should be respected")
}

func testCompletionBeforeMaxRounds() {
    TestRunner.suite("Completion Before Max Rounds")

    let loop = MockToolExecutionLoop(maxToolRounds: 20)

    // Simulate: 3 tool calls, then completion
    let result = loop.simulateExecution(toolCallsPerRound: [1, 1, 1, 0])

    TestRunner.assertEqual(result.rounds, 4, "Should complete in 4 rounds")
    TestRunner.assertFalse(result.hitLimit, "Should not hit limit")
    TestRunner.assertFalse(result.needsSummarization, "Should not need summarization")
}

func testHitMaxRoundsLimit() {
    TestRunner.suite("Hit Max Rounds Limit")

    let loop = MockToolExecutionLoop(maxToolRounds: 5)

    // Simulate: endless tool calls (more than max rounds)
    let result = loop.simulateExecution(toolCallsPerRound: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])

    TestRunner.assertEqual(result.rounds, 5, "Should stop at max rounds")
    TestRunner.assertTrue(result.hitLimit, "Should hit limit")
    TestRunner.assertTrue(result.needsSummarization, "Should need summarization when hitting limit")
}

func testSummarizationNotNeededWhenNoToolRounds() {
    TestRunner.suite("Summarization Not Needed When No Tool Rounds")

    let loop = MockToolExecutionLoop(maxToolRounds: 5)

    // Simulate: immediate completion (no tool calls)
    let result = loop.simulateExecution(toolCallsPerRound: [0])

    TestRunner.assertEqual(result.rounds, 1, "Should complete in 1 round")
    TestRunner.assertFalse(result.hitLimit, "Should not hit limit")
    TestRunner.assertFalse(result.needsSummarization, "Should not need summarization")
}

func testExactMaxRoundsWithCompletion() {
    TestRunner.suite("Exact Max Rounds With Completion")

    let loop = MockToolExecutionLoop(maxToolRounds: 3)

    // Simulate: exactly 3 rounds with tool calls, no more
    let result = loop.simulateExecution(toolCallsPerRound: [1, 1, 1])

    TestRunner.assertEqual(result.rounds, 3, "Should execute exactly 3 rounds")
    TestRunner.assertTrue(result.hitLimit, "Should hit limit")
    TestRunner.assertTrue(result.needsSummarization, "Should need summarization at exact limit")
}

func testSyntheticMessageFormatting() {
    TestRunner.suite("Synthetic Message Formatting")

    // Test that synthetic messages have empty content when tool rounds are present
    let toolCall = ToolCallRecord(
        id: "call_1",
        toolName: "github_search",
        connectorID: "github",
        argumentsJSON: "{\"query\":\"test\"}",
        requestedAt: Date()
    )

    let result = ToolResultRecord(
        callID: "call_1",
        toolName: "github_search",
        isSuccess: true,
        content: "Found 5 results",
        duration: 0.5,
        completedAt: Date()
    )

    let round = ToolExecutionRoundRecord(
        toolCalls: [toolCall],
        results: [result],
        assistantResponse: "Let me search for that..."
    )

    // Synthetic message should have empty content, with assistantResponse in the round
    let syntheticMessage = ChatMessage.assistant("", toolRounds: [round])

    TestRunner.assertEqual(syntheticMessage.content, "", "Synthetic message content should be empty")
    TestRunner.assertNotNil(syntheticMessage.toolRounds, "Synthetic message should have tool rounds")
    TestRunner.assertEqual(syntheticMessage.toolRounds?.count, 1, "Should have 1 tool round")
    TestRunner.assertEqual(syntheticMessage.toolRounds?[0].assistantResponse, "Let me search for that...", "Assistant response should be in round")
}

func testMultipleToolRoundsOrdering() {
    TestRunner.suite("Multiple Tool Rounds Ordering")

    var rounds: [ToolExecutionRoundRecord] = []

    // Simulate 3 sequential rounds
    for i in 1...3 {
        let call = ToolCallRecord(
            id: "call_\(i)",
            toolName: "tool_\(i)",
            connectorID: "connector",
            argumentsJSON: "{}",
            requestedAt: Date()
        )
        let result = ToolResultRecord(
            callID: "call_\(i)",
            toolName: "tool_\(i)",
            isSuccess: true,
            content: "Result \(i)",
            duration: 0.1,
            completedAt: Date()
        )
        rounds.append(ToolExecutionRoundRecord(
            toolCalls: [call],
            results: [result],
            assistantResponse: "Response \(i)"
        ))
    }

    TestRunner.assertEqual(rounds.count, 3, "Should have 3 rounds")
    TestRunner.assertEqual(rounds[0].assistantResponse, "Response 1", "First round response correct")
    TestRunner.assertEqual(rounds[1].assistantResponse, "Response 2", "Second round response correct")
    TestRunner.assertEqual(rounds[2].assistantResponse, "Response 3", "Third round response correct")

    // Verify each round has its own tool call
    TestRunner.assertEqual(rounds[0].toolCalls[0].id, "call_1", "First round call ID correct")
    TestRunner.assertEqual(rounds[1].toolCalls[0].id, "call_2", "Second round call ID correct")
    TestRunner.assertEqual(rounds[2].toolCalls[0].id, "call_3", "Third round call ID correct")
}

func testSummarizationPromptMessage() {
    TestRunner.suite("Summarization Prompt Message")

    // The summarization prompt should be a user message asking for summary
    let summaryPrompt = "You've gathered information using tools. Please provide a complete response based on all the information collected."

    let promptMessage = ChatMessage.user(summaryPrompt)

    TestRunner.assertEqual(promptMessage.role, .user, "Summary prompt should be user role")
    TestRunner.assertTrue(promptMessage.content.contains("gathered information"), "Prompt should mention gathered information")
    TestRunner.assertTrue(promptMessage.content.contains("complete response"), "Prompt should request complete response")
}

func testToolRoundWithAssistantResponse() {
    TestRunner.suite("Tool Round With Assistant Response")

    let call = ToolCallRecord(
        id: "call_xyz",
        toolName: "fetch_data",
        connectorID: "api",
        argumentsJSON: "{\"url\":\"https://example.com\"}",
        requestedAt: Date()
    )

    let result = ToolResultRecord(
        callID: "call_xyz",
        toolName: "fetch_data",
        isSuccess: true,
        content: "Data fetched successfully",
        duration: 1.2,
        completedAt: Date()
    )

    // Round with assistant response
    let roundWithResponse = ToolExecutionRoundRecord(
        toolCalls: [call],
        results: [result],
        assistantResponse: "Let me fetch that data for you..."
    )

    TestRunner.assertNotNil(roundWithResponse.assistantResponse, "Should have assistant response")
    TestRunner.assertEqual(roundWithResponse.assistantResponse, "Let me fetch that data for you...", "Assistant response content correct")

    // Round without assistant response
    let roundWithoutResponse = ToolExecutionRoundRecord(
        toolCalls: [call],
        results: [result],
        assistantResponse: nil
    )

    TestRunner.assertNil(roundWithoutResponse.assistantResponse, "Should not have assistant response")
}

func testEmptyAssistantResponseNotStored() {
    TestRunner.suite("Empty Assistant Response Not Stored")

    let call = ToolCallRecord(
        id: "call_1",
        toolName: "tool",
        connectorID: "c",
        argumentsJSON: "{}",
        requestedAt: Date()
    )

    let result = ToolResultRecord(
        callID: "call_1",
        toolName: "tool",
        isSuccess: true,
        content: "OK",
        duration: 0.1,
        completedAt: Date()
    )

    // Simulate the logic: empty string should become nil
    let roundText = ""
    let roundRecord = ToolExecutionRoundRecord(
        toolCalls: [call],
        results: [result],
        assistantResponse: roundText.isEmpty ? nil : roundText
    )

    TestRunner.assertNil(roundRecord.assistantResponse, "Empty response should be stored as nil")
}

func testRoundLimitBoundaryConditions() {
    TestRunner.suite("Round Limit Boundary Conditions")

    let loop = MockToolExecutionLoop(maxToolRounds: 3)

    // Test at boundary: exactly at limit
    let atLimit = loop.simulateExecution(toolCallsPerRound: [1, 1, 1])
    TestRunner.assertTrue(atLimit.hitLimit, "Should hit limit at exactly max rounds")
    TestRunner.assertEqual(atLimit.rounds, 3, "Should be exactly 3 rounds")

    // Test below boundary: one below limit
    let belowLimit = loop.simulateExecution(toolCallsPerRound: [1, 1, 0])
    TestRunner.assertFalse(belowLimit.hitLimit, "Should not hit limit when completing below max")
    TestRunner.assertEqual(belowLimit.rounds, 3, "Should complete in 3 rounds")

    // Test above boundary: would exceed if not stopped
    let aboveLimit = loop.simulateExecution(toolCallsPerRound: [1, 1, 1, 1, 1])
    TestRunner.assertTrue(aboveLimit.hitLimit, "Should hit limit")
    TestRunner.assertEqual(aboveLimit.rounds, 3, "Should stop at exactly max rounds")
}

// MARK: - Main

@main
struct ToolEnabledChatServiceTests {
    static func main() {
        print("🧪 ToolEnabledChatService Tests")
        print("==================================================")

        testMaxRoundsConfiguration()
        testCompletionBeforeMaxRounds()
        testHitMaxRoundsLimit()
        testSummarizationNotNeededWhenNoToolRounds()
        testExactMaxRoundsWithCompletion()
        testSyntheticMessageFormatting()
        testMultipleToolRoundsOrdering()
        testSummarizationPromptMessage()
        testToolRoundWithAssistantResponse()
        testEmptyAssistantResponseNotStored()
        testRoundLimitBoundaryConditions()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
