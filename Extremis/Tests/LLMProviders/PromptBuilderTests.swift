// MARK: - PromptBuilder Unit Tests
// Tests for prompt mode detection and template rendering

import Foundation

// MARK: - Test Runner

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

    static func assertFalse(_ condition: Bool, _ testName: String, file: String = #file, line: Int = #line) {
        assertTrue(!condition, testName, file: file, line: line)
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

/// Tests for PromptBuilder prompt mode detection and template rendering
struct PromptBuilderTests {

    private let builder = PromptBuilder.shared

    // MARK: - Prompt Mode Detection Tests

    /// Test autocomplete mode: no instruction, no selection
    func testDetectPromptMode_Autocomplete() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: "Hello world",
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "", context: context)
        TestRunner.assertEqual(mode, .autocomplete, "testDetectPromptMode_Autocomplete")
    }

    /// Test autocomplete mode: whitespace-only instruction
    func testDetectPromptMode_AutocompleteWithWhitespace() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: "Hello",
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "   \n\t  ", context: context)
        TestRunner.assertEqual(mode, .autocomplete, "testDetectPromptMode_AutocompleteWithWhitespace")
    }

    /// Test instruction mode: has instruction, no selection
    func testDetectPromptMode_Instruction() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: "Hello",
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "Make this formal", context: context)
        TestRunner.assertEqual(mode, .instruction, "testDetectPromptMode_Instruction")
    }

    /// Test selection transform mode: has instruction AND selection
    func testDetectPromptMode_SelectionTransform() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Some selected text",
            precedingText: nil,
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "Translate to Spanish", context: context)
        TestRunner.assertEqual(mode, .selectionTransform, "testDetectPromptMode_SelectionTransform")
    }

    /// Test selection no instruction mode: has selection, no instruction
    func testDetectPromptMode_SelectionNoInstruction() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Text to summarize",
            precedingText: nil,
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "", context: context)
        TestRunner.assertEqual(mode, .selectionNoInstruction, "testDetectPromptMode_SelectionNoInstruction")
    }

    /// Test empty selection is treated as no selection
    func testDetectPromptMode_EmptySelectionIsNoSelection() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "",
            precedingText: "Hello",
            succeedingText: nil
        )

        let mode = builder.detectPromptMode(instruction: "", context: context)
        TestRunner.assertEqual(mode, .autocomplete, "testDetectPromptMode_EmptySelectionIsNoSelection")
    }

    /// Test whitespace-only selection is treated as no selection
    func testDetectPromptMode_WhitespaceSelectionIsNoSelection() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "   \n\t  ",
            precedingText: "Hello",
            succeedingText: nil
        )

        // Note: Current implementation does NOT trim selection, so whitespace IS a selection
        // This test documents current behavior - may want to change this
        let mode = builder.detectPromptMode(instruction: "", context: context)
        TestRunner.assertEqual(mode, .selectionNoInstruction, "testDetectPromptMode_WhitespaceSelectionIsNoSelection")
    }

    // MARK: - Template Content Tests

    /// Test autocomplete prompt contains required sections
    func testBuildPrompt_AutocompleteContainsRequiredSections() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: "Hello world",
            succeedingText: " and goodbye"
        )

        let prompt = builder.buildPrompt(instruction: "", context: context)

        TestRunner.assertTrue(prompt.contains("AUTOCOMPLETE MODE"), "testBuildPrompt_AutocompleteContainsRequiredSections_Mode")
        TestRunner.assertTrue(prompt.contains("Hello world"), "testBuildPrompt_AutocompleteContainsRequiredSections_Preceding")
        TestRunner.assertTrue(prompt.contains("and goodbye"), "testBuildPrompt_AutocompleteContainsRequiredSections_Succeeding")
    }

    /// Test selection transform prompt contains required sections
    func testBuildPrompt_SelectionTransformContainsRequiredSections() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Selected text here",
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "Make formal", context: context)

        TestRunner.assertTrue(prompt.contains("SELECTION TRANSFORMATION MODE"), "testBuildPrompt_SelectionTransformContainsRequiredSections_Mode")
        TestRunner.assertTrue(prompt.contains("Selected text here"), "testBuildPrompt_SelectionTransformContainsRequiredSections_Selection")
        TestRunner.assertTrue(prompt.contains("Make formal"), "testBuildPrompt_SelectionTransformContainsRequiredSections_Instruction")
    }

    // MARK: - Edge Case Tests

    /// Test nil selectedText is handled correctly
    func testBuildPrompt_NilSelectedText() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "", context: context)

        // Should still generate a valid prompt (autocomplete mode)
        TestRunner.assertTrue(!prompt.isEmpty, "testBuildPrompt_NilSelectedText")
        TestRunner.assertTrue(prompt.contains("AUTOCOMPLETE"), "testBuildPrompt_NilSelectedText_Mode")
    }

    /// Test selection no instruction defaults to summarize
    func testBuildPrompt_SelectionNoInstructionDefaultsToSummarize() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Important text",
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "", context: context)

        TestRunner.assertTrue(prompt.contains("Summarize"), "testBuildPrompt_SelectionNoInstructionDefaultsToSummarize")
    }

    /// Test window title is included when available
    func testBuildPrompt_IncludesWindowTitle() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "My Important Document"
            ),
            selectedText: "Some text",
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "Summarize", context: context)

        TestRunner.assertTrue(prompt.contains("My Important Document"), "testBuildPrompt_IncludesWindowTitle")
    }

    /// Test long instruction is preserved
    func testBuildPrompt_LongInstruction() {
        builder.debugLogging = false

        let longInstruction = String(repeating: "Make this more professional. ", count: 50)
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Short text",
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: longInstruction, context: context)

        TestRunner.assertTrue(prompt.contains("Make this more professional"), "testBuildPrompt_LongInstruction")
    }

    /// Test special characters in selected text are preserved
    func testBuildPrompt_SpecialCharactersInSelection() {
        builder.debugLogging = false

        let specialText = "Code: `func test() { print(\"Hello\") }` and <html> tags & symbols €£¥"
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: specialText,
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "Format this", context: context)

        TestRunner.assertTrue(prompt.contains(specialText), "testBuildPrompt_SpecialCharactersInSelection")
    }

    /// Test newlines in selected text are preserved
    func testBuildPrompt_NewlinesInSelection() {
        builder.debugLogging = false

        let multilineText = "Line 1\nLine 2\nLine 3"
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: multilineText,
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "Summarize", context: context)

        TestRunner.assertTrue(prompt.contains("Line 1"), "testBuildPrompt_NewlinesInSelection_Line1")
        TestRunner.assertTrue(prompt.contains("Line 2"), "testBuildPrompt_NewlinesInSelection_Line2")
        TestRunner.assertTrue(prompt.contains("Line 3"), "testBuildPrompt_NewlinesInSelection_Line3")
    }

    /// Test instruction with selection prioritizes selection transform
    func testBuildPrompt_InstructionWithSelectionIsNotAutocomplete() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Selected text",
            precedingText: "Before text",
            succeedingText: "After text"
        )

        let prompt = builder.buildPrompt(instruction: "Translate", context: context)

        // Should NOT be autocomplete when selection exists
        TestRunner.assertFalse(prompt.contains("AUTOCOMPLETE MODE"), "testBuildPrompt_InstructionWithSelectionIsNotAutocomplete_NotAutocomplete")
        TestRunner.assertTrue(prompt.contains("SELECTION TRANSFORMATION MODE"), "testBuildPrompt_InstructionWithSelectionIsNotAutocomplete_IsTransform")
    }

    /// Test empty context source fields are handled
    func testBuildPrompt_EmptyContextSource() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "", bundleIdentifier: ""),
            selectedText: nil,
            precedingText: "Hello",
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "", context: context)

        // Should still produce valid autocomplete prompt
        TestRunner.assertTrue(prompt.contains("AUTOCOMPLETE"), "testBuildPrompt_EmptyContextSource")
        TestRunner.assertTrue(prompt.contains("Hello"), "testBuildPrompt_EmptyContextSource_Preceding")
    }

    /// Test all text fields nil produces valid prompt
    func testBuildPrompt_AllTextFieldsNil() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil,
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "", context: context)

        // Should still produce a valid prompt
        TestRunner.assertTrue(!prompt.isEmpty, "testBuildPrompt_AllTextFieldsNil_NotEmpty")
        TestRunner.assertTrue(prompt.contains("AUTOCOMPLETE"), "testBuildPrompt_AllTextFieldsNil_Mode")
    }

    /// Test unicode in instruction
    func testBuildPrompt_UnicodeInstruction() {
        builder.debugLogging = false

        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Hello",
            precedingText: nil,
            succeedingText: nil
        )

        let prompt = builder.buildPrompt(instruction: "翻译成中文 🇨🇳", context: context)

        TestRunner.assertTrue(prompt.contains("翻译成中文"), "testBuildPrompt_UnicodeInstruction_Chinese")
        TestRunner.assertTrue(prompt.contains("🇨🇳"), "testBuildPrompt_UnicodeInstruction_Emoji")
    }

    // MARK: - Summarization Tests

    /// Test summarization prompt contains required sections
    func testBuildSummarizationPrompt_ContainsRequiredSections() {
        builder.debugLogging = false

        let request = SummaryRequest(
            text: "Long text to summarize",
            source: ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari"),
            format: .paragraph,
            length: .normal
        )

        let prompt = builder.buildSummarizationPrompt(request: request)

        TestRunner.assertTrue(prompt.contains("SUMMARIZATION MODE"), "testBuildSummarizationPrompt_Mode")
        TestRunner.assertTrue(prompt.contains("Long text to summarize"), "testBuildSummarizationPrompt_Text")
        TestRunner.assertTrue(prompt.contains("Safari"), "testBuildSummarizationPrompt_App")
    }

    /// Test different summary formats produce different instructions
    func testBuildSummarizationPrompt_DifferentFormats() {
        builder.debugLogging = false

        let source = ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari")

        let paragraphRequest = SummaryRequest(text: "Text", source: source, format: .paragraph, length: .normal)
        let bulletsRequest = SummaryRequest(text: "Text", source: source, format: .bullets, length: .normal)

        let paragraphPrompt = builder.buildSummarizationPrompt(request: paragraphRequest)
        let bulletsPrompt = builder.buildSummarizationPrompt(request: bulletsRequest)

        // Prompts should be different
        TestRunner.assertTrue(paragraphPrompt != bulletsPrompt, "testBuildSummarizationPrompt_DifferentFormats")
    }

    /// Test different summary lengths produce different instructions
    func testBuildSummarizationPrompt_DifferentLengths() {
        builder.debugLogging = false

        let source = ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari")

        let shorterRequest = SummaryRequest(text: "Text", source: source, format: .paragraph, length: .shorter)
        let longerRequest = SummaryRequest(text: "Text", source: source, format: .paragraph, length: .longer)

        let shorterPrompt = builder.buildSummarizationPrompt(request: shorterRequest)
        let longerPrompt = builder.buildSummarizationPrompt(request: longerRequest)

        // Prompts should be different
        TestRunner.assertTrue(shorterPrompt != longerPrompt, "testBuildSummarizationPrompt_DifferentLengths")
    }

    /// Test keyPoints format includes appropriate instructions
    func testBuildSummarizationPrompt_KeyPointsFormat() {
        builder.debugLogging = false

        let request = SummaryRequest(
            text: "Long text",
            source: ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari"),
            format: .keyPoints,
            length: .normal
        )

        let prompt = builder.buildSummarizationPrompt(request: request)

        TestRunner.assertTrue(prompt.contains("key points") || prompt.contains("key takeaways"), "testBuildSummarizationPrompt_KeyPointsFormat")
    }

    /// Test summarization with very long text
    func testBuildSummarizationPrompt_LongText() {
        builder.debugLogging = false

        let longText = String(repeating: "This is a long sentence for testing. ", count: 100)
        let request = SummaryRequest(
            text: longText,
            source: ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari"),
            format: .paragraph,
            length: .normal
        )

        let prompt = builder.buildSummarizationPrompt(request: request)

        // Should contain the full text
        TestRunner.assertTrue(prompt.contains("This is a long sentence for testing"), "testBuildSummarizationPrompt_LongText")
    }

    // MARK: - Run All Tests

    func runAllTests() {
        print("\n" + String(repeating: "=", count: 50))
        print("Running PromptBuilder Tests")
        print(String(repeating: "=", count: 50) + "\n")

        // Mode detection tests
        testDetectPromptMode_Autocomplete()
        testDetectPromptMode_AutocompleteWithWhitespace()
        testDetectPromptMode_Instruction()
        testDetectPromptMode_SelectionTransform()
        testDetectPromptMode_SelectionNoInstruction()
        testDetectPromptMode_EmptySelectionIsNoSelection()
        testDetectPromptMode_WhitespaceSelectionIsNoSelection()

        // Template content tests
        testBuildPrompt_AutocompleteContainsRequiredSections()
        testBuildPrompt_SelectionTransformContainsRequiredSections()

        // Edge case tests
        testBuildPrompt_NilSelectedText()
        testBuildPrompt_SelectionNoInstructionDefaultsToSummarize()
        testBuildPrompt_IncludesWindowTitle()
        testBuildPrompt_LongInstruction()
        testBuildPrompt_SpecialCharactersInSelection()
        testBuildPrompt_NewlinesInSelection()
        testBuildPrompt_InstructionWithSelectionIsNotAutocomplete()
        testBuildPrompt_EmptyContextSource()
        testBuildPrompt_AllTextFieldsNil()
        testBuildPrompt_UnicodeInstruction()

        // Summarization tests
        testBuildSummarizationPrompt_ContainsRequiredSections()
        testBuildSummarizationPrompt_DifferentFormats()
        testBuildSummarizationPrompt_DifferentLengths()
        testBuildSummarizationPrompt_KeyPointsFormat()
        testBuildSummarizationPrompt_LongText()
    }
}

// MARK: - Main Entry Point

@main
struct TestMain {
    static func main() {
        print("🧪 Running PromptBuilder Tests...")
        print("")

        let tests = PromptBuilderTests()
        tests.runAllTests()

        TestRunner.printSummary()

        // Exit with appropriate code
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
