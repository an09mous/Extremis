// MARK: - ProcessTransport Unit Tests
// Tests for ProcessTransport JSON filtering, buffer handling, and edge cases

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

// MARK: - JSON Detection Helper (matching ProcessTransport logic)

/// Simulates the JSON detection logic from ProcessTransport.ReadState
func looksLikeJSON(_ data: Data) -> Bool {
    for byte in data {
        // Skip whitespace (space, tab, carriage return)
        if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
            continue
        }
        // Check if it's a JSON start character
        return byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[")
    }
    return false
}

/// Simulates line buffering from ProcessTransport.ReadState
func processLines(from data: Data) -> ([Data], Data) {
    var buffer = data
    var lines: [Data] = []

    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        let lineData = buffer[buffer.startIndex..<newlineIndex]
        buffer = Data(buffer[buffer.index(after: newlineIndex)...])

        if lineData.isEmpty { continue }

        if looksLikeJSON(Data(lineData)) {
            lines.append(Data(lineData))
        }
    }

    return (lines, buffer)
}

// MARK: - Test: JSON Detection

func testJSONDetection() {
    TestRunner.suite("JSON Detection Tests")

    // Test 1: Valid JSON object starting with {
    let jsonObject = "{\"key\": \"value\"}".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonObject), "Detects JSON object starting with {")

    // Test 2: Valid JSON array starting with [
    let jsonArray = "[1, 2, 3]".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonArray), "Detects JSON array starting with [")

    // Test 3: JSON with leading spaces
    let jsonWithSpaces = "  {\"key\": \"value\"}".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonWithSpaces), "Detects JSON with leading spaces")

    // Test 4: JSON with leading tabs
    let jsonWithTabs = "\t\t[1, 2]".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonWithTabs), "Detects JSON with leading tabs")

    // Test 5: JSON with mixed whitespace
    let jsonMixedWhitespace = "  \t  {\"test\": true}".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonMixedWhitespace), "Detects JSON with mixed whitespace")

    // Test 6: JSON with carriage return
    let jsonWithCR = "\r{\"test\": 1}".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonWithCR), "Detects JSON with leading carriage return")

    // Test 7: Plain text (not JSON)
    let plainText = "Hello, World!".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(plainText), "Rejects plain text")

    // Test 8: Status message from MCP server
    let statusMessage = "Starting server...".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(statusMessage), "Rejects server status message")

    // Test 9: Empty data
    let emptyData = Data()
    TestRunner.assertFalse(looksLikeJSON(emptyData), "Rejects empty data")

    // Test 10: Only whitespace
    let onlyWhitespace = "   \t  ".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(onlyWhitespace), "Rejects whitespace-only data")

    // Test 11: Number (not JSON object/array)
    let numberOnly = "42".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(numberOnly), "Rejects bare number")

    // Test 12: String that looks like it could be JSON but isn't object/array
    let falsePositive = "\"just a string\"".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(falsePositive), "Rejects bare JSON string")

    // Test 13: Nested JSON-RPC message
    let jsonRPC = "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{}}".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(jsonRPC), "Detects JSON-RPC message")

    // Test 14: JSON with BOM (unlikely but possible)
    // UTF-8 BOM is EF BB BF, which is not whitespace
    let jsonWithBOM = Data([0xEF, 0xBB, 0xBF]) + "{\"key\":1}".data(using: .utf8)!
    TestRunner.assertFalse(looksLikeJSON(jsonWithBOM), "Rejects JSON with BOM (BOM is not whitespace)")
}

// MARK: - Test: Line Buffering

