// MARK: - Tool Executor Unit Tests
// Tests for ToolExecutor parallel execution and timeout handling

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

    static func assertGreaterThan<T: Comparable>(_ actual: T, _ threshold: T, _ testName: String) {
        if actual > threshold {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected value > \(threshold) but got \(actual)"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertLessThan<T: Comparable>(_ actual: T, _ threshold: T, _ testName: String) {
        if actual < threshold {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected value < \(threshold) but got \(actual)"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
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

// MARK: - Inline Model Definitions (for standalone test)

/// JSON value type
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

/// Tool call representation
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

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id && lhs.toolName == rhs.toolName && lhs.connectorID == rhs.connectorID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Tool error
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

/// Tool content
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

    static func text(_ text: String) -> ToolContent {
        ToolContent(text: text)
    }
}

/// Tool outcome
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

/// Tool result
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

/// Batch result
struct BatchToolExecutionResult {
    let results: [ToolResult]

    var successes: [ToolResult] {
        results.filter { $0.isSuccess }
    }

    var failures: [ToolResult] {
        results.filter { $0.isError }
    }

    var allSucceeded: Bool {
        failures.isEmpty
    }

    var totalDuration: TimeInterval {
        results.map { $0.duration }.max() ?? 0
    }

    var summary: String {
        let total = results.count
        let succeeded = successes.count
        let failed = failures.count
        return "\(succeeded)/\(total) succeeded, \(failed) failed in \(String(format: "%.2f", totalDuration))s"
    }
}

// MARK: - Timeout Helper

/// Error thrown when an operation times out
struct TimeoutError: Error {
    let timeout: TimeInterval
}

/// Execute an async operation with a timeout
func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError(timeout: timeout)
        }

        // Get the first result (either success or timeout)
        guard let result = try await group.next() else {
            throw TimeoutError(timeout: timeout)
        }

        // Cancel the remaining task
        group.cancelAll()

        return result
    }
}

// MARK: - Mock Tool Executor

/// Mock connector for testing
actor MockConnector {
    let id: String
    let name: String
    var simulatedDelay: TimeInterval
    var shouldFail: Bool
    var failureMessage: String

    init(
        id: String,
        name: String,
        simulatedDelay: TimeInterval = 0.01,
        shouldFail: Bool = false,
        failureMessage: String = "Mock failure"
    ) {
        self.id = id
        self.name = name
        self.simulatedDelay = simulatedDelay
        self.shouldFail = shouldFail
        self.failureMessage = failureMessage
    }

    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        let startTime = Date()

        // Simulate delay
        if simulatedDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }

        let duration = Date().timeIntervalSince(startTime)

        if shouldFail {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: failureMessage),
                duration: duration
            )
        }

        return ToolResult.success(
            callID: call.id,
            toolName: call.toolName,
            content: ToolContent.text("Result for \(call.toolName)"),
            duration: duration
        )
    }

    func setDelay(_ delay: TimeInterval) {
        self.simulatedDelay = delay
    }

    func setFailure(_ fail: Bool, message: String = "Mock failure") {
        self.shouldFail = fail
        self.failureMessage = message
    }
}

/// Mock tool executor for testing
actor MockToolExecutor {
    private var connectors: [String: MockConnector] = [:]
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 30.0) {
        self.timeout = timeout
    }

    func registerConnector(_ connector: MockConnector) async {
        let id = await connector.id
        connectors[id] = connector
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        let startTime = Date()

        guard let connector = connectors[call.connectorID] else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Connector not found: \(call.connectorID)"),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        do {
            let result = try await withTimeout(timeout) {
                try await connector.executeTool(call)
            }
            return result
        } catch is TimeoutError {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(
                    message: "Tool execution timed out after \(Int(timeout)) seconds",
                    isRetryable: true
                ),
                duration: Date().timeIntervalSince(startTime)
            )
        } catch let error as ToolError {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: error,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: error.localizedDescription),
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    func execute(toolCalls calls: [ToolCall]) async -> [ToolResult] {
        guard !calls.isEmpty else { return [] }

        var results: [ToolResult] = []
        results.reserveCapacity(calls.count)

        for call in calls {
            let result = await execute(call)
            results.append(result)
        }

        return results
    }

    func executeBatch(_ calls: [ToolCall]) async -> BatchToolExecutionResult {
        let results = await execute(toolCalls: calls)
        return BatchToolExecutionResult(results: results)
    }
}

