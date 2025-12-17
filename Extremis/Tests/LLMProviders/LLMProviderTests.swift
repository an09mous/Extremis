// MARK: - LLM Provider Unit Tests
// Tests for SSE/NDJSON parsing and provider configuration

import Foundation

// MARK: - Test Utilities

/// Reuse TestRunner from PromptBuilderTests
/// Note: When running standalone, copy TestRunner struct here

// MARK: - SSE Parser Test Helpers

/// Helper to expose internal parsing methods for testing
/// These mirror the private methods in each provider

/// OpenAI SSE Line Parser (mirrors OpenAIProvider.parseSSELine)
func parseOpenAISSELine(_ line: String) -> String? {
    guard line.hasPrefix("data: ") else { return nil }
    let jsonString = String(line.dropFirst(6))
    if jsonString == "[DONE]" { return nil }
    
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let delta = firstChoice["delta"] as? [String: Any],
          let content = delta["content"] as? String else {
        return nil
    }
    return content
}

/// Anthropic SSE Line Parser (mirrors AnthropicProvider.parseSSELine)
func parseAnthropicSSELine(_ line: String) -> String? {
    guard line.hasPrefix("data: ") else { return nil }
    let jsonString = String(line.dropFirst(6))
    
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String,
          type == "content_block_delta",
          let delta = json["delta"] as? [String: Any],
          let deltaType = delta["type"] as? String,
          deltaType == "text_delta",
          let text = delta["text"] as? String else {
        return nil
    }
    return text
}

/// Gemini Stream Line Parser (mirrors GeminiProvider.parseStreamLine)
func parseGeminiStreamLine(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed == "[" || trimmed == "]" || trimmed == "," {
        return nil
    }
    
    var jsonString = trimmed
    if jsonString.hasPrefix(",") {
        jsonString = String(jsonString.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let firstCandidate = candidates.first,
          let content = firstCandidate["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let firstPart = parts.first,
          let text = firstPart["text"] as? String else {
        return nil
    }
    return text
}

/// Ollama SSE Line Parser (same as OpenAI - OpenAI-compatible API)
func parseOllamaSSELine(_ line: String) -> String? {
    return parseOpenAISSELine(line)
}

// MARK: - OpenAI Provider Tests

struct OpenAIProviderTests {
    
    static func runAll() {
        print("\n📦 OpenAI Provider Tests")
        print(String(repeating: "-", count: 40))
        
        testParseValidSSELine()
        testParseSSELineWithDone()
        testParseSSELineEmpty()
        testParseSSELineNoDataPrefix()
        testParseSSELineEmptyDelta()
        testParseSSELineMultipleChunks()
        testParseSSELineWithSpecialCharacters()
        testParseSSELineWithUnicode()
        testParseSSELineWithNewlines()
        testParseSSELineMalformedJSON()
    }
    
    static func testParseValidSSELine() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "Hello", "OpenAI: Parse valid SSE line")
    }
    
    static func testParseSSELineWithDone() {
        let line = "data: [DONE]"
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "OpenAI: Parse [DONE] returns nil")
    }
    
    static func testParseSSELineEmpty() {
        let line = ""
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "OpenAI: Parse empty line returns nil")
    }
    
    static func testParseSSELineNoDataPrefix() {
        let line = #"{"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "OpenAI: Parse line without 'data: ' prefix returns nil")
    }
    
    static func testParseSSELineEmptyDelta() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "OpenAI: Parse empty delta returns nil")
    }
    
    static func testParseSSELineMultipleChunks() {
        let lines = [
            #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"}}]}"#,
            #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":" "}}]}"#,
            #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"World"}}]}"#,
            "data: [DONE]"
        ]
        var result = ""
        for line in lines {
            if let chunk = parseOpenAISSELine(line) {
                result += chunk
            }
        }
        TestRunner.assertEqual(result, "Hello World", "OpenAI: Parse multiple chunks")
    }
    
    static func testParseSSELineWithSpecialCharacters() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello \"World\" & <tag>"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "Hello \"World\" & <tag>", "OpenAI: Parse special characters")
    }
    
    static func testParseSSELineWithUnicode() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello 🌍 世界"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "Hello 🌍 世界", "OpenAI: Parse unicode content")
    }
    
    static func testParseSSELineWithNewlines() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Line1\nLine2"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "Line1\nLine2", "OpenAI: Parse content with newlines")
    }
    
    static func testParseSSELineMalformedJSON() {
        let line = "data: {invalid json}"
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "OpenAI: Parse malformed JSON returns nil")
    }
}

// MARK: - Anthropic Provider Tests

struct AnthropicProviderTests {

    static func runAll() {
        print("\n📦 Anthropic Provider Tests")
        print(String(repeating: "-", count: 40))

        testParseValidContentBlockDelta()
        testParseNonContentBlockDelta()
        testParseMessageStart()
        testParseMessageStop()
        testParseEmptyLine()
        testParseEventLine()
        testParseMultipleDeltas()
        testParseWithSpecialCharacters()
        testParseWithUnicode()
        testParseMalformedJSON()
    }

