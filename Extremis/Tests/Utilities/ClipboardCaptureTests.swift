// MARK: - ClipboardCapture Unit Tests
// Standalone test runner that doesn't require XCTest (for Command Line Tools compatibility)

import Foundation
import AppKit

/// Simple test framework for running without XCTest
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String, file: String = #file, line: Int = #line) {
        if actual == expected {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String, file: String = #file, line: Int = #line) {
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

    static func assertTrue(_ condition: Bool, _ testName: String, file: String = #file, line: Int = #line) {
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

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("Test Results: \(passedCount) passed, \(failedCount) failed")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
    }
}

/// Tests for ClipboardCapture marker-based text capture functionality
/// Note: Most methods in ClipboardCapture interact with CGEvent and require
/// accessibility permissions, so we focus on testing the logic we can isolate
struct ClipboardCaptureTests {

    // MARK: - Properties

    private let marker = " " // Same marker used in ClipboardCapture

    // MARK: - Marker Stripping Tests (Preceding Text)

    /// Test stripping marker from end of preceding text
    func testStripMarkerFromEndOfPrecedingText() {
        let capturedText = "Hello World "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello World", "testStripMarkerFromEndOfPrecedingText")
    }

    /// Test when preceding text doesn't end with marker (edge case)
    func testPrecedingTextWithoutMarker() {
        let capturedText = "Hello World"

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello World", "testPrecedingTextWithoutMarker")
    }

    /// Test empty preceding text
    func testEmptyPrecedingText() {
        let capturedText = ""

        let result: String? = capturedText.isEmpty ? nil : capturedText

        TestRunner.assertNil(result, "testEmptyPrecedingText")
    }

    /// Test preceding text that is only the marker
    func testPrecedingTextOnlyMarker() {
        let capturedText = " "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        let finalResult: String? = result.isEmpty ? nil : result

        TestRunner.assertNil(finalResult, "testPrecedingTextOnlyMarker")
    }

