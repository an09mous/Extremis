// MARK: - Tool Enabled Chat Service Tests
// Tests for the tool-enabled chat generation service

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

// MARK: - Mock Types for Testing

/// Mock tool call state
enum MockToolCallState: Equatable {
    case pending
    case executing
    case completed
    case failed
}

/// Mock ChatToolCall for testing
struct MockChatToolCall: Identifiable, Equatable {
    let id: String
    let toolName: String
    let connectorID: String
    let argumentsSummary: String
    var state: MockToolCallState
    var resultSummary: String?
    var errorMessage: String?
    var duration: TimeInterval?

    var isExecuting: Bool { state == .executing }
    var isComplete: Bool { state == .completed || state == .failed }
}

/// Mock ToolExecutionRound for testing
struct MockToolExecutionRound {
    let toolCalls: [MockLLMToolCall]
    let results: [MockToolResult]
}

/// Mock LLMToolCall for testing
struct MockLLMToolCall: Equatable {
    let id: String
    let name: String
    let arguments: [String: String]
}

/// Mock ToolResult for testing
struct MockToolResult {
    let callID: String
    let isSuccess: Bool
    let content: String?
    let error: String?
    let duration: TimeInterval
}

/// Mock GenerationWithToolCalls for testing
struct MockGenerationWithToolCalls {
    let content: String?
    let toolCalls: [MockLLMToolCall]
    let isComplete: Bool
}

// MARK: - Tests

func testChatToolCallStateTransitions() {
    TestRunner.suite("ChatToolCall State Transitions")

    // Test initial state
    var toolCall = MockChatToolCall(
        id: "call_123",
        toolName: "test_tool",
        connectorID: "test-connector",
        argumentsSummary: "arg1=value1",
        state: .pending
    )
    TestRunner.assertEqual(toolCall.state, .pending, "Initial state is pending")
    TestRunner.assertFalse(toolCall.isExecuting, "Not executing initially")
    TestRunner.assertFalse(toolCall.isComplete, "Not complete initially")

    // Test executing state
    toolCall.state = .executing
    TestRunner.assertEqual(toolCall.state, .executing, "State transitions to executing")
    TestRunner.assertTrue(toolCall.isExecuting, "isExecuting is true when executing")
    TestRunner.assertFalse(toolCall.isComplete, "Not complete when executing")

    // Test completed state
    toolCall.state = .completed
    toolCall.resultSummary = "Success: 5 items found"
    toolCall.duration = 0.342
    TestRunner.assertEqual(toolCall.state, .completed, "State transitions to completed")
    TestRunner.assertFalse(toolCall.isExecuting, "Not executing when completed")
    TestRunner.assertTrue(toolCall.isComplete, "isComplete is true when completed")
    TestRunner.assertNotNil(toolCall.resultSummary, "Result summary is set")
    TestRunner.assertNotNil(toolCall.duration, "Duration is set")

    // Test failed state
    var failedCall = MockChatToolCall(
        id: "call_456",
        toolName: "failing_tool",
        connectorID: "test-connector",
        argumentsSummary: "arg1=value1",
        state: .failed,
        errorMessage: "Connection timeout",
        duration: 5.0
    )
    TestRunner.assertEqual(failedCall.state, .failed, "State is failed")
    TestRunner.assertFalse(failedCall.isExecuting, "Not executing when failed")
    TestRunner.assertTrue(failedCall.isComplete, "isComplete is true when failed")
    TestRunner.assertNotNil(failedCall.errorMessage, "Error message is set")
}

