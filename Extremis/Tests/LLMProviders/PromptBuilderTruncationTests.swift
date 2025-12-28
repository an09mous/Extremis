// MARK: - PromptBuilder Truncation Tests
// Standalone tests for context truncation logic
// Run with: swiftc -o test PromptBuilderTruncationTests.swift && ./test

import Foundation

// MARK: - Truncation Constants (must match PromptBuilder.swift)
// Note: Wrapped in enum to avoid redeclaration conflicts when Xcode indexes both files

private enum TruncationLimits {
    static let preceding = 50000
    static let succeeding = 50000
    static let chatSelected = 50000
}

// MARK: - Truncation Functions (mirrors PromptBuilder implementation)

/// Truncates preceding text from the beginning, keeping the suffix (closest to cursor)
func truncatePrecedingText(_ text: String) -> String {
    guard text.count > TruncationLimits.preceding else { return text }
    return "[truncated] ..." + String(text.suffix(TruncationLimits.preceding))
}

/// Truncates succeeding text from the end, keeping the prefix (closest to cursor)
func truncateSucceedingText(_ text: String) -> String {
    guard text.count > TruncationLimits.succeeding else { return text }
    return String(text.prefix(TruncationLimits.succeeding)) + "... [truncated]"
}

/// Truncates selected text for chat system prompt from the end
func truncateChatSelectedText(_ text: String) -> String {
    guard text.count > TruncationLimits.chatSelected else { return text }
    return String(text.prefix(TruncationLimits.chatSelected)) + "... [truncated]"
}

// MARK: - TestRunner (Standalone)

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

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("❌ \(testName): Expected true but got false")
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

// MARK: - Preceding Text Tests

struct PrecedingTextTests {
    static func runAll() {
        print("\n📦 Preceding Text Truncation Tests")
        print(String(repeating: "-", count: 40))

        testNoTruncationWhenUnderLimit()
        testNoTruncationAtExactLimit()
        testTruncatesFromBeginning()
        testKeepsSuffixClosestToCursor()
        testEmptyString()
        testSingleCharacter()
        testOneOverLimit()
        testDirectionIsCorrect()
    }

    static func testNoTruncationWhenUnderLimit() {
        let text = String(repeating: "a", count: 100)
        let result = truncatePrecedingText(text)
        TestRunner.assertEqual(result, text, "Preceding: No truncation under limit")
        TestRunner.assertFalse(result.contains("[truncated]"), "Preceding: No marker under limit")
    }

    static func testNoTruncationAtExactLimit() {
        let text = String(repeating: "b", count: TruncationLimits.preceding)
        let result = truncatePrecedingText(text)
        TestRunner.assertEqual(result, text, "Preceding: No truncation at exact limit")
    }

    static func testTruncatesFromBeginning() {
        let prefix = String(repeating: "A", count: 100)
        let suffix = String(repeating: "B", count: TruncationLimits.preceding)
        let text = prefix + suffix
        let result = truncatePrecedingText(text)
        TestRunner.assertTrue(result.hasPrefix("[truncated] ..."), "Preceding: Has truncation marker")
        TestRunner.assertTrue(result.hasSuffix(String(repeating: "B", count: 100)), "Preceding: Ends with Bs")
        TestRunner.assertFalse(result.contains(String(repeating: "A", count: 50)), "Preceding: No As")
    }

    static func testKeepsSuffixClosestToCursor() {
        let beginning = String(repeating: "X", count: TruncationLimits.preceding)
        let endMarker = "END_MARKER_CLOSEST_TO_CURSOR"
        let text = beginning + endMarker
        let result = truncatePrecedingText(text)
        TestRunner.assertTrue(result.contains(endMarker), "Preceding: End marker preserved")
    }

    static func testEmptyString() {
        TestRunner.assertEqual(truncatePrecedingText(""), "", "Preceding: Empty string")
    }

    static func testSingleCharacter() {
        TestRunner.assertEqual(truncatePrecedingText("X"), "X", "Preceding: Single char")
    }

    static func testOneOverLimit() {
        let text = String(repeating: "Z", count: TruncationLimits.preceding + 1)
        let result = truncatePrecedingText(text)
        TestRunner.assertTrue(result.hasPrefix("[truncated] ..."), "Preceding: One over has marker")
        let expectedLen = "[truncated] ...".count + TruncationLimits.preceding
        TestRunner.assertEqual(result.count, expectedLen, "Preceding: One over correct length")
    }

    static func testDirectionIsCorrect() {
        // CRITICAL: Preceding text should keep END (suffix) because it's closest to cursor
        let beginning = "BEGINNING_SHOULD_BE_REMOVED_" + String(repeating: "X", count: 100)
        let end = String(repeating: "Y", count: TruncationLimits.preceding - 50) + "_END_SHOULD_BE_KEPT"
        let text = beginning + end
        let result = truncatePrecedingText(text)
        TestRunner.assertTrue(result.contains("_END_SHOULD_BE_KEPT"), "Preceding: END preserved")
        TestRunner.assertFalse(result.contains("BEGINNING_SHOULD_BE_REMOVED"), "Preceding: BEGINNING removed")
    }
}

// MARK: - Succeeding Text Tests

struct SucceedingTextTests {
    static func runAll() {
        print("\n📦 Succeeding Text Truncation Tests")
        print(String(repeating: "-", count: 40))

        testNoTruncationWhenUnderLimit()
        testNoTruncationAtExactLimit()
        testTruncatesFromEnd()
        testKeepsPrefixClosestToCursor()
        testEmptyString()
        testSingleCharacter()
        testOneOverLimit()
        testDirectionIsCorrect()
        testWithNewlines()
    }