// MARK: - Tests

func testEmptyToolCalls() {
    TestRunner.suite("Empty Tool Calls")

    let executor = MockToolExecutor()

    // Run the async test
    let semaphore = DispatchSemaphore(value: 0)
    var results: [ToolResult] = []

    Task {
        results = await executor.execute(toolCalls: [])
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertTrue(results.isEmpty, "Empty input returns empty results")
}

func testSingleToolExecution() {
    TestRunner.suite("Single Tool Execution")

    let connector = MockConnector(id: "test-connector", name: "Test")
    let executor = MockToolExecutor()

    let call = ToolCall(
        id: "call_1",
        toolName: "test_tool",
        connectorID: "test-connector",
        originalToolName: "tool",
        arguments: [:]
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        await executor.registerConnector(connector)
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertTrue(result?.isSuccess ?? false, "Execution succeeded")
    TestRunner.assertEqual(result?.callID, "call_1", "Correct call ID")
    TestRunner.assertEqual(result?.toolName, "test_tool", "Correct tool name")
    TestRunner.assertNotNil(result?.content?.text, "Content has text")
}

func testMultipleToolExecution() {
    TestRunner.suite("Multiple Tool Execution")

    let connector = MockConnector(id: "test-connector", name: "Test", simulatedDelay: 0.001)
    let executor = MockToolExecutor()

    let calls = [
        ToolCall(id: "call_1", toolName: "tool_a", connectorID: "test-connector", originalToolName: "a", arguments: [:]),
        ToolCall(id: "call_2", toolName: "tool_b", connectorID: "test-connector", originalToolName: "b", arguments: [:]),
        ToolCall(id: "call_3", toolName: "tool_c", connectorID: "test-connector", originalToolName: "c", arguments: [:])
    ]

    let semaphore = DispatchSemaphore(value: 0)
    var results: [ToolResult] = []

    Task {
        await executor.registerConnector(connector)
        results = await executor.execute(toolCalls: calls)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertEqual(results.count, 3, "Three results returned")
    TestRunner.assertTrue(results.allSatisfy { $0.isSuccess }, "All executions succeeded")
    TestRunner.assertEqual(results[0].callID, "call_1", "First result has correct ID")
    TestRunner.assertEqual(results[1].callID, "call_2", "Second result has correct ID")
    TestRunner.assertEqual(results[2].callID, "call_3", "Third result has correct ID")
}

func testConnectorNotFound() {
    TestRunner.suite("Connector Not Found")

    let executor = MockToolExecutor()

    let call = ToolCall(
        id: "call_1",
        toolName: "some_tool",
        connectorID: "non-existent-connector",
        originalToolName: "tool",
        arguments: [:]
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertTrue(result?.isError ?? false, "Execution failed")
    TestRunner.assertTrue(result?.error?.message.contains("not found") ?? false, "Error mentions not found")
}

func testToolFailure() {
    TestRunner.suite("Tool Execution Failure")

    let connector = MockConnector(
        id: "failing-connector",
        name: "Failing",
        shouldFail: true,
        failureMessage: "Simulated failure"
    )
    let executor = MockToolExecutor()

    let call = ToolCall(
        id: "call_1",
        toolName: "failing_tool",
        connectorID: "failing-connector",
        originalToolName: "tool",
        arguments: [:]
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        await executor.registerConnector(connector)
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertTrue(result?.isError ?? false, "Execution failed")
    TestRunner.assertEqual(result?.error?.message, "Simulated failure", "Error message matches")
}

func testTimeoutHandling() {
    TestRunner.suite("Timeout Handling")

    // Create a connector with a very long delay
    let connector = MockConnector(
        id: "slow-connector",
        name: "Slow",
        simulatedDelay: 10.0 // 10 seconds - will exceed timeout
    )
    // Use a short timeout for testing
    let executor = MockToolExecutor(timeout: 0.1) // 100ms timeout

    let call = ToolCall(
        id: "call_slow",
        toolName: "slow_tool",
        connectorID: "slow-connector",
        originalToolName: "tool",
        arguments: [:]
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        await executor.registerConnector(connector)
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertTrue(result?.isError ?? false, "Execution timed out")
    TestRunner.assertTrue(result?.error?.message.contains("timed out") ?? false, "Error mentions timeout")
    TestRunner.assertTrue(result?.error?.isRetryable ?? false, "Timeout error is retryable")
}

func testBatchExecution() {
    TestRunner.suite("Batch Execution")

    let connector = MockConnector(id: "batch-connector", name: "Batch")
    let executor = MockToolExecutor()

    let calls = [
        ToolCall(id: "batch_1", toolName: "tool_1", connectorID: "batch-connector", originalToolName: "t1", arguments: [:]),
        ToolCall(id: "batch_2", toolName: "tool_2", connectorID: "batch-connector", originalToolName: "t2", arguments: [:])
    ]

    let semaphore = DispatchSemaphore(value: 0)
    var batch: BatchToolExecutionResult?

    Task {
        await executor.registerConnector(connector)
        batch = await executor.executeBatch(calls)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(batch, "Batch result returned")
    TestRunner.assertEqual(batch?.results.count, 2, "Two results in batch")
    TestRunner.assertEqual(batch?.successes.count, 2, "Two successes")
    TestRunner.assertEqual(batch?.failures.count, 0, "No failures")
    TestRunner.assertTrue(batch?.allSucceeded ?? false, "All succeeded")
}

func testBatchWithMixedResults() {
    TestRunner.suite("Batch With Mixed Results")

    let goodConnector = MockConnector(id: "good-connector", name: "Good")
    let badConnector = MockConnector(
        id: "bad-connector",
        name: "Bad",
        shouldFail: true,
        failureMessage: "Bad connector failure"
    )
    let executor = MockToolExecutor()

    let calls = [
        ToolCall(id: "call_good", toolName: "good_tool", connectorID: "good-connector", originalToolName: "good", arguments: [:]),
        ToolCall(id: "call_bad", toolName: "bad_tool", connectorID: "bad-connector", originalToolName: "bad", arguments: [:])
    ]

    let semaphore = DispatchSemaphore(value: 0)
    var batch: BatchToolExecutionResult?

    Task {
        await executor.registerConnector(goodConnector)
        await executor.registerConnector(badConnector)
        batch = await executor.executeBatch(calls)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(batch, "Batch result returned")
    TestRunner.assertEqual(batch?.results.count, 2, "Two results")
    TestRunner.assertEqual(batch?.successes.count, 1, "One success")
    TestRunner.assertEqual(batch?.failures.count, 1, "One failure")
    TestRunner.assertFalse(batch?.allSucceeded ?? true, "Not all succeeded")
}

func testResultDurationTracking() {
    TestRunner.suite("Result Duration Tracking")

    let delay: TimeInterval = 0.05 // 50ms
    let connector = MockConnector(id: "timed-connector", name: "Timed", simulatedDelay: delay)
    let executor = MockToolExecutor()

    let call = ToolCall(
        id: "timed_call",
        toolName: "timed_tool",
        connectorID: "timed-connector",
        originalToolName: "tool",
        arguments: [:]
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        await executor.registerConnector(connector)
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertGreaterThan(result?.duration ?? 0, 0, "Duration is positive")
    // Allow some tolerance for timing
    TestRunner.assertGreaterThan(result?.duration ?? 0, delay * 0.5, "Duration reflects delay (with tolerance)")
}

func testResultsPreserveOrder() {
    TestRunner.suite("Results Preserve Order")

    let connector = MockConnector(id: "order-connector", name: "Order", simulatedDelay: 0.001)
    let executor = MockToolExecutor()

    let calls = (1...5).map { i in
        ToolCall(
            id: "call_\(i)",
            toolName: "tool_\(i)",
            connectorID: "order-connector",
            originalToolName: "t\(i)",
            arguments: [:]
        )
    }

    let semaphore = DispatchSemaphore(value: 0)
    var results: [ToolResult] = []

    Task {
        await executor.registerConnector(connector)
        results = await executor.execute(toolCalls: calls)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertEqual(results.count, 5, "Five results returned")
    for (index, result) in results.enumerated() {
        let expectedID = "call_\(index + 1)"
        TestRunner.assertEqual(result.callID, expectedID, "Result \(index + 1) has correct ID")
    }
}

func testBatchSummary() {
    TestRunner.suite("Batch Summary")

    let connector = MockConnector(id: "summary-connector", name: "Summary")
    let executor = MockToolExecutor()

    let calls = [
        ToolCall(id: "s1", toolName: "t1", connectorID: "summary-connector", originalToolName: "t1", arguments: [:]),
        ToolCall(id: "s2", toolName: "t2", connectorID: "summary-connector", originalToolName: "t2", arguments: [:]),
        ToolCall(id: "s3", toolName: "t3", connectorID: "summary-connector", originalToolName: "t3", arguments: [:])
    ]

    let semaphore = DispatchSemaphore(value: 0)
    var batch: BatchToolExecutionResult?

    Task {
        await executor.registerConnector(connector)
        batch = await executor.executeBatch(calls)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(batch, "Batch result returned")
    let summary = batch?.summary ?? ""
    TestRunner.assertTrue(summary.contains("3/3"), "Summary shows 3/3 succeeded")
    TestRunner.assertTrue(summary.contains("0 failed"), "Summary shows 0 failed")
}

func testEmptyBatch() {
    TestRunner.suite("Empty Batch")

    let executor = MockToolExecutor()

    let semaphore = DispatchSemaphore(value: 0)
    var batch: BatchToolExecutionResult?

    Task {
        batch = await executor.executeBatch([])
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(batch, "Batch result returned")
    TestRunner.assertTrue(batch?.results.isEmpty ?? false, "Empty results")
    TestRunner.assertTrue(batch?.allSucceeded ?? false, "Empty batch counts as all succeeded")
    TestRunner.assertEqual(batch?.totalDuration, 0, "Zero duration for empty batch")
}

func testToolCallWithArguments() {
    TestRunner.suite("Tool Call With Arguments")

    let connector = MockConnector(id: "args-connector", name: "Args")
    let executor = MockToolExecutor()

    let args: [String: JSONValue] = [
        "query": .string("test search"),
        "limit": .number(10),
        "include_metadata": .bool(true)
    ]

    let call = ToolCall(
        id: "args_call",
        toolName: "search",
        connectorID: "args-connector",
        originalToolName: "search",
        arguments: args
    )

    let semaphore = DispatchSemaphore(value: 0)
    var result: ToolResult?

    Task {
        await executor.registerConnector(connector)
        result = await executor.execute(call)
        semaphore.signal()
    }
    semaphore.wait()

    TestRunner.assertNotNil(result, "Result returned")
    TestRunner.assertTrue(result?.isSuccess ?? false, "Execution with arguments succeeded")
    TestRunner.assertEqual(result?.toolName, "search", "Tool name preserved")
}

// MARK: - Main

@main
struct ToolExecutorTestsMain {
    static func main() {
        print("🧪 Tool Executor Unit Tests")
        print("==================================================")

        testEmptyToolCalls()
        testSingleToolExecution()
        testMultipleToolExecution()
        testConnectorNotFound()
        testToolFailure()
        testTimeoutHandling()
        testBatchExecution()
        testBatchWithMixedResults()
        testResultDurationTracking()
        testResultsPreserveOrder()
        testBatchSummary()
        testEmptyBatch()
        testToolCallWithArguments()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