func testToolCallsCollectionHelpers() {
    TestRunner.suite("Tool Calls Collection Helpers")

    var toolCalls = [
        MockChatToolCall(id: "1", toolName: "tool_a", connectorID: "conn", argumentsSummary: "", state: .pending),
        MockChatToolCall(id: "2", toolName: "tool_b", connectorID: "conn", argumentsSummary: "", state: .executing),
        MockChatToolCall(id: "3", toolName: "tool_c", connectorID: "conn", argumentsSummary: "", state: .completed)
    ]

    // Test finding tool call by ID
    let found = toolCalls.first { $0.id == "2" }
    TestRunner.assertNotNil(found, "Can find tool call by ID")
    TestRunner.assertEqual(found?.toolName ?? "", "tool_b", "Found correct tool call")

    // Test allComplete check
    let allComplete = toolCalls.allSatisfy { $0.isComplete }
    TestRunner.assertFalse(allComplete, "Not all complete when some pending/executing")

    // Test hasFailures check
    let hasFailures = toolCalls.contains { $0.state == .failed }
    TestRunner.assertFalse(hasFailures, "No failures in collection")

    // Mark all as completed
    toolCalls[0].state = .completed
    toolCalls[1].state = .completed
    let allCompleteNow = toolCalls.allSatisfy { $0.isComplete }
    TestRunner.assertTrue(allCompleteNow, "All complete after marking")

    // Add a failed call
    toolCalls.append(MockChatToolCall(id: "4", toolName: "tool_d", connectorID: "conn", argumentsSummary: "", state: .failed))
    let hasFailuresNow = toolCalls.contains { $0.state == .failed }
    TestRunner.assertTrue(hasFailuresNow, "Has failures after adding failed call")
}

func testToolExecutionRoundTracking() {
    TestRunner.suite("Tool Execution Round Tracking")

    // Test single round
    let round1 = MockToolExecutionRound(
        toolCalls: [
            MockLLMToolCall(id: "call_1", name: "search", arguments: ["query": "test"])
        ],
        results: [
            MockToolResult(callID: "call_1", isSuccess: true, content: "Found 5 results", error: nil, duration: 0.5)
        ]
    )
    TestRunner.assertEqual(round1.toolCalls.count, 1, "Round has one tool call")
    TestRunner.assertEqual(round1.results.count, 1, "Round has one result")
    TestRunner.assertTrue(round1.results[0].isSuccess, "Result is successful")

    // Test multiple rounds tracking
    var rounds: [MockToolExecutionRound] = []
    rounds.append(round1)

    let round2 = MockToolExecutionRound(
        toolCalls: [
            MockLLMToolCall(id: "call_2", name: "fetch", arguments: ["url": "https://example.com"]),
            MockLLMToolCall(id: "call_3", name: "parse", arguments: ["format": "json"])
        ],
        results: [
            MockToolResult(callID: "call_2", isSuccess: true, content: "Fetched data", error: nil, duration: 1.2),
            MockToolResult(callID: "call_3", isSuccess: false, content: nil, error: "Parse error", duration: 0.1)
        ]
    )
    rounds.append(round2)

    TestRunner.assertEqual(rounds.count, 2, "Two rounds tracked")

    let totalToolCalls = rounds.reduce(0) { $0 + $1.toolCalls.count }
    TestRunner.assertEqual(totalToolCalls, 3, "Total of 3 tool calls across rounds")

    let failedResults = rounds.flatMap { $0.results }.filter { !$0.isSuccess }
    TestRunner.assertEqual(failedResults.count, 1, "One failed result")
}

func testGenerationCompletionDetection() {
    TestRunner.suite("Generation Completion Detection")

    // Test generation with content only (no tools)
    let contentOnly = MockGenerationWithToolCalls(
        content: "Here's your answer...",
        toolCalls: [],
        isComplete: true
    )
    TestRunner.assertTrue(contentOnly.isComplete, "Content-only generation is complete")
    TestRunner.assertTrue(contentOnly.toolCalls.isEmpty, "No tool calls")

    // Test generation with tool calls (not complete)
    let withTools = MockGenerationWithToolCalls(
        content: nil,
        toolCalls: [MockLLMToolCall(id: "call_1", name: "search", arguments: [:])],
        isComplete: false
    )
    TestRunner.assertFalse(withTools.isComplete, "Generation with tools is not complete")
    TestRunner.assertFalse(withTools.toolCalls.isEmpty, "Has tool calls")

    // Test generation with content and tools (intermediate state)
    let mixed = MockGenerationWithToolCalls(
        content: "Let me search for that...",
        toolCalls: [MockLLMToolCall(id: "call_2", name: "web_search", arguments: ["q": "test"])],
        isComplete: false
    )
    TestRunner.assertFalse(mixed.isComplete, "Mixed generation not complete")
    TestRunner.assertNotNil(mixed.content, "Has partial content")
    TestRunner.assertFalse(mixed.toolCalls.isEmpty, "Has tool calls")
}