    static func testParseValidContentBlockDelta() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertEqual(result, "Hello", "Anthropic: Parse valid content_block_delta")
    }

    static func testParseNonContentBlockDelta() {
        let line = #"data: {"type":"message_start","message":{"id":"msg_123"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse message_start returns nil")
    }

    static func testParseMessageStart() {
        let line = #"data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse message_start event returns nil")
    }

    static func testParseMessageStop() {
        let line = #"data: {"type":"message_stop"}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse message_stop returns nil")
    }

    static func testParseEmptyLine() {
        let line = ""
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse empty line returns nil")
    }

    static func testParseEventLine() {
        let line = "event: content_block_delta"
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse event line returns nil")
    }

    static func testParseMultipleDeltas() {
        let lines = [
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" "}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"World"}}"#,
            #"data: {"type":"message_stop"}"#
        ]
        var result = ""
        for line in lines {
            if let chunk = parseAnthropicSSELine(line) {
                result += chunk
            }
        }
        TestRunner.assertEqual(result, "Hello World", "Anthropic: Parse multiple deltas")
    }

    static func testParseWithSpecialCharacters() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"<code>x & y</code>"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertEqual(result, "<code>x & y</code>", "Anthropic: Parse special characters")
    }

    static func testParseWithUnicode() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"こんにちは 🎉"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertEqual(result, "こんにちは 🎉", "Anthropic: Parse unicode content")
    }

    static func testParseMalformedJSON() {
        let line = "data: {not valid json"
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Anthropic: Parse malformed JSON returns nil")
    }
}

// MARK: - Gemini Provider Tests

struct GeminiProviderTests {

    static func runAll() {
        print("\n📦 Gemini Provider Tests")
        print(String(repeating: "-", count: 40))

        testParseValidStreamLine()
        testParseArrayStart()
        testParseArrayEnd()
        testParseComma()
        testParseEmptyLine()
        testParseLineWithLeadingComma()
        testParseMultipleChunks()
        testParseWithSpecialCharacters()
        testParseWithUnicode()
        testParseMalformedJSON()
        testParseWithWhitespace()
    }

    static func testParseValidStreamLine() {
        let line = #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "Hello", "Gemini: Parse valid stream line")
    }

    static func testParseArrayStart() {
        let line = "["
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Gemini: Parse array start returns nil")
    }

    static func testParseArrayEnd() {
        let line = "]"
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Gemini: Parse array end returns nil")
    }

    static func testParseComma() {
        let line = ","
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Gemini: Parse comma returns nil")
    }

    static func testParseEmptyLine() {
        let line = ""
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Gemini: Parse empty line returns nil")
    }

    static func testParseLineWithLeadingComma() {
        let line = #",{"candidates":[{"content":{"parts":[{"text":"World"}]}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "World", "Gemini: Parse line with leading comma")
    }

    static func testParseMultipleChunks() {
        let lines = [
            "[",
            #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#,
            #",{"candidates":[{"content":{"parts":[{"text":" "}]}}]}"#,
            #",{"candidates":[{"content":{"parts":[{"text":"World"}]}}]}"#,
            "]"
        ]
        var result = ""
        for line in lines {
            if let chunk = parseGeminiStreamLine(line) {
                result += chunk
            }
        }
        TestRunner.assertEqual(result, "Hello World", "Gemini: Parse multiple chunks")
    }

    static func testParseWithSpecialCharacters() {
        let line = #"{"candidates":[{"content":{"parts":[{"text":"if (x < 10 && y > 5)"}]}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "if (x < 10 && y > 5)", "Gemini: Parse special characters")
    }

    static func testParseWithUnicode() {
        let line = #"{"candidates":[{"content":{"parts":[{"text":"Привет 🌟"}]}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "Привет 🌟", "Gemini: Parse unicode content")
    }

    static func testParseMalformedJSON() {
        let line = "{candidates: invalid}"
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Gemini: Parse malformed JSON returns nil")
    }

    static func testParseWithWhitespace() {
        let line = "  " + #"{"candidates":[{"content":{"parts":[{"text":"Spaced"}]}}]}"# + "  "
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "Spaced", "Gemini: Parse line with whitespace")
    }
}

// MARK: - Ollama Provider Tests

struct OllamaProviderTests {

    static func runAll() {
        print("\n📦 Ollama Provider Tests")
        print(String(repeating: "-", count: 40))

        // Ollama uses OpenAI-compatible format
        testParseValidSSELine()
        testParseSSELineWithDone()
        testParseSSELineEmpty()
        testParseMultipleChunks()
        testParseWithCodeBlock()
    }

    static func testParseValidSSELine() {
        let line = #"data: {"id":"ollama-123","choices":[{"delta":{"content":"Hello from Ollama"}}]}"#
        let result = parseOllamaSSELine(line)
        TestRunner.assertEqual(result, "Hello from Ollama", "Ollama: Parse valid SSE line")
    }

