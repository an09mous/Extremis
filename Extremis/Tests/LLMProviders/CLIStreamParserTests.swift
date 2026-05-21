// MARK: - CLIStreamParser Unit Tests
// Tests for JSONL stream event parsing from Claude Code CLI
// Standalone test file — can be compiled and run independently

import Foundation

// MARK: - Test Infrastructure

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(String, String)] = []

    static func assertTrue(_ condition: Bool, _ name: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected true, got false"))
            print("  ✗ \(name)")
        }
    }

    static func assertFalse(_ condition: Bool, _ name: String) {
        assertTrue(!condition, name)
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected \(expected), got \(actual)"))
            print("  ✗ \(name) — Expected \(expected), got \(actual)")
        }
    }

    static func assertNil<T>(_ value: T?, _ name: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected nil, got \(value!)"))
            print("  ✗ \(name) — Expected nil, got \(value!)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ name: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected non-nil"))
            print("  ✗ \(name) — Expected non-nil")
        }
    }

    static func suite(_ name: String) {
        print("\n📦 \(name)")
        print(String(repeating: "-", count: 50))
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed Tests:")
            for (name, message) in failedTests {
                print("  • \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - Minimal type stubs for standalone compilation

struct AnyCodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else { value = "" }
    }
}

struct CLIRateLimitInfo: Decodable {
    let status: String?
    let resetsAt: Int?
    let rateLimitType: String?
}

struct CLIMessageInfo: Decodable {
    let model: String?
    let role: String?
}

struct CLIAssistantContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}

struct CLIAssistantMessage: Decodable {
    let model: String?
    let role: String?
    let content: [CLIAssistantContentBlock]?
}

struct ContentBlock: Decodable {
    let type: String
    let id: String?
    let name: String?
    let toolUseId: String?
    let content: String?
    enum CodingKeys: String, CodingKey {
        case type, id, name, content
        case toolUseId = "tool_use_id"
    }
}

struct ContentDelta: Decodable {
    let type: String
    let text: String?
    let partialJson: String?
    let thinking: String?
    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
    }
}

struct StreamEventPayload: Decodable {
    let type: String
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: ContentDelta?
    let message: CLIMessageInfo?
    enum CodingKeys: String, CodingKey {
        case type, index, delta, message
        case contentBlock = "content_block"
    }
}

struct CLIStreamEvent: Decodable {
    let type: String
    let subtype: String?
    let sessionId: String?
    let totalCostUsd: Double?
    let event: StreamEventPayload?
    let tools: [String]?
    let message: CLIAssistantMessage?
    let error: String?
    let durationMs: Int?
    let rateLimitInfo: CLIRateLimitInfo?
    enum CodingKeys: String, CodingKey {
        case type, subtype, event, tools, message, error
        case sessionId = "session_id"
        case totalCostUsd = "total_cost_usd"
        case durationMs = "duration_ms"
        case rateLimitInfo = "rate_limit_info"
    }
}

enum ParsedCLIEvent {
    case initialized(sessionId: String?, tools: [String])
    case textDelta(String)
    case thinkingDelta(String)
    case toolUseStart(id: String, name: String)
    case toolInputDelta(index: Int, partialJson: String)
    case toolResult(toolUseId: String, content: String)
    case contentBlockStop(index: Int)
    case messageStop
    case resultSuccess(sessionId: String?, costUsd: Double?, durationMs: Int?)
    case resultError(error: String)
    case rateLimit(status: String?, resetsAt: Int?, type: String?)
    case assistantMessage(content: String)
}

final class CLIStreamParser {
    private let decoder = JSONDecoder()