func testLineBuffering() {
    TestRunner.suite("Line Buffering Tests")

    // Test 1: Single complete line
    let singleLine = "{\"test\":1}\n".data(using: .utf8)!
    let (lines1, remaining1) = processLines(from: singleLine)
    TestRunner.assertEqual(lines1.count, 1, "Processes single complete line")
    TestRunner.assertEqual(remaining1.count, 0, "No remaining data after complete line")

    // Test 2: Multiple complete lines
    let multiLine = "{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".data(using: .utf8)!
    let (lines2, remaining2) = processLines(from: multiLine)
    TestRunner.assertEqual(lines2.count, 3, "Processes multiple complete lines")
    TestRunner.assertEqual(remaining2.count, 0, "No remaining data after multiple lines")

    // Test 3: Incomplete line (no newline)
    let incompleteLine = "{\"test\":1}".data(using: .utf8)!
    let (lines3, remaining3) = processLines(from: incompleteLine)
    TestRunner.assertEqual(lines3.count, 0, "Does not process incomplete line")
    TestRunner.assertEqual(remaining3.count, incompleteLine.count, "Keeps incomplete line in buffer")

    // Test 4: Complete + incomplete line
    let mixedLines = "{\"a\":1}\n{\"b\":2".data(using: .utf8)!
    let (lines4, remaining4) = processLines(from: mixedLines)
    TestRunner.assertEqual(lines4.count, 1, "Processes only complete line")
    TestRunner.assertTrue(remaining4.count > 0, "Keeps incomplete line in buffer")

    // Test 5: Empty lines filtered out
    let withEmpty = "{\"a\":1}\n\n{\"b\":2}\n".data(using: .utf8)!
    let (lines5, _) = processLines(from: withEmpty)
    TestRunner.assertEqual(lines5.count, 2, "Filters empty lines")

    // Test 6: Non-JSON lines filtered out
    let withNonJSON = "{\"a\":1}\nStatus: OK\n{\"b\":2}\n".data(using: .utf8)!
    let (lines6, _) = processLines(from: withNonJSON)
    TestRunner.assertEqual(lines6.count, 2, "Filters non-JSON lines")

    // Test 7: Only non-JSON content
    let onlyNonJSON = "Server starting...\nInitialization complete\n".data(using: .utf8)!
    let (lines7, _) = processLines(from: onlyNonJSON)
    TestRunner.assertEqual(lines7.count, 0, "Processes no lines when all are non-JSON")

    // Test 8: JSON with leading whitespace
    let jsonWithWhitespace = "  {\"a\":1}\n\t{\"b\":2}\n".data(using: .utf8)!
    let (lines8, _) = processLines(from: jsonWithWhitespace)
    TestRunner.assertEqual(lines8.count, 2, "Processes JSON with leading whitespace")

    // Test 9: Very long line
    let longValue = String(repeating: "x", count: 10000)
    let longLine = "{\"data\":\"\(longValue)\"}\n".data(using: .utf8)!
    let (lines9, _) = processLines(from: longLine)
    TestRunner.assertEqual(lines9.count, 1, "Handles very long lines")

    // Test 10: Line with only whitespace
    let whitespaceOnly = "   \n{\"a\":1}\n".data(using: .utf8)!
    let (lines10, _) = processLines(from: whitespaceOnly)
    // Whitespace-only line doesn't look like JSON, so filtered
    TestRunner.assertEqual(lines10.count, 1, "Filters whitespace-only lines")
}

// MARK: - Test: ConnectorTool Naming Edge Cases

/// Simulates ConnectorTool name generation
func generateToolName(connectorName: String, originalName: String) -> String {
    let prefix = connectorName
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "-", with: "_")
        .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    return "\(prefix)_\(originalName)"
}