    static func testParseSSELineWithDone() {
        let line = "data: [DONE]"
        let result = parseOllamaSSELine(line)
        TestRunner.assertNil(result, "Ollama: Parse [DONE] returns nil")
    }

    static func testParseSSELineEmpty() {
        let line = ""
        let result = parseOllamaSSELine(line)
        TestRunner.assertNil(result, "Ollama: Parse empty line returns nil")
    }

    static func testParseMultipleChunks() {
        let lines = [
            #"data: {"id":"ollama-123","choices":[{"delta":{"content":"def "}}]}"#,
            #"data: {"id":"ollama-123","choices":[{"delta":{"content":"hello"}}]}"#,
            #"data: {"id":"ollama-123","choices":[{"delta":{"content":"():"}}]}"#,
            "data: [DONE]"
        ]
        var result = ""
        for line in lines {
            if let chunk = parseOllamaSSELine(line) {
                result += chunk
            }
        }
        TestRunner.assertEqual(result, "def hello():", "Ollama: Parse multiple code chunks")
    }

    static func testParseWithCodeBlock() {
        let line = #"data: {"id":"ollama-123","choices":[{"delta":{"content":"```swift\nlet x = 5\n```"}}]}"#
        let result = parseOllamaSSELine(line)
        TestRunner.assertEqual(result, "```swift\nlet x = 5\n```", "Ollama: Parse code block")
    }
}

// MARK: - Error Handling Tests

struct ErrorHandlingTests {

    static func runAll() {
        print("\n📦 Error Handling Tests")
        print(String(repeating: "-", count: 40))

        testOpenAIMissingChoices()
        testOpenAIMissingDelta()
        testAnthropicWrongDeltaType()
        testGeminiMissingCandidates()
        testGeminiMissingParts()
    }

    static func testOpenAIMissingChoices() {
        let line = #"data: {"id":"chatcmpl-123"}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "Error: OpenAI missing choices returns nil")
    }

    static func testOpenAIMissingDelta() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"message":{"content":"test"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertNil(result, "Error: OpenAI missing delta returns nil")
    }

    static func testAnthropicWrongDeltaType() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertNil(result, "Error: Anthropic wrong delta type returns nil")
    }

    static func testGeminiMissingCandidates() {
        let line = #"{"error":{"message":"Rate limit exceeded"}}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Error: Gemini missing candidates returns nil")
    }

    static func testGeminiMissingParts() {
        let line = #"{"candidates":[{"content":{}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertNil(result, "Error: Gemini missing parts returns nil")
    }
}

// MARK: - Edge Case Tests

struct EdgeCaseTests {

    static func runAll() {
        print("\n📦 Edge Case Tests")
        print(String(repeating: "-", count: 40))

        testOpenAIEmptyContent()
        testAnthropicEmptyText()
        testGeminiEmptyText()
        testLongContent()
        testContentWithJSON()
    }

    static func testOpenAIEmptyContent() {
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":""}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "", "EdgeCase: OpenAI empty content")
    }

    static func testAnthropicEmptyText() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":""}}"#
        let result = parseAnthropicSSELine(line)
        TestRunner.assertEqual(result, "", "EdgeCase: Anthropic empty text")
    }

    static func testGeminiEmptyText() {
        let line = #"{"candidates":[{"content":{"parts":[{"text":""}]}}]}"#
        let result = parseGeminiStreamLine(line)
        TestRunner.assertEqual(result, "", "EdgeCase: Gemini empty text")
    }

    static func testLongContent() {
        let longText = String(repeating: "a", count: 10000)
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"\#(longText)"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, longText, "EdgeCase: Long content (10KB)")
    }

    static func testContentWithJSON() {
        // Content that looks like JSON
        let line = #"data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Here is JSON: {\"key\": \"value\"}"}}]}"#
        let result = parseOpenAISSELine(line)
        TestRunner.assertEqual(result, "Here is JSON: {\"key\": \"value\"}", "EdgeCase: Content containing JSON")
    }
}

// MARK: - TestRunner (Standalone)

/// Simple test framework for running without XCTest
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func assertEqual<T: Equatable>(_ actual: T?, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(String(describing: actual))'"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got '\(value!)'"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected true but got false"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
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

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
    }
}

// MARK: - Main Entry Point

@main
struct LLMProviderTestsMain {
    static func main() {
        print("🧪 LLM Provider Unit Tests")
        print(String(repeating: "=", count: 50))

        TestRunner.reset()

        // Run all test suites
        OpenAIProviderTests.runAll()
        AnthropicProviderTests.runAll()
        GeminiProviderTests.runAll()
        OllamaProviderTests.runAll()
        ErrorHandlingTests.runAll()
        EdgeCaseTests.runAll()

        // Print summary
        TestRunner.printSummary()

        // Exit with appropriate code
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