    /// Test preceding text with multiple trailing spaces
    func testPrecedingTextMultipleTrailingSpaces() {
        let capturedText = "Hello World   " // 3 spaces at end

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count)) // Should only strip 1
        }

        TestRunner.assertEqual(result, "Hello World  ", "testPrecedingTextMultipleTrailingSpaces") // Should have 2 spaces left
    }

    // MARK: - Marker Stripping Tests (Succeeding Text)

    /// Test stripping marker from beginning of succeeding text
    func testStripMarkerFromStartOfSucceedingText() {
        let capturedText = " Hello World"

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        TestRunner.assertEqual(result, "Hello World", "testStripMarkerFromStartOfSucceedingText")
    }

    /// Test when succeeding text doesn't start with marker (edge case)
    func testSucceedingTextWithoutMarker() {
        let capturedText = "Hello World"

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        TestRunner.assertEqual(result, "Hello World", "testSucceedingTextWithoutMarker")
    }

    /// Test empty succeeding text
    func testEmptySucceedingText() {
        let capturedText = ""

        let result: String? = capturedText.isEmpty ? nil : capturedText

        TestRunner.assertNil(result, "testEmptySucceedingText")
    }

    /// Test succeeding text that is only the marker
    func testSucceedingTextOnlyMarker() {
        let capturedText = " "

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        let finalResult: String? = result.isEmpty ? nil : result

        TestRunner.assertNil(finalResult, "testSucceedingTextOnlyMarker")
    }

    /// Test succeeding text with multiple leading spaces
    func testSucceedingTextMultipleLeadingSpaces() {
        let capturedText = "   Hello World" // 3 spaces at start

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count)) // Should only strip 1
        }

        TestRunner.assertEqual(result, "  Hello World", "testSucceedingTextMultipleLeadingSpaces") // Should have 2 spaces left
    }

    // MARK: - Multiline Text Tests

    /// Test preceding multiline text with marker
    func testPrecedingMultilineText() {
        let capturedText = "Line 1\nLine 2\nLine 3 "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Line 1\nLine 2\nLine 3", "testPrecedingMultilineText")
    }

    /// Test succeeding multiline text with marker
    func testSucceedingMultilineText() {
        let capturedText = " Line 1\nLine 2\nLine 3"

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        TestRunner.assertEqual(result, "Line 1\nLine 2\nLine 3", "testSucceedingMultilineText")
    }

    // MARK: - Unicode Text Tests

    /// Test preceding text with unicode characters
    func testPrecedingUnicodeText() {
        let capturedText = "Hello 🌍 World 你好 "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello 🌍 World 你好", "testPrecedingUnicodeText")
    }

    /// Test succeeding text with unicode characters
    func testSucceedingUnicodeText() {
        let capturedText = " Hello 🌍 World 你好"

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        TestRunner.assertEqual(result, "Hello 🌍 World 你好", "testSucceedingUnicodeText")
    }

    // MARK: - Clipboard Save/Restore Tests

    /// Test clipboard save and restore with string data
    func testClipboardSaveRestoreString() {
        let pasteboard = NSPasteboard.general
        let originalContent = "Original clipboard content"

        // Set original content
        pasteboard.clearContents()
        pasteboard.setString(originalContent, forType: .string)

        // Save clipboard
        var savedData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedData[type] = data
            }
        }

        // Modify clipboard (simulating capture operation)
        pasteboard.clearContents()
        pasteboard.setString("Modified content", forType: .string)

        // Verify modification
        TestRunner.assertEqual(pasteboard.string(forType: .string), "Modified content", "testClipboardSaveRestoreString - modification")

        // Restore clipboard
        pasteboard.clearContents()
        for (type, data) in savedData {
            pasteboard.setData(data, forType: type)
        }

        // Verify restoration
        TestRunner.assertEqual(pasteboard.string(forType: .string), originalContent, "testClipboardSaveRestoreString - restoration")
    }

    /// Test clipboard save with empty clipboard
    func testClipboardSaveEmpty() {
        let pasteboard = NSPasteboard.general

        // Clear clipboard
        pasteboard.clearContents()

        // Save empty clipboard
        var savedData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedData[type] = data
            }
        }

        TestRunner.assertTrue(savedData.isEmpty, "testClipboardSaveEmpty")
    }

    // MARK: - Edge Case: Text Entirely Made of Spaces

    /// Test preceding text that is all spaces (multiple markers)
    func testPrecedingTextAllSpaces() {
        let capturedText = "     " // 5 spaces

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count)) // Only strips 1
        }

        // Should have 4 spaces left
        TestRunner.assertEqual(result, "    ", "testPrecedingTextAllSpaces - content")
        TestRunner.assertEqual(result.count, 4, "testPrecedingTextAllSpaces - count")
    }

    /// Test succeeding text that is all spaces
    func testSucceedingTextAllSpaces() {
        let capturedText = "     " // 5 spaces

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count)) // Only strips 1
        }

        // Should have 4 spaces left
        TestRunner.assertEqual(result, "    ", "testSucceedingTextAllSpaces - content")
        TestRunner.assertEqual(result.count, 4, "testSucceedingTextAllSpaces - count")
    }

    // MARK: - Edge Case: Newlines and Whitespace

    /// Test text with tab characters
    func testTextWithTabs() {
        let capturedText = "Hello\tWorld "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello\tWorld", "testTextWithTabs")
    }

    /// Test text ending with newline then marker
    func testTextWithNewlineBeforeMarker() {
        let capturedText = "Hello World\n "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello World\n", "testTextWithNewlineBeforeMarker")
    }

    // MARK: - Edge Case: Windows Line Endings

    /// Test text with Windows-style line endings (CRLF)
    func testTextWithCRLF() {
        let capturedText = "Line 1\r\nLine 2\r\nLine 3 "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Line 1\r\nLine 2\r\nLine 3", "testTextWithCRLF")
    }

    /// Test succeeding text with CRLF
    func testSucceedingTextWithCRLF() {
        let capturedText = " Line 1\r\nLine 2"

        var result = capturedText
        if result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count))
        }

        TestRunner.assertEqual(result, "Line 1\r\nLine 2", "testSucceedingTextWithCRLF")
    }

    // MARK: - Edge Case: Only Newlines

    /// Test text that is only newlines with marker
    func testTextOnlyNewlines() {
        let capturedText = "\n\n\n "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "\n\n\n", "testTextOnlyNewlines")
    }

    // MARK: - Edge Case: Special Characters

    /// Test text with special characters
    func testTextWithSpecialCharacters() {
        let capturedText = "Hello @#$%^&*()_+-=[]{}|;':\",./<>? World "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result, "Hello @#$%^&*()_+-=[]{}|;':\",./<>? World", "testTextWithSpecialCharacters")
    }

    // MARK: - Edge Case: Very Long Text

    /// Test that marker stripping works on long text
    func testVeryLongText() {
        let longContent = String(repeating: "a", count: 10000)
        let capturedText = longContent + " "

        var result = capturedText
        if result.hasSuffix(marker) {
            result = String(result.dropLast(marker.count))
        }

        TestRunner.assertEqual(result.count, 10000, "testVeryLongText - length")
        TestRunner.assertEqual(result, longContent, "testVeryLongText - content")
    }

    // MARK: - Edge Case: Nil Handling

    /// Test nil clipboard content handling
    func testNilClipboardContent() {
        let copiedContent: String? = nil

        // Simulate the logic from ClipboardCapture
        var result = copiedContent
        if let content = result, content.hasSuffix(marker) {
            result = String(content.dropLast(marker.count))
        }

        let finalResult = result?.isEmpty == true ? nil : result

        TestRunner.assertNil(finalResult, "testNilClipboardContent")
    }

    // MARK: - Run All Tests

    func runAllTests() {
        print("\n🧪 Running ClipboardCapture Tests...\n")

        // Marker stripping - preceding text
        testStripMarkerFromEndOfPrecedingText()
        testPrecedingTextWithoutMarker()
        testEmptyPrecedingText()
        testPrecedingTextOnlyMarker()
        testPrecedingTextMultipleTrailingSpaces()

        // Marker stripping - succeeding text
        testStripMarkerFromStartOfSucceedingText()
        testSucceedingTextWithoutMarker()
        testEmptySucceedingText()
        testSucceedingTextOnlyMarker()
        testSucceedingTextMultipleLeadingSpaces()

        // Multiline text
        testPrecedingMultilineText()
        testSucceedingMultilineText()

        // Unicode text
        testPrecedingUnicodeText()
        testSucceedingUnicodeText()

        // Clipboard save/restore
        testClipboardSaveRestoreString()
        testClipboardSaveEmpty()

        // Edge cases - spaces
        testPrecedingTextAllSpaces()
        testSucceedingTextAllSpaces()

        // Edge cases - whitespace
        testTextWithTabs()
        testTextWithNewlineBeforeMarker()

        // Edge cases - Windows line endings
        testTextWithCRLF()
        testSucceedingTextWithCRLF()

        // Edge cases - only newlines
        testTextOnlyNewlines()

        // Edge cases - special characters
        testTextWithSpecialCharacters()

        // Edge cases - very long text
        testVeryLongText()

        // Edge cases - nil handling
        testNilClipboardContent()

        TestRunner.printSummary()
    }
}

// MARK: - Main Entry Point

/// Run tests when this file is executed directly
@main
struct TestMain {
    static func main() {
        let tests = ClipboardCaptureTests()
        tests.runAllTests()

        // Exit with appropriate code
        exit(TestRunner.failedCount > 0 ? 1 : 0)
    }
}

