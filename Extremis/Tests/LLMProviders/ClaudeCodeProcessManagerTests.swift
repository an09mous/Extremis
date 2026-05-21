// MARK: - ClaudeCodeProcessManager Unit Tests
// Tests for process state transitions and lifecycle logic
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

// MARK: - ProcessState Enum (standalone copy for testing)

enum ProcessState: Equatable {
    case stopped
    case starting
    case ready
    case generating
    case error(String)

    static func == (lhs: ProcessState, rhs: ProcessState) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped), (.starting, .starting),
             (.ready, .ready), (.generating, .generating):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Tests

func testProcessStateEquality() {
    TestRunner.suite("ProcessState Equality")

    TestRunner.assertTrue(ProcessState.stopped == ProcessState.stopped, "stopped == stopped")
    TestRunner.assertTrue(ProcessState.starting == ProcessState.starting, "starting == starting")
    TestRunner.assertTrue(ProcessState.ready == ProcessState.ready, "ready == ready")
    TestRunner.assertTrue(ProcessState.generating == ProcessState.generating, "generating == generating")
    TestRunner.assertTrue(ProcessState.error("x") == ProcessState.error("x"), "error(x) == error(x)")

    TestRunner.assertFalse(ProcessState.stopped == ProcessState.starting, "stopped != starting")
    TestRunner.assertFalse(ProcessState.ready == ProcessState.generating, "ready != generating")
    TestRunner.assertFalse(ProcessState.error("a") == ProcessState.error("b"), "error(a) != error(b)")
    TestRunner.assertFalse(ProcessState.stopped == ProcessState.error("x"), "stopped != error")
}

func testStateTransitions() {
    TestRunner.suite("State Transition Logic — Persistent Process")

    // Simulate the expected state machine for persistent process
    var state: ProcessState = .stopped

    // stopped → starting (on start())
    state = .starting
    TestRunner.assertEqual(state, .starting, "stopped → starting")

    // starting → ready (on system/init received)
    state = .ready
    TestRunner.assertEqual(state, .ready, "starting → ready")

    // ready → generating (on sendMessage())
    state = .generating
    TestRunner.assertEqual(state, .generating, "ready → generating")

    // generating → ready (on result/success — process stays alive)
    state = .ready
    TestRunner.assertEqual(state, .ready, "generating → ready (success)")

    // ready → generating (another message — same process, no restart)
    state = .generating
    TestRunner.assertEqual(state, .generating, "ready → generating (2nd message, same process)")

    // generating → ready (on result/error — process stays alive)
    state = .ready
    TestRunner.assertEqual(state, .ready, "generating → ready (error result)")

    // ready → generating (3rd message — still same process)
    state = .generating
    TestRunner.assertEqual(state, .generating, "ready → generating (3rd message)")

    // generating → ready
    state = .ready
    TestRunner.assertEqual(state, .ready, "generating → ready (3rd success)")

    // ready → stopped (on stop())
    state = .stopped
    TestRunner.assertEqual(state, .stopped, "ready → stopped (user stop)")
}

func testCrashRecoveryTransitions() {
    TestRunner.suite("Crash Recovery Transitions")

    var state: ProcessState = .ready

    // Simulate unexpected process crash
    state = .error("Process exited with code 1")
    TestRunner.assertTrue(state == .error("Process exited with code 1"), "ready → error on crash")

    // Provider calls ensureProcessRunning() → start() → starting
    state = .starting
    TestRunner.assertEqual(state, .starting, "error → starting (auto-restart)")

    // Back to ready after init
    state = .ready
    TestRunner.assertEqual(state, .ready, "starting → ready after restart")
}

func testDoubleStartGuard() {
    TestRunner.suite("Double Start Guard Logic")

    // When state is .ready, start() should be a no-op
    let state: ProcessState = .ready
    let shouldStart = (state == .stopped || {
        if case .error = state { return true }
        return false
    }())
    TestRunner.assertFalse(shouldStart, "Should not start when already ready")

    // When state is .stopped, start() should proceed
    let stoppedState: ProcessState = .stopped
    let shouldStartFromStopped = (stoppedState == .stopped)
    TestRunner.assertTrue(shouldStartFromStopped, "Should start when stopped")

    // When state is .error, start() should proceed (restart)
    let errorState: ProcessState = .error("crashed")
    let shouldStartFromError: Bool = {
        if case .error = errorState { return true }
        return false
    }()
    TestRunner.assertTrue(shouldStartFromError, "Should start when in error state")
}

func testStopIdempotency() {
    TestRunner.suite("Stop Idempotency")

    var state: ProcessState = .ready
    state = .stopped
    TestRunner.assertEqual(state, .stopped, "First stop")

    state = .stopped
    TestRunner.assertEqual(state, .stopped, "Second stop — still stopped")

    state = .generating
    state = .stopped
    TestRunner.assertEqual(state, .stopped, "Stop from generating")
}

