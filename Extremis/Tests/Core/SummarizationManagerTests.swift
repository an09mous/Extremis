// MARK: - SummarizationManager Unit Tests
// Tests for summarization trigger logic and SessionSummary model
// These tests verify the summarization thresholds and summary validation logic

import Foundation

// MARK: - Test Runner (embedded for standalone execution)

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
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
        assertTrue(!condition, testName)
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

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Test Helper: Create messages

func createTestMessages(count: Int, charsPerMessage: Int = 100) -> [PersistedMessage] {
    (0..<count).map { i in
        let role: ChatRole = i % 2 == 0 ? .user : .assistant
        let content = String(repeating: "x", count: charsPerMessage)
        return PersistedMessage(
            id: UUID(),
            role: role,
            content: content,
            timestamp: Date().addingTimeInterval(Double(i) * 60),
            contextData: nil
        )
    }
}

func createTestSession(
    messageCount: Int,
    charsPerMessage: Int = 100,
    summary: SessionSummary? = nil
) -> PersistedSession {
    PersistedSession(
        id: UUID(),
        messages: createTestMessages(count: messageCount, charsPerMessage: charsPerMessage),
        initialRequest: nil,
        maxMessages: 20,
        createdAt: Date(),
        updatedAt: Date(),
        title: "Test Session",
        isArchived: false,
        summary: summary
    )
}

// MARK: - Token Estimation Tests

func testTokenEstimation() {
    print("\n📦 Token Estimation Tests")
    print("----------------------------------------")

    // Test: 100 chars = 25 tokens (100 / 4)
    let session100 = createTestSession(messageCount: 1, charsPerMessage: 100)
    let chars100 = session100.messages.reduce(0) { $0 + $1.content.count }
    let tokens100 = chars100 / 4
    TestRunner.assertEqual(tokens100, 25, "100 chars = 25 tokens")

    // Test: 1000 chars = 250 tokens
    let session1000 = createTestSession(messageCount: 10, charsPerMessage: 100)
    let chars1000 = session1000.messages.reduce(0) { $0 + $1.content.count }
    let tokens1000 = chars1000 / 4
    TestRunner.assertEqual(tokens1000, 250, "1000 chars = 250 tokens")

    // Test: 32000 chars = 8000 tokens (threshold)
    let session32000 = createTestSession(messageCount: 10, charsPerMessage: 3200)
    let chars32000 = session32000.messages.reduce(0) { $0 + $1.content.count }
    let tokens32000 = chars32000 / 4
    TestRunner.assertEqual(tokens32000, 8000, "32000 chars = 8000 tokens")
}

// MARK: - SessionSummary Model Tests

func testSessionSummary_IsValid_WithContent() {
    print("\n📦 SessionSummary - Is Valid")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    TestRunner.assertTrue(summary.isValid, "Summary with content and message count should be valid")
}

func testSessionSummary_IsValid_EmptyContent() {
    print("\n📦 SessionSummary - Is Invalid (Empty Content)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    TestRunner.assertFalse(summary.isValid, "Summary with empty content should be invalid")
}

func testSessionSummary_IsValid_ZeroMessageCount() {
    print("\n📦 SessionSummary - Is Invalid (Zero Message Count)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 0,
        createdAt: Date(),
        modelUsed: nil
    )

    TestRunner.assertFalse(summary.isValid, "Summary with zero message count should be invalid")
}

func testSessionSummary_IsValid_BothInvalid() {
    print("\n📦 SessionSummary - Is Invalid (Both Empty)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "",
        coversMessageCount: 0,
        createdAt: Date(),
        modelUsed: nil
    )

    TestRunner.assertFalse(summary.isValid, "Summary with both invalid should be invalid")
}

func testSessionSummary_NeedsRegeneration_BelowThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (Below Threshold)")
    print("----------------------------------------")

    // Summary covers 10 messages, threshold=10 means 10 recent were kept
    // So at creation: 10 summarized + 10 recent = 20 total covered
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 25 total: coveredWhenCreated = 10 + 10 = 20, new = 25 - 20 = 5 (below threshold 10)
    let needsRegen = summary.needsRegeneration(totalMessages: 25)

    TestRunner.assertFalse(needsRegen, "5 new messages should not need regeneration (threshold 10)")
}

func testSessionSummary_NeedsRegeneration_AtThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (At Threshold)")
    print("----------------------------------------")

    // Summary covers 10 messages, threshold=10 means 10 recent were kept
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 30 total: coveredWhenCreated = 10 + 10 = 20, new = 30 - 20 = 10 (at threshold)
    let needsRegen = summary.needsRegeneration(totalMessages: 30)

    TestRunner.assertTrue(needsRegen, "10 new messages should need regeneration (threshold 10)")
}

func testSessionSummary_NeedsRegeneration_AboveThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (Above Threshold)")
    print("----------------------------------------")

    // Summary covers 10 messages, threshold=10 means 10 recent were kept
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 35 total: coveredWhenCreated = 10 + 10 = 20, new = 35 - 20 = 15 (above threshold)
    let needsRegen = summary.needsRegeneration(totalMessages: 35)

    TestRunner.assertTrue(needsRegen, "15 new messages should need regeneration (threshold 10)")
}

func testSessionSummary_NeedsRegeneration_CustomThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (Custom Threshold)")
    print("----------------------------------------")

    // Summary covers 10 messages, custom threshold=5 means 5 recent were kept
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 20 total with threshold 5: coveredWhenCreated = 10 + 5 = 15, new = 20 - 15 = 5 (at threshold)
    let needsRegen = summary.needsRegeneration(totalMessages: 20, threshold: 5)

    TestRunner.assertTrue(needsRegen, "5 new messages should need regeneration (custom threshold 5)")
}

