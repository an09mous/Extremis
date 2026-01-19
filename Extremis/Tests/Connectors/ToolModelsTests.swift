// MARK: - Tool Models Unit Tests
// Comprehensive tests for ToolCall, ToolResult, ToolContent, ToolError, and related types

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

// MARK: - JSONValue (Inline for standalone test)

enum JSONValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    var asAny: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.asAny }
        case .object(let obj): return obj.mapValues { $0.asAny }
        }
    }

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let b as Bool: return .bool(b)
        case let arr as [Any]: return .array(arr.map { from($0) })
        case let dict as [String: Any]: return .object(dict.mapValues { from($0) })
        case is NSNull: return .null
        default: return .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if container.decodeNil() { self = .null }
        else if let arr = try? container.decode([JSONValue].self) { self = .array(arr) }
        else if let obj = try? container.decode([String: JSONValue].self) { self = .object(obj) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }
}

// MARK: - ToolCall (Inline for standalone test)

struct ToolCall: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let toolName: String
    let connectorID: String
    let originalToolName: String
    let arguments: [String: JSONValue]
    let requestedAt: Date

    init(
        id: String,
        toolName: String,
        connectorID: String,
        originalToolName: String,
        arguments: [String: JSONValue],
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
        self.originalToolName = originalToolName
        self.arguments = arguments
        self.requestedAt = requestedAt
    }

    var argumentsAsAny: [String: Any] {
        arguments.mapValues { $0.asAny }
    }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id &&
        lhs.toolName == rhs.toolName &&
        lhs.connectorID == rhs.connectorID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ToolError (Inline for standalone test)

struct ToolError: Equatable, Error, Sendable {
    let message: String
    let code: Int?
    let isRetryable: Bool

    init(message: String, code: Int? = nil, isRetryable: Bool = false) {
        self.message = message
        self.code = code
        self.isRetryable = isRetryable
    }
}

// MARK: - ToolContent (Inline for standalone test)

struct ToolContent: Equatable, Sendable {
    let text: String?
    let json: Data?
    let imageData: Data?
    let imageMimeType: String?

    init(
        text: String? = nil,
        json: Data? = nil,
        imageData: Data? = nil,
        imageMimeType: String? = nil
    ) {
        self.text = text
        self.json = json
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }

    var displaySummary: String {
        if let text = text {
            return text.count > 200 ? String(text.prefix(200)) + "..." : text
        }
        if json != nil { return "[JSON data]" }
        if imageData != nil { return "[Image]" }
        return "[Empty result]"
    }

    var contentForLLM: String {
        if let text = text { return text }
        if let json = json, let jsonString = String(data: json, encoding: .utf8) {
            return jsonString
        }
        if imageData != nil { return "[Image content - see attached image]" }
        return ""
    }

    static func text(_ text: String) -> ToolContent {
        ToolContent(text: text)
    }

    static func json(_ data: Data) -> ToolContent {
        ToolContent(json: data)
    }

    static func image(data: Data, mimeType: String) -> ToolContent {
        ToolContent(imageData: data, imageMimeType: mimeType)
    }
}

// MARK: - ToolOutcome (Inline for standalone test)

enum ToolOutcome: Sendable, Equatable {
    case success(ToolContent)
    case error(ToolError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - ToolResult (Inline for standalone test)

struct ToolResult: Identifiable, Sendable {
    let callID: String
    let toolName: String
    let outcome: ToolOutcome
    let duration: TimeInterval
    let completedAt: Date

    var id: String { callID }

    init(
        callID: String,
        toolName: String,
        outcome: ToolOutcome,
        duration: TimeInterval,
        completedAt: Date = Date()
    ) {
        self.callID = callID
        self.toolName = toolName
        self.outcome = outcome
        self.duration = duration
        self.completedAt = completedAt
    }

    var isSuccess: Bool { outcome.isSuccess }
    var isError: Bool { outcome.isError }

    var error: ToolError? {
        if case .error(let error) = outcome { return error }
        return nil
    }

    var content: ToolContent? {
        if case .success(let content) = outcome { return content }
        return nil
    }

    static func success(
        callID: String,
        toolName: String,
        content: ToolContent,
        duration: TimeInterval
    ) -> ToolResult {
        ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .success(content),
            duration: duration
        )
    }

    static func failure(
        callID: String,
        toolName: String,
        error: ToolError,
        duration: TimeInterval
    ) -> ToolResult {
        ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .error(error),
            duration: duration
        )
    }
}