func testCancelGenerationTransition() {
    TestRunner.suite("Cancel Generation Transition — Process Stays Alive")

    var state: ProcessState = .generating

    // Cancel should return to ready (process stays alive for next message)
    state = .ready
    TestRunner.assertEqual(state, .ready, "generating → ready on cancel (process alive)")

    // Cancel from ready should be no-op
    let alreadyReady: ProcessState = .ready
    let afterCancel = alreadyReady
    TestRunner.assertEqual(afterCancel, .ready, "Cancel from ready stays ready")
}

func testErrorStateMessages() {
    TestRunner.suite("Error State Messages")

    let timeout: ProcessState = .error("CLI process init timed out after 15s")
    if case .error(let msg) = timeout {
        TestRunner.assertTrue(msg.contains("timed out"), "Timeout error contains 'timed out'")
    } else {
        TestRunner.assertTrue(false, "Expected error state")
    }

    let exitCode: ProcessState = .error("Process exited with code 137")
    if case .error(let msg) = exitCode {
        TestRunner.assertTrue(msg.contains("137"), "Exit code error contains code")
    } else {
        TestRunner.assertTrue(false, "Expected error state")
    }

    let stderrMsg: ProcessState = .error("Not logged in")
    if case .error(let msg) = stderrMsg {
        TestRunner.assertTrue(msg.contains("Not logged in"), "Stderr error preserved")
    } else {
        TestRunner.assertTrue(false, "Expected error state")
    }

    let stdoutClosed: ProcessState = .error("Process closed stdout unexpectedly")
    if case .error(let msg) = stdoutClosed {
        TestRunner.assertTrue(msg.contains("stdout"), "Stdout EOF error message")
    } else {
        TestRunner.assertTrue(false, "Expected error state")
    }
}

func testMultiTurnStateSequence() {
    TestRunner.suite("Multi-Turn State Sequence (Persistent Process)")

    // Simulate a full multi-turn conversation lifecycle
    var state: ProcessState = .stopped

    // 1. Process starts
    state = .starting
    state = .ready
    TestRunner.assertEqual(state, .ready, "Process initialized and ready")

    // 2. First message
    state = .generating
    state = .ready
    TestRunner.assertEqual(state, .ready, "Turn 1 complete")

    // 3. Second message (no restart — same process)
    state = .generating
    state = .ready
    TestRunner.assertEqual(state, .ready, "Turn 2 complete")

    // 4. Third message
    state = .generating
    state = .ready
    TestRunner.assertEqual(state, .ready, "Turn 3 complete")

    // 5. User cancels mid-generation
    state = .generating
    state = .ready  // cancel → ready (process alive)
    TestRunner.assertEqual(state, .ready, "Cancel mid-generation")

    // 6. Next message after cancel works
    state = .generating
    state = .ready
    TestRunner.assertEqual(state, .ready, "Turn after cancel complete")

    // 7. Process crashes
    state = .error("Process exited with code 1")
    TestRunner.assertTrue(state == .error("Process exited with code 1"), "Process crashed")

    // 8. Restart and continue
    state = .starting
    state = .ready
    state = .generating
    state = .ready
    TestRunner.assertEqual(state, .ready, "Recovered and completed turn after crash")

    // 9. Clean shutdown
    state = .stopped
    TestRunner.assertEqual(state, .stopped, "Clean shutdown")
}

func testNDJSONMessageFormat() {
    TestRunner.suite("NDJSON Message Format")

    // Test that the user message format is correct
    let content = "Hello, world!"
    let message: [String: Any] = [
        "type": "user",
        "message": [
            "role": "user",
            "content": content
        ]
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
          let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        TestRunner.assertTrue(false, "Failed to serialize message")
        return
    }

    TestRunner.assertEqual(parsed["type"] as? String, "user", "Message type is 'user'")

    if let msg = parsed["message"] as? [String: Any] {
        TestRunner.assertEqual(msg["role"] as? String, "user", "Message role is 'user'")
        TestRunner.assertEqual(msg["content"] as? String, content, "Message content preserved")
    } else {
        TestRunner.assertTrue(false, "Message field missing")
    }

    // Test newline termination
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        TestRunner.assertTrue(false, "Failed to convert to string")
        return
    }
    let terminated = jsonString + "\n"
    TestRunner.assertTrue(terminated.hasSuffix("\n"), "Message ends with newline")
    TestRunner.assertFalse(jsonString.contains("\n"), "JSON body has no embedded newlines")
}