    func parseLine(_ line: String) -> ParsedCLIEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let event = try? decoder.decode(CLIStreamEvent.self, from: data) else { return nil }
        return mapEvent(event)
    }

    private func mapEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        switch event.type {
        case "system":
            guard event.subtype == "init" else { return nil }
            return .initialized(sessionId: event.sessionId, tools: event.tools ?? [])
        case "stream_event":
            return mapStreamEvent(event)
        case "assistant":
            guard let message = event.message else { return nil }
            let text = message.content?.filter { $0.type == "text" }.compactMap { $0.text }.joined(separator: "") ?? ""
            guard !text.isEmpty else { return nil }
            return .assistantMessage(content: text)
        case "result":
            switch event.subtype {
            case "success":
                return .resultSuccess(sessionId: event.sessionId, costUsd: event.totalCostUsd, durationMs: event.durationMs)
            case "error":
                return .resultError(error: event.error ?? "Unknown error")
            default: return nil
            }
        case "rate_limit_event":
            return .rateLimit(status: event.rateLimitInfo?.status, resetsAt: event.rateLimitInfo?.resetsAt, type: event.rateLimitInfo?.rateLimitType)
        default: return nil
        }
    }

    private func mapStreamEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        guard let payload = event.event else { return nil }
        switch payload.type {
        case "content_block_start":
            guard let block = payload.contentBlock else { return nil }
            if block.type == "tool_use", let id = block.id, let name = block.name {
                return .toolUseStart(id: id, name: name)
            }
            if block.type == "tool_result", let toolUseId = block.toolUseId {
                return .toolResult(toolUseId: toolUseId, content: block.content ?? "")
            }
            return nil
        case "content_block_delta":
            guard let delta = payload.delta else { return nil }
            switch delta.type {
            case "text_delta":
                if let t = delta.text { return .textDelta(t) }
            case "thinking_delta":
                if let t = delta.thinking { return .thinkingDelta(t) }
            case "input_json_delta":
                if let j = delta.partialJson, let idx = payload.index { return .toolInputDelta(index: idx, partialJson: j) }
            default: break
            }
            return nil
        case "content_block_stop":
            return .contentBlockStop(index: payload.index ?? 0)
        case "message_stop":
            return .messageStop
        default: return nil
        }
    }
}

// MARK: - Tests

func testEmptyAndMalformedLines() {
    TestRunner.suite("Empty and Malformed Lines")
    let parser = CLIStreamParser()

    TestRunner.assertNil(parser.parseLine(""), "Empty line returns nil")
    TestRunner.assertNil(parser.parseLine("   "), "Whitespace-only line returns nil")
    TestRunner.assertNil(parser.parseLine("not json at all"), "Non-JSON returns nil")
    TestRunner.assertNil(parser.parseLine("{invalid json}"), "Invalid JSON returns nil")
    TestRunner.assertNil(parser.parseLine("{\"type\": \"unknown_type\"}"), "Unknown type returns nil")
}

func testSystemInitEvent() {
    TestRunner.suite("System Init Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"system","subtype":"init","session_id":"abc123","tools":["Bash","Read","Edit"]}"#
    let result = parser.parseLine(line)

    if case .initialized(let sessionId, let tools) = result {
        TestRunner.assertEqual(sessionId, "abc123", "Session ID parsed")
        TestRunner.assertEqual(tools.count, 3, "Three tools parsed")
        TestRunner.assertEqual(tools[0], "Bash", "First tool is Bash")
        TestRunner.assertEqual(tools[1], "Read", "Second tool is Read")
        TestRunner.assertEqual(tools[2], "Edit", "Third tool is Edit")
    } else {
        TestRunner.assertTrue(false, "Expected initialized event, got \(String(describing: result))")
    }

    // Non-init system event
    let statusLine = #"{"type":"system","subtype":"status","session_id":"abc123"}"#
    TestRunner.assertNil(parser.parseLine(statusLine), "Non-init system event returns nil")
}

func testTextDeltaEvent() {
    TestRunner.suite("Text Delta Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello "}}}"#
    let result = parser.parseLine(line)

    if case .textDelta(let text) = result {
        TestRunner.assertEqual(text, "Hello ", "Text delta content parsed")
    } else {
        TestRunner.assertTrue(false, "Expected textDelta event")
    }
}

func testThinkingDeltaEvent() {
    TestRunner.suite("Thinking Delta Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The user is asking..."}}}"#
    let result = parser.parseLine(line)

    if case .thinkingDelta(let text) = result {
        TestRunner.assertEqual(text, "The user is asking...", "Thinking delta content parsed")
    } else {
        TestRunner.assertTrue(false, "Expected thinkingDelta event")
    }
}

func testToolUseStartEvent() {
    TestRunner.suite("Tool Use Start Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_123","name":"Bash","input":{}}}}"#
    let result = parser.parseLine(line)

    if case .toolUseStart(let id, let name) = result {
        TestRunner.assertEqual(id, "tool_123", "Tool use ID parsed")
        TestRunner.assertEqual(name, "Bash", "Tool name parsed")
    } else {
        TestRunner.assertTrue(false, "Expected toolUseStart event")
    }
}

func testToolInputDeltaEvent() {
    TestRunner.suite("Tool Input Delta Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"command\":\"ls"}}}"#
    let result = parser.parseLine(line)

    if case .toolInputDelta(let index, let json) = result {
        TestRunner.assertEqual(index, 1, "Index parsed")
        TestRunner.assertEqual(json, #"{"command":"ls"#, "Partial JSON parsed")
    } else {
        TestRunner.assertTrue(false, "Expected toolInputDelta event")
    }
}

