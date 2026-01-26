// MARK: - Tool Persistence Tests
// Tests for tool call and result persistence in chat messages

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

/// Simplified ToolCallRecord for standalone testing
struct ToolCallRecord: Codable, Identifiable, Equatable {
    let id: String
    let toolName: String
    let connectorID: String
    let argumentsJSON: String
    let requestedAt: Date

    var argumentsDisplay: String {
        guard let data = argumentsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return argumentsJSON
        }
        let formatted = dict.map { key, value in
            let valueStr = String(describing: value)
            let truncated = valueStr.count > 30 ? String(valueStr.prefix(30)) + "..." : valueStr
            return "\(key)=\(truncated)"
        }
        let joined = formatted.joined(separator: ", ")
        return joined.count > 100 ? String(joined.prefix(100)) + "..." : joined
    }
}

/// Simplified ToolResultRecord for standalone testing
struct ToolResultRecord: Codable, Identifiable, Equatable {
    let callID: String
    let toolName: String
    let isSuccess: Bool
    let content: String
    let duration: TimeInterval
    let completedAt: Date

    var id: String { callID }

    var displaySummary: String {
        content.count > 200 ? String(content.prefix(200)) + "..." : content
    }

    var durationString: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        return String(format: "%.1fs", duration)
    }
}

/// Simplified ToolExecutionRoundRecord for standalone testing
struct ToolExecutionRoundRecord: Codable, Equatable {
    let toolCalls: [ToolCallRecord]
    let results: [ToolResultRecord]
    let assistantResponse: String?

    init(toolCalls: [ToolCallRecord], results: [ToolResultRecord], assistantResponse: String? = nil) {
        self.toolCalls = toolCalls
        self.results = results
        self.assistantResponse = assistantResponse
    }

    var allSucceeded: Bool {
        results.allSatisfy { $0.isSuccess }
    }

    var hasFailures: Bool {
        results.contains { !$0.isSuccess }
    }

    var totalDuration: TimeInterval {
        results.reduce(0) { $0 + $1.duration }
    }
}

extension Array where Element == ToolExecutionRoundRecord {
    var totalToolCalls: Int {
        reduce(0) { $0 + $1.toolCalls.count }
    }

    var totalFailures: Int {
        reduce(0) { sum, round in
            sum + round.results.filter { !$0.isSuccess }.count
        }
    }
}

// MARK: - Tests