// MARK: - LLMToolCall (Inline for standalone test)

struct LLMToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    let arguments: [String: Any]

    static func == (lhs: LLMToolCall, rhs: LLMToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

// MARK: - ToolExecutionRound (Inline for standalone test)

struct ToolExecutionRound {
    let toolCalls: [LLMToolCall]
    let results: [ToolResult]

    init(toolCalls: [LLMToolCall], results: [ToolResult]) {
        self.toolCalls = toolCalls
        self.results = results
    }
}

// MARK: - ToolEnabledGeneration (Inline for standalone test)

struct ToolEnabledGeneration {
    let content: String?
    let toolCalls: [LLMToolCall]

    var isComplete: Bool { toolCalls.isEmpty }

    static func text(_ content: String) -> ToolEnabledGeneration {
        ToolEnabledGeneration(content: content, toolCalls: [])
    }

    static func withTools(content: String?, toolCalls: [LLMToolCall]) -> ToolEnabledGeneration {
        ToolEnabledGeneration(content: content, toolCalls: toolCalls)
    }
}

// MARK: - Tests

func testJSONValue() {
    TestRunner.suite("JSONValue")

    // Test string
    let strVal = JSONValue.string("hello")
    TestRunner.assertEqual(strVal.asAny as? String, "hello", "String asAny")

    // Test number
    let numVal = JSONValue.number(42.5)
    TestRunner.assertEqual(numVal.asAny as? Double, 42.5, "Number asAny")

    // Test bool
    let boolVal = JSONValue.bool(true)
    TestRunner.assertEqual(boolVal.asAny as? Bool, true, "Bool asAny")

    // Test null
    let nullVal = JSONValue.null
    TestRunner.assertTrue(nullVal.asAny is NSNull, "Null asAny")

    // Test array
    let arrVal = JSONValue.array([.string("a"), .number(1)])
    TestRunner.assertTrue(arrVal.asAny is [Any], "Array asAny")

    // Test object
    let objVal = JSONValue.object(["key": .string("value")])
    let objAny = objVal.asAny as? [String: Any]
    TestRunner.assertNotNil(objAny, "Object asAny not nil")
    TestRunner.assertEqual(objAny?["key"] as? String, "value", "Object value")

    // Test from() conversions
    TestRunner.assertEqual(JSONValue.from("test"), .string("test"), "from String")
    TestRunner.assertEqual(JSONValue.from(123), .number(123), "from Int")
    TestRunner.assertEqual(JSONValue.from(true), .bool(true), "from Bool")
    TestRunner.assertEqual(JSONValue.from(NSNull()), .null, "from NSNull")

    // Test nested conversion
    let nested: [String: Any] = ["arr": [1, 2], "str": "test"]
    let nestedVal = JSONValue.from(nested)
    if case .object(let obj) = nestedVal {
        TestRunner.assertNotNil(obj["arr"], "Nested array exists")
        TestRunner.assertNotNil(obj["str"], "Nested string exists")
    } else {
        TestRunner.assertTrue(false, "Nested object conversion")
    }
}

func testToolCall() {
    TestRunner.suite("ToolCall")

    let args: [String: JSONValue] = [
        "query": .string("test query"),
        "limit": .number(10)
    ]

    let call = ToolCall(
        id: "call_123",
        toolName: "github_search",
        connectorID: "github-connector",
        originalToolName: "search",
        arguments: args
    )

    // Test basic properties
    TestRunner.assertEqual(call.id, "call_123", "ID")
    TestRunner.assertEqual(call.toolName, "github_search", "Tool name")
    TestRunner.assertEqual(call.connectorID, "github-connector", "Connector ID")
    TestRunner.assertEqual(call.originalToolName, "search", "Original tool name")

    // Test argumentsAsAny
    let anyArgs = call.argumentsAsAny
    TestRunner.assertEqual(anyArgs["query"] as? String, "test query", "Arguments query")
    TestRunner.assertEqual(anyArgs["limit"] as? Double, 10, "Arguments limit")

    // Test Equatable
    let samecall = ToolCall(
        id: "call_123",
        toolName: "github_search",
        connectorID: "github-connector",
        originalToolName: "search",
        arguments: [:]
    )
    TestRunner.assertTrue(call == samecall, "Same ID equals")

    let differentCall = ToolCall(
        id: "call_456",
        toolName: "github_search",
        connectorID: "github-connector",
        originalToolName: "search",
        arguments: args
    )
    TestRunner.assertFalse(call == differentCall, "Different ID not equals")

    // Test Hashable
    var set = Set<ToolCall>()
    set.insert(call)
    set.insert(samecall)
    TestRunner.assertEqual(set.count, 1, "Set deduplication by ID")
}

func testToolError() {
    TestRunner.suite("ToolError")

    // Basic error
    let basicError = ToolError(message: "Something went wrong")
    TestRunner.assertEqual(basicError.message, "Something went wrong", "Basic error message")
    TestRunner.assertNil(basicError.code, "Basic error no code")
    TestRunner.assertFalse(basicError.isRetryable, "Basic error not retryable")

    // Error with code
    let codedError = ToolError(message: "Not found", code: 404, isRetryable: false)
    TestRunner.assertEqual(codedError.code, 404, "Coded error code")

    // Retryable error
    let retryableError = ToolError(message: "Rate limited", code: 429, isRetryable: true)
    TestRunner.assertTrue(retryableError.isRetryable, "Retryable error")

    // Test Equatable
    let error1 = ToolError(message: "Error", code: 500, isRetryable: false)
    let error2 = ToolError(message: "Error", code: 500, isRetryable: false)
    let error3 = ToolError(message: "Different", code: 500, isRetryable: false)
    TestRunner.assertTrue(error1 == error2, "Same errors equal")
    TestRunner.assertFalse(error1 == error3, "Different messages not equal")
}

func testToolContent() {
    TestRunner.suite("ToolContent")

    // Text content
    let textContent = ToolContent.text("Hello world")
    TestRunner.assertEqual(textContent.text, "Hello world", "Text content")
    TestRunner.assertNil(textContent.json, "Text no JSON")
    TestRunner.assertNil(textContent.imageData, "Text no image")
    TestRunner.assertEqual(textContent.displaySummary, "Hello world", "Text display summary")
    TestRunner.assertEqual(textContent.contentForLLM, "Hello world", "Text content for LLM")

    // Long text truncation
    let longText = String(repeating: "a", count: 300)
    let longContent = ToolContent.text(longText)
    TestRunner.assertTrue(longContent.displaySummary.count < 210, "Long text truncated")
    TestRunner.assertTrue(longContent.displaySummary.hasSuffix("..."), "Truncated ends with ...")
    TestRunner.assertEqual(longContent.contentForLLM.count, 300, "contentForLLM not truncated")

    // JSON content
    let jsonData = "{\"key\":\"value\"}".data(using: .utf8)!
    let jsonContent = ToolContent.json(jsonData)
    TestRunner.assertEqual(jsonContent.displaySummary, "[JSON data]", "JSON display summary")
    TestRunner.assertEqual(jsonContent.contentForLLM, "{\"key\":\"value\"}", "JSON content for LLM")

    // Image content
    let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
    let imageContent = ToolContent.image(data: imageData, mimeType: "image/png")
    TestRunner.assertEqual(imageContent.displaySummary, "[Image]", "Image display summary")
    TestRunner.assertEqual(imageContent.contentForLLM, "[Image content - see attached image]", "Image content for LLM")
    TestRunner.assertEqual(imageContent.imageMimeType, "image/png", "Image MIME type")

    // Empty content
    let emptyContent = ToolContent()
    TestRunner.assertEqual(emptyContent.displaySummary, "[Empty result]", "Empty display summary")
    TestRunner.assertEqual(emptyContent.contentForLLM, "", "Empty content for LLM")
}

func testToolOutcome() {
    TestRunner.suite("ToolOutcome")

    // Success outcome
    let successContent = ToolContent.text("Success!")
    let success = ToolOutcome.success(successContent)
    TestRunner.assertTrue(success.isSuccess, "Success isSuccess")
    TestRunner.assertFalse(success.isError, "Success not isError")

    // Error outcome
    let errorObj = ToolError(message: "Failed")
    let error = ToolOutcome.error(errorObj)
    TestRunner.assertFalse(error.isSuccess, "Error not isSuccess")
    TestRunner.assertTrue(error.isError, "Error isError")

    // Test Equatable
    let success1 = ToolOutcome.success(ToolContent.text("Same"))
    let success2 = ToolOutcome.success(ToolContent.text("Same"))
    let success3 = ToolOutcome.success(ToolContent.text("Different"))
    TestRunner.assertTrue(success1 == success2, "Same success equal")
    TestRunner.assertFalse(success1 == success3, "Different success not equal")

    let error1 = ToolOutcome.error(ToolError(message: "Error"))
    let error2 = ToolOutcome.error(ToolError(message: "Error"))
    TestRunner.assertTrue(error1 == error2, "Same error equal")
    TestRunner.assertFalse(success1 == error1, "Success and error not equal")
}

func testToolResult() {
    TestRunner.suite("ToolResult")

    // Success result
    let successResult = ToolResult.success(
        callID: "call_1",
        toolName: "search",
        content: ToolContent.text("Found 5 results"),
        duration: 0.5
    )
    TestRunner.assertEqual(successResult.callID, "call_1", "Success call ID")
    TestRunner.assertEqual(successResult.toolName, "search", "Success tool name")
    TestRunner.assertTrue(successResult.isSuccess, "Success isSuccess")
    TestRunner.assertFalse(successResult.isError, "Success not isError")
    TestRunner.assertNotNil(successResult.content, "Success has content")
    TestRunner.assertNil(successResult.error, "Success no error")
    TestRunner.assertEqual(successResult.duration, 0.5, "Success duration")
    TestRunner.assertEqual(successResult.id, "call_1", "Success id = callID")

    // Failure result
    let failureResult = ToolResult.failure(
        callID: "call_2",
        toolName: "search",
        error: ToolError(message: "Connection timeout", isRetryable: true),
        duration: 30.0
    )
    TestRunner.assertEqual(failureResult.callID, "call_2", "Failure call ID")
    TestRunner.assertFalse(failureResult.isSuccess, "Failure not isSuccess")
    TestRunner.assertTrue(failureResult.isError, "Failure isError")
    TestRunner.assertNil(failureResult.content, "Failure no content")
    TestRunner.assertNotNil(failureResult.error, "Failure has error")
    TestRunner.assertEqual(failureResult.error?.message, "Connection timeout", "Failure error message")
    TestRunner.assertTrue(failureResult.error?.isRetryable ?? false, "Failure error retryable")
}

func testLLMToolCall() {
    TestRunner.suite("LLMToolCall")

    let call1 = LLMToolCall(id: "call_abc", name: "search", arguments: ["q": "test"])
    let call2 = LLMToolCall(id: "call_abc", name: "search", arguments: ["q": "different"])
    let call3 = LLMToolCall(id: "call_xyz", name: "search", arguments: ["q": "test"])

    // Test basic properties
    TestRunner.assertEqual(call1.id, "call_abc", "LLMToolCall ID")
    TestRunner.assertEqual(call1.name, "search", "LLMToolCall name")

    // Test Equatable (based on id and name only, not arguments)
    TestRunner.assertTrue(call1 == call2, "Same id/name equal (ignores arguments)")
    TestRunner.assertFalse(call1 == call3, "Different id not equal")
}

func testToolExecutionRound() {
    TestRunner.suite("ToolExecutionRound")

    // Create tool calls
    let toolCall1 = LLMToolCall(id: "call_1", name: "search", arguments: ["q": "test"])
    let toolCall2 = LLMToolCall(id: "call_2", name: "fetch", arguments: ["url": "http://example.com"])

    // Create results
    let result1 = ToolResult.success(
        callID: "call_1",
        toolName: "search",
        content: ToolContent.text("Results"),
        duration: 0.1
    )
    let result2 = ToolResult.failure(
        callID: "call_2",
        toolName: "fetch",
        error: ToolError(message: "Network error"),
        duration: 5.0
    )

    // Create round
    let round = ToolExecutionRound(
        toolCalls: [toolCall1, toolCall2],
        results: [result1, result2]
    )

    // Test properties
    TestRunner.assertEqual(round.toolCalls.count, 2, "Round has 2 tool calls")
    TestRunner.assertEqual(round.results.count, 2, "Round has 2 results")
    TestRunner.assertEqual(round.toolCalls[0].id, "call_1", "First call ID")
    TestRunner.assertEqual(round.results[0].callID, "call_1", "First result call ID")
    TestRunner.assertTrue(round.results[0].isSuccess, "First result success")
    TestRunner.assertTrue(round.results[1].isError, "Second result error")

    // Test empty round
    let emptyRound = ToolExecutionRound(toolCalls: [], results: [])
    TestRunner.assertEqual(emptyRound.toolCalls.count, 0, "Empty round no calls")
    TestRunner.assertEqual(emptyRound.results.count, 0, "Empty round no results")
}

func testToolEnabledGeneration() {
    TestRunner.suite("ToolEnabledGeneration")

    // Text only (complete)
    let textGen = ToolEnabledGeneration.text("Hello world")
    TestRunner.assertEqual(textGen.content, "Hello world", "Text content")
    TestRunner.assertTrue(textGen.toolCalls.isEmpty, "Text no tool calls")
    TestRunner.assertTrue(textGen.isComplete, "Text is complete")

    // With tool calls (not complete)
    let toolCalls = [
        LLMToolCall(id: "call_1", name: "search", arguments: [:]),
        LLMToolCall(id: "call_2", name: "fetch", arguments: [:])
    ]
    let toolGen = ToolEnabledGeneration.withTools(content: "I'll search for that", toolCalls: toolCalls)
    TestRunner.assertEqual(toolGen.content, "I'll search for that", "Tool gen content")
    TestRunner.assertEqual(toolGen.toolCalls.count, 2, "Tool gen has 2 calls")
    TestRunner.assertFalse(toolGen.isComplete, "Tool gen not complete")

    // Tool calls with nil content
    let noContentGen = ToolEnabledGeneration.withTools(content: nil, toolCalls: toolCalls)
    TestRunner.assertNil(noContentGen.content, "No content gen nil")
    TestRunner.assertFalse(noContentGen.isComplete, "No content gen not complete")

    // Empty tool calls = complete
    let emptyToolsGen = ToolEnabledGeneration(content: "Done", toolCalls: [])
    TestRunner.assertTrue(emptyToolsGen.isComplete, "Empty tools is complete")
}

func testMultiRoundScenario() {
    TestRunner.suite("Multi-Round Tool Execution Scenario")

    // Simulate a multi-round tool execution flow

    // Round 1: LLM requests search
    let round1Calls = [LLMToolCall(id: "r1_c1", name: "search", arguments: ["q": "Swift"])]
    let round1Results = [ToolResult.success(
        callID: "r1_c1",
        toolName: "search",
        content: ToolContent.text("Found 10 results"),
        duration: 0.2
    )]
    let round1 = ToolExecutionRound(toolCalls: round1Calls, results: round1Results)

    // Round 2: LLM requests two more tools
    let round2Calls = [
        LLMToolCall(id: "r2_c1", name: "fetch", arguments: ["url": "http://1"]),
        LLMToolCall(id: "r2_c2", name: "fetch", arguments: ["url": "http://2"])
    ]
    let round2Results = [
        ToolResult.success(callID: "r2_c1", toolName: "fetch", content: ToolContent.text("Page 1"), duration: 0.3),
        ToolResult.success(callID: "r2_c2", toolName: "fetch", content: ToolContent.text("Page 2"), duration: 0.4)
    ]
    let round2 = ToolExecutionRound(toolCalls: round2Calls, results: round2Results)

    // Collect all rounds
    let allRounds = [round1, round2]

    // Verify round count
    TestRunner.assertEqual(allRounds.count, 2, "Two rounds total")

    // Verify each round has matching call/result counts
    TestRunner.assertEqual(allRounds[0].toolCalls.count, allRounds[0].results.count, "Round 1 call/result count match")
    TestRunner.assertEqual(allRounds[1].toolCalls.count, allRounds[1].results.count, "Round 2 call/result count match")

    // Verify call IDs match result IDs
    for round in allRounds {
        for (call, result) in zip(round.toolCalls, round.results) {
            TestRunner.assertEqual(call.id, result.callID, "Call ID matches result callID: \(call.id)")
        }
    }

    // Calculate total tools executed
    let totalCalls = allRounds.reduce(0) { $0 + $1.toolCalls.count }
    TestRunner.assertEqual(totalCalls, 3, "Total 3 tool calls across rounds")

    // Verify all succeeded
    let allSucceeded = allRounds.allSatisfy { round in
        round.results.allSatisfy { $0.isSuccess }
    }
    TestRunner.assertTrue(allSucceeded, "All tools succeeded")
}

func testEdgeCases() {
    TestRunner.suite("Edge Cases")

    // Empty string content
    let emptyStringContent = ToolContent.text("")
    TestRunner.assertEqual(emptyStringContent.text, "", "Empty string preserved")
    TestRunner.assertEqual(emptyStringContent.displaySummary, "", "Empty string summary")

    // Special characters in content
    let specialContent = ToolContent.text("Test\n\twith\r\nspecial \"chars\" & <xml>")
    TestRunner.assertTrue(specialContent.text?.contains("\"chars\"") ?? false, "Special chars preserved")

    // Unicode content
    let unicodeContent = ToolContent.text("Hello 世界 🌍 مرحبا")
    TestRunner.assertEqual(unicodeContent.text, "Hello 世界 🌍 مرحبا", "Unicode preserved")

    // Very long tool name
    let longName = String(repeating: "a", count: 1000)
    let longNameCall = ToolCall(
        id: "call_long",
        toolName: longName,
        connectorID: "test",
        originalToolName: longName,
        arguments: [:]
    )
    TestRunner.assertEqual(longNameCall.toolName.count, 1000, "Long tool name preserved")

    // Zero duration
    let zeroDurationResult = ToolResult.success(
        callID: "call_fast",
        toolName: "instant",
        content: ToolContent.text("Done"),
        duration: 0.0
    )
    TestRunner.assertEqual(zeroDurationResult.duration, 0.0, "Zero duration allowed")

    // Very long duration
    let longDurationResult = ToolResult.failure(
        callID: "call_slow",
        toolName: "slow",
        error: ToolError(message: "Timeout"),
        duration: 3600.0 // 1 hour
    )
    TestRunner.assertEqual(longDurationResult.duration, 3600.0, "Long duration preserved")

    // Empty arguments
    let emptyArgsCall = ToolCall(
        id: "call_no_args",
        toolName: "noargs",
        connectorID: "test",
        originalToolName: "noargs",
        arguments: [:]
    )
    TestRunner.assertTrue(emptyArgsCall.arguments.isEmpty, "Empty arguments allowed")
    TestRunner.assertTrue(emptyArgsCall.argumentsAsAny.isEmpty, "Empty argumentsAsAny")

    // Nested JSON arguments
    let nestedArgs: [String: JSONValue] = [
        "config": .object([
            "nested": .object([
                "deep": .string("value")
            ])
        ])
    ]
    let nestedCall = ToolCall(
        id: "call_nested",
        toolName: "nested",
        connectorID: "test",
        originalToolName: "nested",
        arguments: nestedArgs
    )
    let nestedAny = nestedCall.argumentsAsAny
    TestRunner.assertTrue(nestedAny["config"] is [String: Any], "Nested conversion works")
}

// MARK: - Main

@main
struct ToolModelsTestsMain {
    static func main() {
        print("🧪 Tool Models Unit Tests")
        print("==================================================")

        testJSONValue()
        testToolCall()
        testToolError()
        testToolContent()
        testToolOutcome()
        testToolResult()
        testLLMToolCall()
        testToolExecutionRound()
        testToolEnabledGeneration()
        testMultiRoundScenario()
        testEdgeCases()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