func testConnectorToolNaming() {
    TestRunner.suite("ConnectorTool Naming Edge Cases")

    // Test 1: Simple connector name
    TestRunner.assertEqual(
        generateToolName(connectorName: "github", originalName: "search"),
        "github_search",
        "Simple connector name generates correct tool name"
    )

    // Test 2: Connector name with spaces
    TestRunner.assertEqual(
        generateToolName(connectorName: "My Server", originalName: "query"),
        "my_server_query",
        "Connector name with spaces converts to underscores"
    )

    // Test 3: Connector name with hyphens
    TestRunner.assertEqual(
        generateToolName(connectorName: "web-search", originalName: "find"),
        "web_search_find",
        "Connector name with hyphens converts to underscores"
    )

    // Test 4: Connector name with special characters
    TestRunner.assertEqual(
        generateToolName(connectorName: "My@Server#1!", originalName: "test"),
        "myserver1_test",
        "Connector name with special chars filters them out"
    )

    // Test 5: Connector name with numbers
    TestRunner.assertEqual(
        generateToolName(connectorName: "server2", originalName: "action"),
        "server2_action",
        "Connector name with numbers preserves them"
    )

    // Test 6: Mixed case connector name
    TestRunner.assertEqual(
        generateToolName(connectorName: "MyMCPServer", originalName: "run"),
        "mymcpserver_run",
        "Mixed case connector name lowercased"
    )

    // Test 7: Connector name with leading/trailing spaces
    TestRunner.assertEqual(
        generateToolName(connectorName: "  spaced  ", originalName: "call"),
        "__spaced___call",
        "Leading/trailing spaces become underscores"
    )

    // Test 8: Unicode connector name (Swift's isLetter includes Unicode letters)
    TestRunner.assertEqual(
        generateToolName(connectorName: "サーバー", originalName: "action"),
        "サーバー_action",
        "Unicode letters preserved (Swift isLetter includes all Unicode letters)"
    )

    // Test 9: Empty connector name (edge case)
    TestRunner.assertEqual(
        generateToolName(connectorName: "", originalName: "tool"),
        "_tool",
        "Empty connector name results in underscore prefix"
    )

    // Test 10: Connector name with only special chars
    TestRunner.assertEqual(
        generateToolName(connectorName: "@#$%", originalName: "exec"),
        "_exec",
        "All-special-char connector name filtered to empty"
    )
}

// MARK: - Test: Tool Lookup Edge Cases

struct MockConnectorTool {
    let originalName: String
    let connectorID: String
    let connectorName: String

    var name: String {
        generateToolName(connectorName: connectorName, originalName: originalName)
    }
}

func testToolLookup() {
    TestRunner.suite("Tool Lookup Edge Cases")

    let tools = [
        MockConnectorTool(originalName: "search", connectorID: "github-1", connectorName: "github"),
        MockConnectorTool(originalName: "search", connectorID: "gitlab-1", connectorName: "gitlab"),
        MockConnectorTool(originalName: "create_issue", connectorID: "github-1", connectorName: "github"),
        MockConnectorTool(originalName: "list_repos", connectorID: "github-1", connectorName: "github"),
    ]

    // Test 1: Find by disambiguated name
    let found1 = tools.first { $0.name == "github_search" }
    TestRunner.assertNotNil(found1, "Finds tool by disambiguated name")
    TestRunner.assertEqual(found1?.connectorID, "github-1", "Found correct tool by name")

    // Test 2: Find by original name (ambiguous - multiple matches)
    let foundByOriginal = tools.filter { $0.originalName == "search" }
    TestRunner.assertEqual(foundByOriginal.count, 2, "Multiple tools with same original name")

    // Test 3: Find by original name + connector ID (unique)
    let found3 = tools.first { $0.originalName == "search" && $0.connectorID == "gitlab-1" }
    TestRunner.assertNotNil(found3, "Finds tool by original name + connector ID")
    TestRunner.assertEqual(found3?.connectorName, "gitlab", "Found correct tool")

    // Test 4: Non-existent tool
    let notFound = tools.first { $0.name == "nonexistent_tool" }
    TestRunner.assertNil(notFound, "Returns nil for non-existent tool")

    // Test 5: Name collision detection
    let originalNames = tools.map { $0.originalName }
    let hasCollisions = originalNames.count != Set(originalNames).count
    TestRunner.assertTrue(hasCollisions, "Detects name collisions")

    // Test 6: Tools for specific connector
    let githubTools = tools.filter { $0.connectorID == "github-1" }
    TestRunner.assertEqual(githubTools.count, 3, "Finds all tools for connector")

    // Test 7: Empty tool list
    let emptyTools: [MockConnectorTool] = []
    let emptyResult = emptyTools.first { $0.name == "any" }
    TestRunner.assertNil(emptyResult, "Handles empty tool list")
}