func testToolCallRecordCodable() {
    TestRunner.suite("ToolCallRecord Codable")

    let original = ToolCallRecord(
        id: "call_123",
        toolName: "github_search_issues",
        connectorID: "github-mcp",
        argumentsJSON: "{\"query\":\"bug fix\",\"limit\":10}",
        requestedAt: Date()
    )

    // Encode
    guard let encoded = try? JSONEncoder().encode(original) else {
        TestRunner.assertTrue(false, "Encoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding succeeds")

    // Decode
    guard let decoded = try? JSONDecoder().decode(ToolCallRecord.self, from: encoded) else {
        TestRunner.assertTrue(false, "Decoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding succeeds")

    // Verify fields
    TestRunner.assertEqual(decoded.id, original.id, "ID preserved")
    TestRunner.assertEqual(decoded.toolName, original.toolName, "Tool name preserved")
    TestRunner.assertEqual(decoded.connectorID, original.connectorID, "Connector ID preserved")
    TestRunner.assertEqual(decoded.argumentsJSON, original.argumentsJSON, "Arguments JSON preserved")
}

func testToolResultRecordCodable() {
    TestRunner.suite("ToolResultRecord Codable")

    let original = ToolResultRecord(
        callID: "call_123",
        toolName: "github_search_issues",
        isSuccess: true,
        content: "Found 5 matching issues",
        duration: 0.342,
        completedAt: Date()
    )

    // Encode
    guard let encoded = try? JSONEncoder().encode(original) else {
        TestRunner.assertTrue(false, "Encoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding succeeds")

    // Decode
    guard let decoded = try? JSONDecoder().decode(ToolResultRecord.self, from: encoded) else {
        TestRunner.assertTrue(false, "Decoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding succeeds")

    // Verify fields
    TestRunner.assertEqual(decoded.callID, original.callID, "Call ID preserved")
    TestRunner.assertEqual(decoded.toolName, original.toolName, "Tool name preserved")
    TestRunner.assertEqual(decoded.isSuccess, original.isSuccess, "Success status preserved")
    TestRunner.assertEqual(decoded.content, original.content, "Content preserved")
    TestRunner.assertEqual(decoded.duration, original.duration, "Duration preserved")
}

func testToolExecutionRoundRecordCodable() {
    TestRunner.suite("ToolExecutionRoundRecord Codable")

    let toolCall = ToolCallRecord(
        id: "call_1",
        toolName: "search",
        connectorID: "mcp-server",
        argumentsJSON: "{\"q\":\"test\"}",
        requestedAt: Date()
    )

    let result = ToolResultRecord(
        callID: "call_1",
        toolName: "search",
        isSuccess: true,
        content: "Found results",
        duration: 0.5,
        completedAt: Date()
    )

    let original = ToolExecutionRoundRecord(toolCalls: [toolCall], results: [result])

    // Encode
    guard let encoded = try? JSONEncoder().encode(original) else {
        TestRunner.assertTrue(false, "Encoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding succeeds")

    // Decode
    guard let decoded = try? JSONDecoder().decode(ToolExecutionRoundRecord.self, from: encoded) else {
        TestRunner.assertTrue(false, "Decoding should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding succeeds")

    // Verify
    TestRunner.assertEqual(decoded.toolCalls.count, 1, "Tool calls count preserved")
    TestRunner.assertEqual(decoded.results.count, 1, "Results count preserved")
    TestRunner.assertEqual(decoded.toolCalls[0].id, "call_1", "Tool call ID preserved")
    TestRunner.assertEqual(decoded.results[0].callID, "call_1", "Result call ID preserved")
}

func testToolExecutionRoundComputedProperties() {
    TestRunner.suite("ToolExecutionRound Computed Properties")

    // Round with all success
    let successRound = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "1", toolName: "a", connectorID: "c", argumentsJSON: "{}", requestedAt: Date()),
            ToolCallRecord(id: "2", toolName: "b", connectorID: "c", argumentsJSON: "{}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "1", toolName: "a", isSuccess: true, content: "ok", duration: 0.1, completedAt: Date()),
            ToolResultRecord(callID: "2", toolName: "b", isSuccess: true, content: "ok", duration: 0.2, completedAt: Date())
        ]
    )

    TestRunner.assertTrue(successRound.allSucceeded, "All succeeded is true when all results succeed")
    TestRunner.assertFalse(successRound.hasFailures, "Has failures is false when all succeed")
    // Use approximate comparison for floating point
    let durationDiff = abs(successRound.totalDuration - 0.3)
    TestRunner.assertTrue(durationDiff < 0.0001, "Total duration sums correctly (within tolerance)")

    // Round with failure
    let failureRound = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "3", toolName: "c", connectorID: "c", argumentsJSON: "{}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "3", toolName: "c", isSuccess: false, content: "Error", duration: 1.0, completedAt: Date())
        ]
    )

    TestRunner.assertFalse(failureRound.allSucceeded, "All succeeded is false when any fails")
    TestRunner.assertTrue(failureRound.hasFailures, "Has failures is true when any fails")
}

func testToolRoundsArrayExtensions() {
    TestRunner.suite("Tool Rounds Array Extensions")

    let round1 = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "1", toolName: "a", connectorID: "c", argumentsJSON: "{}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "1", toolName: "a", isSuccess: true, content: "ok", duration: 0.1, completedAt: Date())
        ]
    )

    let round2 = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "2", toolName: "b", connectorID: "c", argumentsJSON: "{}", requestedAt: Date()),
            ToolCallRecord(id: "3", toolName: "c", connectorID: "c", argumentsJSON: "{}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "2", toolName: "b", isSuccess: true, content: "ok", duration: 0.2, completedAt: Date()),
            ToolResultRecord(callID: "3", toolName: "c", isSuccess: false, content: "error", duration: 0.3, completedAt: Date())
        ]
    )

    let rounds = [round1, round2]

    TestRunner.assertEqual(rounds.totalToolCalls, 3, "Total tool calls is sum across rounds")
    TestRunner.assertEqual(rounds.totalFailures, 1, "Total failures counts failed results")
}

func testArgumentsDisplay() {
    TestRunner.suite("Arguments Display Formatting")

    // Simple arguments
    let simple = ToolCallRecord(
        id: "1",
        toolName: "search",
        connectorID: "c",
        argumentsJSON: "{\"query\":\"test\"}",
        requestedAt: Date()
    )
    TestRunner.assertTrue(simple.argumentsDisplay.contains("query"), "Display contains key")
    TestRunner.assertTrue(simple.argumentsDisplay.contains("test"), "Display contains value")

    // Long value should be truncated
    let longValue = String(repeating: "x", count: 50)
    let longJSON = "{\"data\":\"\(longValue)\"}"
    let longArgs = ToolCallRecord(
        id: "2",
        toolName: "process",
        connectorID: "c",
        argumentsJSON: longJSON,
        requestedAt: Date()
    )
    TestRunner.assertTrue(longArgs.argumentsDisplay.contains("..."), "Long values are truncated")

    // Invalid JSON returns raw
    let invalid = ToolCallRecord(
        id: "3",
        toolName: "test",
        connectorID: "c",
        argumentsJSON: "not json",
        requestedAt: Date()
    )
    TestRunner.assertEqual(invalid.argumentsDisplay, "not json", "Invalid JSON returns raw string")
}