    static func testNoTruncationWhenUnderLimit() {
        let text = String(repeating: "c", count: 100)
        let result = truncateSucceedingText(text)
        TestRunner.assertEqual(result, text, "Succeeding: No truncation under limit")
    }

    static func testNoTruncationAtExactLimit() {
        let text = String(repeating: "d", count: TruncationLimits.succeeding)
        let result = truncateSucceedingText(text)
        TestRunner.assertEqual(result, text, "Succeeding: No truncation at exact limit")
    }

    static func testTruncatesFromEnd() {
        let prefix = String(repeating: "A", count: TruncationLimits.succeeding)
        let suffix = String(repeating: "B", count: 100)
        let text = prefix + suffix
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.hasSuffix("... [truncated]"), "Succeeding: Has truncation marker")
        TestRunner.assertTrue(result.hasPrefix(String(repeating: "A", count: 100)), "Succeeding: Starts with As")
        TestRunner.assertFalse(result.contains(String(repeating: "B", count: 50)), "Succeeding: No Bs")
    }

    static func testKeepsPrefixClosestToCursor() {
        let startMarker = "START_MARKER_CLOSEST_TO_CURSOR"
        let ending = String(repeating: "Y", count: TruncationLimits.succeeding)
        let text = startMarker + ending
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.contains(startMarker), "Succeeding: Start marker preserved")
    }

    static func testEmptyString() {
        TestRunner.assertEqual(truncateSucceedingText(""), "", "Succeeding: Empty string")
    }

    static func testSingleCharacter() {
        TestRunner.assertEqual(truncateSucceedingText("Y"), "Y", "Succeeding: Single char")
    }

    static func testOneOverLimit() {
        let text = String(repeating: "Z", count: TruncationLimits.succeeding + 1)
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.hasSuffix("... [truncated]"), "Succeeding: One over has marker")
    }

    static func testDirectionIsCorrect() {
        // CRITICAL: Succeeding text should keep BEGINNING (prefix) because it's closest to cursor
        let beginning = "BEGINNING_SHOULD_BE_KEPT_" + String(repeating: "Y", count: TruncationLimits.succeeding - 50)
        let end = String(repeating: "X", count: 100) + "_END_SHOULD_BE_REMOVED"
        let text = beginning + end
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.contains("BEGINNING_SHOULD_BE_KEPT"), "Succeeding: BEGINNING preserved")
        TestRunner.assertFalse(result.contains("END_SHOULD_BE_REMOVED"), "Succeeding: END removed")
    }

    static func testWithNewlines() {
        let prefix = "Line1\nLine2\nLine3\n"
        let filler = String(repeating: "X", count: TruncationLimits.succeeding)
        let text = prefix + filler
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.contains("Line1\nLine2\nLine3\n"), "Succeeding: Newlines preserved")
    }
}

// MARK: - Chat Selected Text Tests

struct ChatSelectedTextTests {
    static func runAll() {
        print("\n📦 Chat Selected Text Truncation Tests")
        print(String(repeating: "-", count: 40))

        testNoTruncationWhenUnderLimit()
        testTruncatesFromEnd()
        testEmptyString()
    }

    static func testNoTruncationWhenUnderLimit() {
        let text = String(repeating: "e", count: 100)
        let result = truncateChatSelectedText(text)
        TestRunner.assertEqual(result, text, "ChatSelected: No truncation under limit")
    }

    static func testTruncatesFromEnd() {
        let prefix = String(repeating: "A", count: TruncationLimits.chatSelected)
        let suffix = String(repeating: "B", count: 100)
        let text = prefix + suffix
        let result = truncateChatSelectedText(text)
        TestRunner.assertTrue(result.hasSuffix("... [truncated]"), "ChatSelected: Has truncation marker")
        TestRunner.assertTrue(result.hasPrefix(String(repeating: "A", count: 100)), "ChatSelected: Starts with As")
    }

    static func testEmptyString() {
        TestRunner.assertEqual(truncateChatSelectedText(""), "", "ChatSelected: Empty string")
    }
}

// MARK: - Unicode Tests

struct UnicodeTests {
    static func runAll() {
        print("\n📦 Unicode Truncation Tests")
        print(String(repeating: "-", count: 40))

        testPrecedingWithEmoji()
        testSucceedingWithUnicode()
    }

    static func testPrecedingWithEmoji() {
        let emoji = "🎉"
        let prefix = String(repeating: emoji, count: 10)
        let suffix = String(repeating: "A", count: TruncationLimits.preceding)
        let text = prefix + suffix
        let result = truncatePrecedingText(text)
        TestRunner.assertTrue(result.hasPrefix("[truncated] ..."), "Unicode: Preceding with emoji truncates")
        TestRunner.assertTrue(result.contains(String(repeating: "A", count: 100)), "Unicode: Preserves suffix As")
    }

    static func testSucceedingWithUnicode() {
        let prefix = "日本語テスト"
        let filler = String(repeating: "X", count: TruncationLimits.succeeding)
        let text = prefix + filler
        let result = truncateSucceedingText(text)
        TestRunner.assertTrue(result.contains("日本語テスト"), "Unicode: Japanese preserved")
    }
}

// MARK: - Main Entry Point

@main
struct PromptBuilderTruncationTestsMain {
    static func main() {
        print("🧪 PromptBuilder Truncation Tests")
        print(String(repeating: "=", count: 50))

        TestRunner.reset()

        PrecedingTextTests.runAll()
        SucceedingTextTests.runAll()
        ChatSelectedTextTests.runAll()
        UnicodeTests.runAll()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