// MARK: - Test: Timeout Edge Cases

func testTimeoutConstants() {
    TestRunner.suite("Timeout Constants Tests")

    // Simulating ConnectorConstants values
    let connectionTimeout: TimeInterval = 10.0
    let toolExecutionTimeout: TimeInterval = 60.0
    let toolDiscoveryTimeout: TimeInterval = 3.0
    let maxReconnectAttempts = 3
    let reconnectBaseDelay: TimeInterval = 1.0

    // Test 1: Connection timeout is reasonable
    TestRunner.assertTrue(connectionTimeout >= 5.0, "Connection timeout is at least 5 seconds")
    TestRunner.assertTrue(connectionTimeout <= 30.0, "Connection timeout is at most 30 seconds")

    // Test 2: Tool execution timeout is reasonable for complex tools
    TestRunner.assertTrue(toolExecutionTimeout >= 30.0, "Tool execution timeout allows for slow tools")
    TestRunner.assertTrue(toolExecutionTimeout <= 300.0, "Tool execution timeout has upper bound")

    // Test 3: Tool discovery is quick
    TestRunner.assertTrue(toolDiscoveryTimeout <= connectionTimeout, "Tool discovery faster than connection")

    // Test 4: Reconnect attempts are bounded
    TestRunner.assertTrue(maxReconnectAttempts >= 1, "At least 1 reconnect attempt")
    TestRunner.assertTrue(maxReconnectAttempts <= 10, "Reconnect attempts bounded")

    // Test 5: Exponential backoff calculation
    let delays = (1...maxReconnectAttempts).map { attempt in
        reconnectBaseDelay * pow(2.0, Double(attempt - 1))
    }
    TestRunner.assertEqual(delays[0], 1.0, "First retry delay is 1 second")
    TestRunner.assertEqual(delays[1], 2.0, "Second retry delay is 2 seconds")
    TestRunner.assertEqual(delays[2], 4.0, "Third retry delay is 4 seconds")

    // Test 6: Total retry time is reasonable
    let totalRetryTime = delays.reduce(0, +)
    TestRunner.assertTrue(totalRetryTime < 60.0, "Total retry time under 1 minute")
}

// MARK: - Test: Error Classification

func testErrorClassification() {
    TestRunner.suite("Error Classification Tests")

    // Simulating ConnectorError.isRetryable
    func isRetryable(_ errorType: String) -> Bool {
        switch errorType {
        case "connectionTimeout", "toolExecutionTimeout", "connectionFailed", "processSpawnFailed":
            return true
        default:
            return false
        }
    }

    // Test 1: Timeout errors are retryable
    TestRunner.assertTrue(isRetryable("connectionTimeout"), "Connection timeout is retryable")
    TestRunner.assertTrue(isRetryable("toolExecutionTimeout"), "Tool execution timeout is retryable")

    // Test 2: Connection failures are retryable
    TestRunner.assertTrue(isRetryable("connectionFailed"), "Connection failed is retryable")
    TestRunner.assertTrue(isRetryable("processSpawnFailed"), "Process spawn failed is retryable")

    // Test 3: Other errors are not retryable
    TestRunner.assertFalse(isRetryable("notConnected"), "Not connected is not retryable")
    TestRunner.assertFalse(isRetryable("toolNotFound"), "Tool not found is not retryable")
    TestRunner.assertFalse(isRetryable("invalidResponse"), "Invalid response is not retryable")
    TestRunner.assertFalse(isRetryable("protocolError"), "Protocol error is not retryable")
    TestRunner.assertFalse(isRetryable("authenticationRequired"), "Auth required is not retryable")
}

// MARK: - Test: ConnectorState Transitions