func testToolResultEvent() {
    TestRunner.suite("Tool Result Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":2,"content_block":{"type":"tool_result","tool_use_id":"tool_123","content":"file1.txt\nfile2.txt"}}}"#
    let result = parser.parseLine(line)

    if case .toolResult(let toolUseId, let content) = result {
        TestRunner.assertEqual(toolUseId, "tool_123", "Tool use ID parsed")
        TestRunner.assertEqual(content, "file1.txt\nfile2.txt", "Tool result content parsed")
    } else {
        TestRunner.assertTrue(false, "Expected toolResult event")
    }
}

func testContentBlockStopEvent() {
    TestRunner.suite("Content Block Stop Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"content_block_stop","index":1}}"#
    let result = parser.parseLine(line)

    if case .contentBlockStop(let index) = result {
        TestRunner.assertEqual(index, 1, "Block index parsed")
    } else {
        TestRunner.assertTrue(false, "Expected contentBlockStop event")
    }
}

func testMessageStopEvent() {
    TestRunner.suite("Message Stop Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"message_stop"}}"#
    let result = parser.parseLine(line)

    if case .messageStop = result {
        TestRunner.assertTrue(true, "Message stop parsed")
    } else {
        TestRunner.assertTrue(false, "Expected messageStop event")
    }
}

func testResultSuccessEvent() {
    TestRunner.suite("Result Success Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"result","subtype":"success","session_id":"abc123","total_cost_usd":0.001,"duration_ms":2500}"#
    let result = parser.parseLine(line)

    if case .resultSuccess(let sessionId, let cost, let duration) = result {
        TestRunner.assertEqual(sessionId, "abc123", "Session ID parsed")
        TestRunner.assertEqual(cost, 0.001, "Cost parsed")
        TestRunner.assertEqual(duration, 2500, "Duration parsed")
    } else {
        TestRunner.assertTrue(false, "Expected resultSuccess event")
    }
}

func testResultErrorEvent() {
    TestRunner.suite("Result Error Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"result","subtype":"error","error":"Not logged in"}"#
    let result = parser.parseLine(line)

    if case .resultError(let error) = result {
        TestRunner.assertEqual(error, "Not logged in", "Error message parsed")
    } else {
        TestRunner.assertTrue(false, "Expected resultError event")
    }
}

func testRateLimitEvent() {
    TestRunner.suite("Rate Limit Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1779373200,"rateLimitType":"five_hour"}}"#
    let result = parser.parseLine(line)

    if case .rateLimit(let status, let resetsAt, let type) = result {
        TestRunner.assertEqual(status, "allowed", "Rate limit status parsed")
        TestRunner.assertEqual(resetsAt, 1779373200, "Resets at parsed")
        TestRunner.assertEqual(type, "five_hour", "Rate limit type parsed")
    } else {
        TestRunner.assertTrue(false, "Expected rateLimit event")
    }
}

func testAssistantMessageEvent() {
    TestRunner.suite("Assistant Message Event")
    let parser = CLIStreamParser()

    let line = #"{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","role":"assistant","content":[{"type":"text","text":"Hello!"}]}}"#
    let result = parser.parseLine(line)

    if case .assistantMessage(let content) = result {
        TestRunner.assertEqual(content, "Hello!", "Assistant message text extracted")
    } else {
        TestRunner.assertTrue(false, "Expected assistantMessage event")
    }

    // Empty content should return nil
    let emptyLine = #"{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","role":"assistant","content":[]}}"#
    TestRunner.assertNil(parser.parseLine(emptyLine), "Empty assistant content returns nil")
}

func testMessageStartEvent() {
    TestRunner.suite("Message Start Event (ignored)")
    let parser = CLIStreamParser()

    let line = #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","role":"assistant"}}}"#
    // message_start is not mapped to any ParsedCLIEvent — returns nil
    TestRunner.assertNil(parser.parseLine(line), "message_start returns nil (not mapped)")
}

func testMultipleTextDeltas() {
    TestRunner.suite("Multiple Text Deltas (streaming sequence)")
    let parser = CLIStreamParser()

    let lines = [
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"!"}}}"#,
    ]

    var accumulated = ""
    for line in lines {
        if case .textDelta(let text) = parser.parseLine(line) {
            accumulated += text
        }
    }

    TestRunner.assertEqual(accumulated, "Hello world!", "Multiple text deltas accumulate correctly")
}

// MARK: - Main

@main
struct CLIStreamParserTests {
    static func main() {
        testEmptyAndMalformedLines()
        testSystemInitEvent()
        testTextDeltaEvent()
        testThinkingDeltaEvent()
        testToolUseStartEvent()
        testToolInputDeltaEvent()
        testToolResultEvent()
        testContentBlockStopEvent()
        testMessageStopEvent()
        testResultSuccessEvent()
        testResultErrorEvent()
        testRateLimitEvent()
        testAssistantMessageEvent()
        testMessageStartEvent()
        testMultipleTextDeltas()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