func testDurationFormatting() {
    TestRunner.suite("Duration Formatting")

    // Milliseconds
    let fastResult = ToolResultRecord(
        callID: "1",
        toolName: "fast",
        isSuccess: true,
        content: "ok",
        duration: 0.234,
        completedAt: Date()
    )
    TestRunner.assertEqual(fastResult.durationString, "234ms", "Sub-second shows milliseconds")

    // Seconds
    let slowResult = ToolResultRecord(
        callID: "2",
        toolName: "slow",
        isSuccess: true,
        content: "ok",
        duration: 2.5,
        completedAt: Date()
    )
    TestRunner.assertEqual(slowResult.durationString, "2.5s", "Multi-second shows seconds")
}

func testDisplaySummaryTruncation() {
    TestRunner.suite("Display Summary Truncation")

    // Short content - no truncation
    let shortResult = ToolResultRecord(
        callID: "1",
        toolName: "test",
        isSuccess: true,
        content: "Short content",
        duration: 0.1,
        completedAt: Date()
    )
    TestRunner.assertEqual(shortResult.displaySummary, "Short content", "Short content not truncated")

    // Long content - truncated
    let longContent = String(repeating: "x", count: 300)
    let longResult = ToolResultRecord(
        callID: "2",
        toolName: "test",
        isSuccess: true,
        content: longContent,
        duration: 0.1,
        completedAt: Date()
    )
    TestRunner.assertTrue(longResult.displaySummary.count <= 203, "Long content truncated to ~200 chars")
    TestRunner.assertTrue(longResult.displaySummary.hasSuffix("..."), "Truncated content ends with ellipsis")
}