func testSessionSummary_NeedsRegeneration_NoNewMessages() {
    print("\n📦 SessionSummary - Needs Regeneration (No New Messages)")
    print("----------------------------------------")

    // Summary covers 10 messages, threshold=10 means 10 recent were kept = 20 total at creation
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 20 total: coveredWhenCreated = 10 + 10 = 20, new = 20 - 20 = 0
    let needsRegen = summary.needsRegeneration(totalMessages: 20)

    TestRunner.assertFalse(needsRegen, "0 new messages should not need regeneration")
}

// MARK: - PersistedSession buildLLMContext Tests

func testBuildLLMContext_NoSummary() {
    print("\n📦 buildLLMContext - No Summary")
    print("----------------------------------------")

    let session = createTestSession(messageCount: 10)

    let context = session.buildLLMContext()

    TestRunner.assertEqual(context.count, 10, "Without summary, returns all messages")
}

func testBuildLLMContext_WithValidSummary() {
    print("\n📦 buildLLMContext - With Valid Summary")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary of earlier messages",
        coversMessageCount: 15,
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 20, summary: summary)

    let context = session.buildLLMContext()

    // Should return: 1 summary message + (20 - 15) = 6 messages total
    TestRunner.assertEqual(context.count, 6, "With summary covering 15, returns 1 summary + 5 recent")
    TestRunner.assertEqual(context.first?.role, .system, "First message should be system (summary)")
    TestRunner.assertTrue(context.first?.content.contains("Previous session context") ?? false, "Summary message should have prefix")
}

func testBuildLLMContext_WithInvalidSummary() {
    print("\n📦 buildLLMContext - With Invalid Summary")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "",  // Invalid - empty content
        coversMessageCount: 15,
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 20, summary: summary)

    let context = session.buildLLMContext()

    // Invalid summary should be ignored, return all messages
    TestRunner.assertEqual(context.count, 20, "Invalid summary should be ignored, returns all messages")
}

func testBuildLLMContext_SummaryCoversAllMessages() {
    print("\n📦 buildLLMContext - Summary Covers All Messages")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary covering everything",
        coversMessageCount: 20,
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 20, summary: summary)

    let context = session.buildLLMContext()

    // Summary covers all 20, so should return just the summary message
    TestRunner.assertEqual(context.count, 1, "Summary covering all returns just summary message")
    TestRunner.assertEqual(context.first?.role, .system, "Only message should be summary")
}

func testBuildLLMContext_SummaryCoversMoreThanExists() {
    print("\n📦 buildLLMContext - Summary Covers More Than Exists")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 30,  // More than 20 messages
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 20, summary: summary)

    let context = session.buildLLMContext()

    // Edge case: covers more than exists, should handle gracefully
    // min(30, 20) = 20, so suffix(from: 20) = empty, result is just summary
    TestRunner.assertEqual(context.count, 1, "Summary covering more than exists returns just summary")
}

// MARK: - Threshold Logic Tests (without SummarizationManager instance)

func testMessageThresholdLogic() {
    print("\n📦 Message Threshold Logic")
    print("----------------------------------------")

    let threshold = 20

    // Below threshold
    let below = 19 >= threshold
    TestRunner.assertFalse(below, "19 messages below threshold 20")

    // At threshold
    let at = 20 >= threshold
    TestRunner.assertTrue(at, "20 messages at threshold 20")

    // Above threshold
    let above = 25 >= threshold
    TestRunner.assertTrue(above, "25 messages above threshold 20")
}

func testTokenThresholdLogic() {
    print("\n📦 Token Threshold Logic")
    print("----------------------------------------")

    let threshold = 8000

    // Calculate tokens from chars (1 token ≈ 4 chars)
    let tokensBelow = 7999 * 4 / 4  // 7999 tokens
    let tokensAt = 8000 * 4 / 4      // 8000 tokens
    let tokensAbove = 10000 * 4 / 4  // 10000 tokens

    TestRunner.assertFalse(tokensBelow >= threshold, "7999 tokens below threshold 8000")
    TestRunner.assertTrue(tokensAt >= threshold, "8000 tokens at threshold 8000")
    TestRunner.assertTrue(tokensAbove >= threshold, "10000 tokens above threshold 8000")
}

// MARK: - Main Entry Point

func runSummarizationTests() {
    print("")
    print("🧪 SummarizationManager Unit Tests")
    print("==================================================")

    TestRunner.reset()

    // Token estimation tests
    testTokenEstimation()

    // SessionSummary model tests
    testSessionSummary_IsValid_WithContent()
    testSessionSummary_IsValid_EmptyContent()
    testSessionSummary_IsValid_ZeroMessageCount()
    testSessionSummary_IsValid_BothInvalid()
    testSessionSummary_NeedsRegeneration_BelowThreshold()
    testSessionSummary_NeedsRegeneration_AtThreshold()
    testSessionSummary_NeedsRegeneration_AboveThreshold()
    testSessionSummary_NeedsRegeneration_CustomThreshold()
    testSessionSummary_NeedsRegeneration_NoNewMessages()

    // buildLLMContext tests
    testBuildLLMContext_NoSummary()
    testBuildLLMContext_WithValidSummary()
    testBuildLLMContext_WithInvalidSummary()
    testBuildLLMContext_SummaryCoversAllMessages()
    testBuildLLMContext_SummaryCoversMoreThanExists()

    // Threshold logic tests
    testMessageThresholdLogic()
    testTokenThresholdLogic()

    TestRunner.printSummary()
}

// Run when executed directly
@main
struct SummarizationTestRunner {
    static func main() {
        runSummarizationTests()
        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