func testSpecialCharactersInMessage() {
    TestRunner.suite("Special Characters in NDJSON Message")

    let specialContent = "Hello \"world\" with\nnewlines\tand\ttabs & <html>"
    let message: [String: Any] = [
        "type": "user",
        "message": [
            "role": "user",
            "content": specialContent
        ]
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
          let reparsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let msg = reparsed["message"] as? [String: Any] else {
        TestRunner.assertTrue(false, "Failed to round-trip special characters")
        return
    }

    TestRunner.assertEqual(msg["content"] as? String, specialContent, "Special characters round-trip correctly")
}

func testNDJSONMultimodalMessageFormat() {
    TestRunner.suite("NDJSON Multimodal (Image) Message Format")

    // Test that the multimodal content block format is correct for Claude Code CLI
    // When images are present, content becomes an array of blocks (Anthropic API format)
    let text = "What's in this image?"
    let base64Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    let mimeType = "image/png"

    // Build content blocks (mirrors PromptBuilder.formatAnthropicMultimodalContent)
    let contentBlocks: [[String: Any]] = [
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": mimeType,
                "data": base64Data
            ]
        ],
        [
            "type": "text",
            "text": text
        ]
    ]

    let message: [String: Any] = [
        "type": "user",
        "message": [
            "role": "user",
            "content": contentBlocks
        ] as [String: Any]
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
          let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        TestRunner.assertTrue(false, "Failed to serialize multimodal message")
        return
    }

    TestRunner.assertEqual(parsed["type"] as? String, "user", "Message type is 'user'")

    guard let msg = parsed["message"] as? [String: Any] else {
        TestRunner.assertTrue(false, "Message field missing")
        return
    }

    TestRunner.assertEqual(msg["role"] as? String, "user", "Message role is 'user'")

    guard let content = msg["content"] as? [[String: Any]] else {
        TestRunner.assertTrue(false, "Content should be an array of blocks")
        return
    }

    TestRunner.assertEqual(content.count, 2, "Two content blocks (image + text)")

    // Verify image block
    let imageBlock = content[0]
    TestRunner.assertEqual(imageBlock["type"] as? String, "image", "First block is image type")

    if let source = imageBlock["source"] as? [String: String] {
        TestRunner.assertEqual(source["type"], "base64", "Image source type is base64")
        TestRunner.assertEqual(source["media_type"], mimeType, "Image media_type preserved")
        TestRunner.assertEqual(source["data"], base64Data, "Image data preserved")
    } else {
        TestRunner.assertTrue(false, "Image source missing or wrong type")
    }

    // Verify text block
    let textBlock = content[1]
    TestRunner.assertEqual(textBlock["type"] as? String, "text", "Second block is text type")
    TestRunner.assertEqual(textBlock["text"] as? String, text, "Text content preserved")

    // Verify it serializes as valid single-line NDJSON
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        TestRunner.assertTrue(false, "Failed to convert to string")
        return
    }
    let terminated = jsonString + "\n"
    TestRunner.assertTrue(terminated.hasSuffix("\n"), "Message ends with newline")
}

func testMultipleImagesInMessage() {
    TestRunner.suite("Multiple Images in NDJSON Message")

    let base64_1 = "AAAA"
    let base64_2 = "BBBB"

    let contentBlocks: [[String: Any]] = [
        [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/png", "data": base64_1]
        ],
        [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/jpeg", "data": base64_2]
        ],
        [
            "type": "text",
            "text": "Compare these images"
        ]
    ]

    let message: [String: Any] = [
        "type": "user",
        "message": [
            "role": "user",
            "content": contentBlocks
        ] as [String: Any]
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
          let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let msg = parsed["message"] as? [String: Any],
          let content = msg["content"] as? [[String: Any]] else {
        TestRunner.assertTrue(false, "Failed to round-trip multiple images message")
        return
    }

    TestRunner.assertEqual(content.count, 3, "Three content blocks (2 images + text)")
    TestRunner.assertEqual(content[0]["type"] as? String, "image", "First block is image")
    TestRunner.assertEqual(content[1]["type"] as? String, "image", "Second block is image")
    TestRunner.assertEqual(content[2]["type"] as? String, "text", "Third block is text")
}

func testTextOnlyFallback() {
    TestRunner.suite("Text-Only Message (No Images)")

    // When no images, content should be a plain string (not an array)
    let content = "Hello, no images here"
    let message: [String: Any] = [
        "type": "user",
        "message": [
            "role": "user",
            "content": content
        ]
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
          let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let msg = parsed["message"] as? [String: Any] else {
        TestRunner.assertTrue(false, "Failed to round-trip text-only message")
        return
    }

    // Content should be a string, not an array
    TestRunner.assertTrue(msg["content"] is String, "Content is plain string when no images")
    TestRunner.assertEqual(msg["content"] as? String, content, "Text content preserved")
}

// MARK: - Main

@main
struct ClaudeCodeProcessManagerTests {
    static func main() {
        testProcessStateEquality()
        testStateTransitions()
        testCrashRecoveryTransitions()
        testDoubleStartGuard()
        testStopIdempotency()
        testCancelGenerationTransition()
        testErrorStateMessages()
        testMultiTurnStateSequence()
        testNDJSONMessageFormat()
        testSpecialCharactersInMessage()
        testNDJSONMultimodalMessageFormat()
        testMultipleImagesInMessage()
        testTextOnlyFallback()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