func testMultipleRoundsPersistence() {
    TestRunner.suite("Multiple Rounds Persistence")

    // Create multiple rounds like a real tool execution session
    let round1 = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "call_1", toolName: "search", connectorID: "mcp", argumentsJSON: "{\"q\":\"bugs\"}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "call_1", toolName: "search", isSuccess: true, content: "Found 5 bugs", duration: 0.5, completedAt: Date())
        ]
    )

    let round2 = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "call_2", toolName: "get_details", connectorID: "mcp", argumentsJSON: "{\"id\":123}", requestedAt: Date()),
            ToolCallRecord(id: "call_3", toolName: "get_comments", connectorID: "mcp", argumentsJSON: "{\"id\":123}", requestedAt: Date())
        ],
        results: [
            ToolResultRecord(callID: "call_2", toolName: "get_details", isSuccess: true, content: "Bug details...", duration: 0.3, completedAt: Date()),
            ToolResultRecord(callID: "call_3", toolName: "get_comments", isSuccess: true, content: "3 comments", duration: 0.2, completedAt: Date())
        ]
    )

    let rounds = [round1, round2]

    // Encode all rounds
    guard let encoded = try? JSONEncoder().encode(rounds) else {
        TestRunner.assertTrue(false, "Encoding multiple rounds should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding multiple rounds succeeds")

    // Decode
    guard let decoded = try? JSONDecoder().decode([ToolExecutionRoundRecord].self, from: encoded) else {
        TestRunner.assertTrue(false, "Decoding multiple rounds should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding multiple rounds succeeds")

    // Verify structure
    TestRunner.assertEqual(decoded.count, 2, "Two rounds decoded")
    TestRunner.assertEqual(decoded[0].toolCalls.count, 1, "First round has 1 tool call")
    TestRunner.assertEqual(decoded[1].toolCalls.count, 2, "Second round has 2 tool calls")
    TestRunner.assertEqual(decoded.totalToolCalls, 3, "Total 3 tool calls across rounds")
}

func testEmptyRoundsHandling() {
    TestRunner.suite("Empty Rounds Handling")

    // Empty array
    let emptyRounds: [ToolExecutionRoundRecord] = []
    TestRunner.assertEqual(emptyRounds.totalToolCalls, 0, "Empty rounds have 0 tool calls")
    TestRunner.assertEqual(emptyRounds.totalFailures, 0, "Empty rounds have 0 failures")

    // Round with no results (edge case)
    let emptyResultRound = ToolExecutionRoundRecord(
        toolCalls: [
            ToolCallRecord(id: "1", toolName: "test", connectorID: "c", argumentsJSON: "{}", requestedAt: Date())
        ],
        results: []
    )
    TestRunner.assertTrue(emptyResultRound.allSucceeded, "Empty results means all succeeded (vacuous truth)")
    TestRunner.assertFalse(emptyResultRound.hasFailures, "Empty results has no failures")
    TestRunner.assertEqual(emptyResultRound.totalDuration, 0, "Empty results has 0 duration")
}

func testAssistantResponsePersistence() {
    TestRunner.suite("Assistant Response Persistence")

    let toolCall = ToolCallRecord(
        id: "call_1",
        toolName: "search",
        connectorID: "mcp-server",
        argumentsJSON: "{\"q\":\"test\"}",
        requestedAt: Date()
    )

    let result = ToolResultRecord(
        callID: "call_1",
        toolName: "search",
        isSuccess: true,
        content: "Found 5 results",
        duration: 0.5,
        completedAt: Date()
    )

    // Test round with assistant response
    let roundWithResponse = ToolExecutionRoundRecord(
        toolCalls: [toolCall],
        results: [result],
        assistantResponse: "I found 5 results matching your query. Here's a summary..."
    )

    // Encode
    guard let encoded = try? JSONEncoder().encode(roundWithResponse) else {
        TestRunner.assertTrue(false, "Encoding round with assistantResponse should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding round with assistantResponse succeeds")

    // Decode
    guard let decoded = try? JSONDecoder().decode(ToolExecutionRoundRecord.self, from: encoded) else {
        TestRunner.assertTrue(false, "Decoding round with assistantResponse should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding round with assistantResponse succeeds")

    // Verify assistantResponse preserved
    TestRunner.assertNotNil(decoded.assistantResponse, "assistantResponse is present after decoding")
    TestRunner.assertEqual(decoded.assistantResponse!, roundWithResponse.assistantResponse!, "assistantResponse content preserved")

    // Test round without assistant response (nil)
    let roundWithoutResponse = ToolExecutionRoundRecord(
        toolCalls: [toolCall],
        results: [result],
        assistantResponse: nil
    )

    guard let encodedNil = try? JSONEncoder().encode(roundWithoutResponse) else {
        TestRunner.assertTrue(false, "Encoding round without assistantResponse should succeed")
        return
    }
    TestRunner.assertTrue(true, "Encoding round without assistantResponse succeeds")

    guard let decodedNil = try? JSONDecoder().decode(ToolExecutionRoundRecord.self, from: encodedNil) else {
        TestRunner.assertTrue(false, "Decoding round without assistantResponse should succeed")
        return
    }
    TestRunner.assertTrue(true, "Decoding round without assistantResponse succeeds")
    TestRunner.assertNil(decodedNil.assistantResponse, "nil assistantResponse preserved")
}

func testBackwardCompatibilityWithoutAssistantResponse() {
    TestRunner.suite("Backward Compatibility Without Assistant Response")

    // Simulate old JSON format without assistantResponse field
    let oldFormatJSON = """
    {
        "toolCalls": [{
            "id": "call_1",
            "toolName": "search",
            "connectorID": "mcp",
            "argumentsJSON": "{}",
            "requestedAt": 0
        }],
        "results": [{
            "callID": "call_1",
            "toolName": "search",
            "isSuccess": true,
            "content": "results",
            "duration": 0.5,
            "completedAt": 0
        }]
    }
    """

    guard let data = oldFormatJSON.data(using: .utf8) else {
        TestRunner.assertTrue(false, "Creating JSON data should succeed")
        return
    }

    // Decode old format - assistantResponse should be nil
    guard let decoded = try? JSONDecoder().decode(ToolExecutionRoundRecord.self, from: data) else {
        TestRunner.assertTrue(false, "Decoding old format should succeed")
        return
    }
    TestRunner.assertTrue(true, "Old format without assistantResponse decodes successfully")
    TestRunner.assertNil(decoded.assistantResponse, "Missing assistantResponse defaults to nil")
    TestRunner.assertEqual(decoded.toolCalls.count, 1, "Tool calls preserved from old format")
    TestRunner.assertEqual(decoded.results.count, 1, "Results preserved from old format")
}

// MARK: - Main

@main
struct ToolPersistenceTests {
    static func main() {
        print("==================================================")
        print("Tool Persistence Tests")
        print("==================================================")

        testToolCallRecordCodable()
        testToolResultRecordCodable()
        testToolExecutionRoundRecordCodable()
        testToolExecutionRoundComputedProperties()
        testToolRoundsArrayExtensions()
        testArgumentsDisplay()
        testDurationFormatting()
        testDisplaySummaryTruncation()
        testMultipleRoundsPersistence()
        testEmptyRoundsHandling()
        testAssistantResponsePersistence()
        testBackwardCompatibilityWithoutAssistantResponse()

        TestRunner.printSummary()

        // Exit with appropriate code
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