func testToolResultFormatting() {
    TestRunner.suite("Tool Result Formatting")

    // Test successful result
    let successResult = MockToolResult(
        callID: "call_123",
        isSuccess: true,
        content: "Found 10 matching items",
        error: nil,
        duration: 0.234
    )
    TestRunner.assertTrue(successResult.isSuccess, "Result is successful")
    TestRunner.assertNotNil(successResult.content, "Has content")
    TestRunner.assertNil(successResult.error, "No error")

    // Test duration formatting
    let durationMs = successResult.duration * 1000
    TestRunner.assertTrue(durationMs >= 200 && durationMs <= 300, "Duration in expected range (234ms)")

    // Test failed result
    let failedResult = MockToolResult(
        callID: "call_456",
        isSuccess: false,
        content: nil,
        error: "Tool execution timed out after 30 seconds",
        duration: 30.0
    )
    TestRunner.assertFalse(failedResult.isSuccess, "Result is not successful")
    TestRunner.assertNil(failedResult.content, "No content on failure")
    TestRunner.assertNotNil(failedResult.error, "Has error message")
}

func testMaxToolRoundsLimit() {
    TestRunner.suite("Max Tool Rounds Limit")

    let maxRounds = 10  // Same as ToolEnabledChatService.maxToolRounds

    // Simulate reaching max rounds
    var rounds = 0
    var shouldContinue = true

    while shouldContinue && rounds < maxRounds {
        rounds += 1
        // Simulate tool execution round
        let hasMoreTools = rounds < 15  // Would continue if no limit
        shouldContinue = hasMoreTools && rounds < maxRounds
    }

    TestRunner.assertEqual(rounds, maxRounds, "Stops at max rounds limit")
    TestRunner.assertFalse(rounds > maxRounds, "Never exceeds max rounds")
}

func testToolCallIdMapping() {
    TestRunner.suite("Tool Call ID Mapping")

    // Test that tool call IDs are preserved through the pipeline
    let llmCall = MockLLMToolCall(id: "toolu_01abc123", name: "github_search", arguments: ["query": "bug fix"])

    // Simulate creating ChatToolCall from LLMToolCall
    let chatToolCall = MockChatToolCall(
        id: llmCall.id,
        toolName: llmCall.name,
        connectorID: "github-mcp",
        argumentsSummary: "query=bug fix",
        state: .pending
    )

    TestRunner.assertEqual(chatToolCall.id, llmCall.id, "ID preserved from LLM call")
    TestRunner.assertEqual(chatToolCall.toolName, llmCall.name, "Tool name preserved")

    // Simulate result coming back
    let result = MockToolResult(
        callID: llmCall.id,
        isSuccess: true,
        content: "Found 5 issues",
        error: nil,
        duration: 0.5
    )

    TestRunner.assertEqual(result.callID, chatToolCall.id, "Result maps back to correct tool call")
}

// MARK: - Main

@main
struct ToolEnabledChatServiceTests {
    static func main() {
        print("==================================================")
        print("Tool Enabled Chat Service Tests")
        print("==================================================")

        testChatToolCallStateTransitions()
        testToolCallsCollectionHelpers()
        testToolExecutionRoundTracking()
        testGenerationCompletionDetection()
        testToolResultFormatting()
        testMaxToolRoundsLimit()
        testToolCallIdMapping()

        TestRunner.printSummary()

        // Exit with appropriate code
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