func testConnectorStateTransitions() {
    TestRunner.suite("ConnectorState Transition Tests")

    enum ConnectorState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // Test 1: Initial state is disconnected
    var state: ConnectorState = .disconnected
    TestRunner.assertFalse(state.isConnected, "Initial state is not connected")

    // Test 2: Connecting transition
    state = .connecting
    TestRunner.assertFalse(state.isConnected, "Connecting state is not connected")

    // Test 3: Connected transition
    state = .connected
    TestRunner.assertTrue(state.isConnected, "Connected state is connected")

    // Test 4: Error transition
    state = .error("Connection refused")
    TestRunner.assertFalse(state.isConnected, "Error state is not connected")

    // Test 5: Error states with same message are equal
    let error1 = ConnectorState.error("timeout")
    let error2 = ConnectorState.error("timeout")
    TestRunner.assertTrue(error1 == error2, "Same error messages are equal")

    // Test 6: Error states with different messages are not equal
    let error3 = ConnectorState.error("timeout")
    let error4 = ConnectorState.error("refused")
    TestRunner.assertFalse(error3 == error4, "Different error messages are not equal")
}

// MARK: - Test: JSON-RPC Message Format

func testJSONRPCMessageFormat() {
    TestRunner.suite("JSON-RPC Message Format Tests")

    // Test 1: Valid JSON-RPC request
    let request = """
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    """.data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(request), "Valid JSON-RPC request detected")

    // Test 2: Valid JSON-RPC response
    let response = """
    {"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"test"}}}
    """.data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(response), "Valid JSON-RPC response detected")

    // Test 3: JSON-RPC notification (no id)
    let notification = """
    {"jsonrpc":"2.0","method":"notifications/progress","params":{}}
    """.data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(notification), "JSON-RPC notification detected")

    // Test 4: JSON-RPC error response
    let errorResponse = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid Request"}}
    """.data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(errorResponse), "JSON-RPC error response detected")

    // Test 5: Malformed but still JSON
    let malformed = "{\"incomplete".data(using: .utf8)!
    TestRunner.assertTrue(looksLikeJSON(malformed), "Malformed JSON still detected as JSON-like")
}

// MARK: - Test: Data Slicing Edge Cases

func testDataSlicing() {
    TestRunner.suite("Data Slicing Edge Cases")

    // Test 1: Process data at boundaries
    let data = "{\"a\":1}\n{\"b\":2}\n".data(using: .utf8)!
    let (lines, remaining) = processLines(from: data)
    TestRunner.assertEqual(lines.count, 2, "Processes lines at data boundaries")
    TestRunner.assertEqual(remaining.count, 0, "No remaining data")

    // Test 2: Single byte at a time simulation
    var buffer = Data()
    var allLines: [Data] = []
    for byte in "{\"a\":1}\n".data(using: .utf8)! {
        buffer.append(byte)
        let (lines, remaining) = processLines(from: buffer)
        allLines.append(contentsOf: lines)
        buffer = remaining
    }
    TestRunner.assertEqual(allLines.count, 1, "Processes single bytes correctly")

    // Test 3: Large chunk followed by small chunk
    let chunk1 = "{\"data\":\"".data(using: .utf8)!
    let chunk2 = "value\"}\n".data(using: .utf8)!
    var combined = chunk1
    let (lines1, remaining1) = processLines(from: combined)
    TestRunner.assertEqual(lines1.count, 0, "Incomplete line not processed")
    combined = remaining1 + chunk2
    let (lines2, _) = processLines(from: combined)
    TestRunner.assertEqual(lines2.count, 1, "Complete line processed after chunks combined")
}

// MARK: - Main

@main
struct ProcessTransportTests {
    static func main() {
        print("ProcessTransport Unit Tests")
        print("==================================================")

        testJSONDetection()
        testLineBuffering()
        testConnectorToolNaming()
        testToolLookup()
        testTimeoutConstants()
        testErrorClassification()
        testConnectorStateTransitions()
        testJSONRPCMessageFormat()
        testDataSlicing()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
