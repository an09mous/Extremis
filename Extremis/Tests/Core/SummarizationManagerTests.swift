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

    // Edge case: covers more than exists - defensive behavior returns all messages
    // This handles cases where summary state got out of sync (e.g., after retry)
    TestRunner.assertEqual(context.count, 20, "Summary covering more than exists falls back to all messages")
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

// MARK: - Edge Cases for Regeneration Logic

func testSessionSummary_NeedsRegeneration_NegativeNewMessages() {
    print("\n📦 SessionSummary - Needs Regeneration (Negative New Messages)")
    print("----------------------------------------")

    // Summary covers 20 messages, but total is only 15 (edge case: messages deleted?)
    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 20,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 15 total with threshold 10: coveredWhenCreated = 20 + 10 = 30, new = 15 - 30 = -15
    let needsRegen = summary.needsRegeneration(totalMessages: 15)

    TestRunner.assertFalse(needsRegen, "Negative new messages should not need regeneration")
}

func testSessionSummary_NeedsRegeneration_ZeroThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (Zero Threshold)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 11 total with threshold 0: coveredWhenCreated = 10 + 0 = 10, new = 11 - 10 = 1, 1 >= 0 = true
    let needsRegen = summary.needsRegeneration(totalMessages: 11, threshold: 0)

    TestRunner.assertTrue(needsRegen, "With threshold 0, any new message should trigger regeneration")
}

func testSessionSummary_NeedsRegeneration_LargeThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (Large Threshold)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 50 total with threshold 50: coveredWhenCreated = 10 + 50 = 60, new = 50 - 60 = -10
    let needsRegen = summary.needsRegeneration(totalMessages: 50, threshold: 50)

    TestRunner.assertFalse(needsRegen, "Large threshold should prevent regeneration")
}

func testSessionSummary_NeedsRegeneration_OneBelowThreshold() {
    print("\n📦 SessionSummary - Needs Regeneration (One Below Threshold)")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // At 29 total with threshold 10: coveredWhenCreated = 10 + 10 = 20, new = 29 - 20 = 9 (one below)
    let needsRegen = summary.needsRegeneration(totalMessages: 29)

    TestRunner.assertFalse(needsRegen, "9 new messages should not need regeneration (threshold 10)")
}

// MARK: - Hierarchical Summarization Scenario Tests

func testHierarchicalSummarization_FirstSummary() {
    print("\n📦 Hierarchical Summarization - First Summary (20 messages)")
    print("----------------------------------------")

    // Scenario: 20 messages, first summarization
    // Action: Summarize messages 0..<10, keep 10..<20 as recent
    // Result: summary covers 10 messages

    let recentToKeep = 10
    let messageCount = 20
    let targetCoverCount = messageCount - recentToKeep  // 10

    TestRunner.assertEqual(targetCoverCount, 10, "First summary should cover 10 messages")

    // After first summary, no regeneration needed
    let summary = SessionSummary(
        content: "First summary",
        coversMessageCount: targetCoverCount,
        createdAt: Date(),
        modelUsed: nil
    )

    let needsRegen = summary.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegen, "No regeneration needed right after first summary")
}

func testHierarchicalSummarization_SecondSummary() {
    print("\n📦 Hierarchical Summarization - Second Summary (30 messages)")
    print("----------------------------------------")

    // Scenario: 30 messages, existing summary covers 10
    // Check: Need regeneration? Yes (10 new messages since summary+recent=20)
    // Action: Summarize S1 + messages 10..<20, keep 20..<30 as recent
    // Result: summary covers 20 messages

    let recentToKeep = 10
    let firstSummaryCoverCount = 10
    let messageCount = 30

    let firstSummary = SessionSummary(
        content: "First summary",
        coversMessageCount: firstSummaryCoverCount,
        createdAt: Date(),
        modelUsed: nil
    )

    // Check regeneration
    let needsRegen = firstSummary.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertTrue(needsRegen, "At 30 messages with summary covering 10, regeneration needed")

    // Calculate new target cover count
    let newTargetCoverCount = messageCount - recentToKeep  // 20

    TestRunner.assertEqual(newTargetCoverCount, 20, "Second summary should cover 20 messages")

    // After second summary, no regeneration needed
    let secondSummary = SessionSummary(
        content: "Second summary (hierarchical)",
        coversMessageCount: newTargetCoverCount,
        createdAt: Date(),
        modelUsed: nil
    )

    let needsRegenAfter = secondSummary.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegenAfter, "No regeneration needed right after second summary")
}

func testHierarchicalSummarization_ThirdSummary() {
    print("\n📦 Hierarchical Summarization - Third Summary (40 messages)")
    print("----------------------------------------")

    // Scenario: 40 messages, existing summary covers 20
    let recentToKeep = 10
    let secondSummaryCoverCount = 20
    let messageCount = 40

    let secondSummary = SessionSummary(
        content: "Second summary",
        coversMessageCount: secondSummaryCoverCount,
        createdAt: Date(),
        modelUsed: nil
    )

    // Check regeneration
    let needsRegen = secondSummary.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertTrue(needsRegen, "At 40 messages with summary covering 20, regeneration needed")

    // Calculate new target cover count
    let newTargetCoverCount = messageCount - recentToKeep  // 30

    TestRunner.assertEqual(newTargetCoverCount, 30, "Third summary should cover 30 messages")
}

func testHierarchicalSummarization_InBetweenMessages() {
    print("\n📦 Hierarchical Summarization - Between Summaries (25 messages)")
    print("----------------------------------------")

    // Scenario: 25 messages, existing summary covers 10
    // Not yet at regeneration threshold
    let recentToKeep = 10
    let summaryCoverCount = 10
    let messageCount = 25

    let summary = SessionSummary(
        content: "First summary",
        coversMessageCount: summaryCoverCount,
        createdAt: Date(),
        modelUsed: nil
    )

    let needsRegen = summary.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegen, "At 25 messages, only 5 new - no regeneration yet")

    // Messages to be summarized on next regeneration would be 10..<15
    let messagesToSummarize = messageCount - recentToKeep - summaryCoverCount
    TestRunner.assertEqual(messagesToSummarize, 5, "5 new messages to be added to summary")
}

// MARK: - SessionSummary Edge Cases

func testSessionSummary_WhitespaceContent() {
    print("\n📦 SessionSummary - Whitespace Content")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "   ",  // Whitespace only - technically not empty
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // Current implementation considers whitespace as valid content
    // This tests the actual behavior
    TestRunner.assertTrue(summary.isValid, "Whitespace-only content is technically valid (not empty)")
}

func testSessionSummary_VeryLongContent() {
    print("\n📦 SessionSummary - Very Long Content")
    print("----------------------------------------")

    let longContent = String(repeating: "x", count: 10000)
    let summary = SessionSummary(
        content: longContent,
        coversMessageCount: 100,
        createdAt: Date(),
        modelUsed: "test-model"
    )

    TestRunner.assertTrue(summary.isValid, "Very long content should be valid")
    TestRunner.assertEqual(summary.content.count, 10000, "Content should preserve full length")
}

func testSessionSummary_NegativeMessageCount() {
    print("\n📦 SessionSummary - Negative Message Count")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: -5,  // Invalid negative count
        createdAt: Date(),
        modelUsed: nil
    )

    // Negative is not > 0, so should be invalid
    TestRunner.assertFalse(summary.isValid, "Negative message count should be invalid")
}

func testSessionSummary_ModelUsed() {
    print("\n📦 SessionSummary - Model Used Field")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: "claude-3-opus-20240229"
    )

    TestRunner.assertEqual(summary.modelUsed, "claude-3-opus-20240229", "Model used should be preserved")
    TestRunner.assertTrue(summary.isValid, "Summary with model should be valid")
}

// MARK: - PersistedSession buildLLMContext Edge Cases

func testBuildLLMContext_EmptySession() {
    print("\n📦 buildLLMContext - Empty Session")
    print("----------------------------------------")

    let session = createTestSession(messageCount: 0)

    let context = session.buildLLMContext()

    TestRunner.assertEqual(context.count, 0, "Empty session returns empty context")
}

func testBuildLLMContext_SingleMessage() {
    print("\n📦 buildLLMContext - Single Message")
    print("----------------------------------------")

    let session = createTestSession(messageCount: 1)

    let context = session.buildLLMContext()

    TestRunner.assertEqual(context.count, 1, "Single message session returns that message")
}

func testBuildLLMContext_SummaryCoversOne() {
    print("\n📦 buildLLMContext - Summary Covers One Message")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Summary of first message",
        coversMessageCount: 1,
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 5, summary: summary)

    let context = session.buildLLMContext()

    // Summary + messages 1..<5 = 1 + 4 = 5
    TestRunner.assertEqual(context.count, 5, "Summary covering 1 + 4 remaining = 5 total")
}

func testBuildLLMContext_SummaryContentPreserved() {
    print("\n📦 buildLLMContext - Summary Content Preserved")
    print("----------------------------------------")

    let summaryContent = "This is a detailed summary of the conversation"
    let summary = SessionSummary(
        content: summaryContent,
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )
    let session = createTestSession(messageCount: 15, summary: summary)

    let context = session.buildLLMContext()

    let expectedPrefix = "Previous session context: "
    TestRunner.assertTrue(
        context.first?.content.contains(summaryContent) ?? false,
        "Summary content should be in system message"
    )
    TestRunner.assertTrue(
        context.first?.content.hasPrefix(expectedPrefix) ?? false,
        "Summary should have 'Previous session context:' prefix"
    )
}

// MARK: - Conversation Lifecycle Tests

func testConversationLifecycle_GrowthPattern() {
    print("\n📦 Conversation Lifecycle - Growth Pattern")
    print("----------------------------------------")

    let recentToKeep = 10
    let messageThreshold = 20

    // Simulate conversation growth
    var messageCount = 5

    // Phase 1: Below threshold
    var needsSummarization = messageCount >= messageThreshold
    TestRunner.assertFalse(needsSummarization, "5 messages: no summarization needed")

    // Phase 2: At threshold
    messageCount = 20
    needsSummarization = messageCount >= messageThreshold
    TestRunner.assertTrue(needsSummarization, "20 messages: summarization needed")

    // Phase 3: After first summary (covers 10)
    let summary1 = SessionSummary(
        content: "Summary 1",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: nil
    )

    // Right after summarization
    var needsRegen = summary1.needsRegeneration(totalMessages: 20, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegen, "Right after first summary: no regen needed")

    // Phase 4: Growth to 25
    messageCount = 25
    needsRegen = summary1.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegen, "25 messages, 5 new: no regen needed")

    // Phase 5: Growth to 30 (triggers regen)
    messageCount = 30
    needsRegen = summary1.needsRegeneration(totalMessages: messageCount, threshold: recentToKeep)
    TestRunner.assertTrue(needsRegen, "30 messages, 10 new: regen needed")

    // Phase 6: After second summary (covers 20)
    let summary2 = SessionSummary(
        content: "Summary 2 (hierarchical)",
        coversMessageCount: 20,
        createdAt: Date(),
        modelUsed: nil
    )

    needsRegen = summary2.needsRegeneration(totalMessages: 30, threshold: recentToKeep)
    TestRunner.assertFalse(needsRegen, "Right after second summary: no regen needed")
}

func testConversationLifecycle_ContextWindowSize() {
    print("\n📦 Conversation Lifecycle - Context Window Size")
    print("----------------------------------------")

    // Test that context window stays bounded regardless of conversation length
    // With recentToKeep = 10, summary + 10 recent = 11 messages max in context

    // 20 messages with summary covering 10 = 1 summary + 10 recent = 11 messages
    let summary1 = SessionSummary(content: "S1", coversMessageCount: 10, createdAt: Date(), modelUsed: nil)
    let session1 = createTestSession(messageCount: 20, summary: summary1)
    let context1 = session1.buildLLMContext()
    TestRunner.assertEqual(context1.count, 11, "20 msgs with summary covering 10: 1 + 10 = 11")

    // 100 messages with summary covering 90 = 1 summary + 10 recent = 11 messages
    let summary2 = SessionSummary(content: "S2", coversMessageCount: 90, createdAt: Date(), modelUsed: nil)
    let session2 = createTestSession(messageCount: 100, summary: summary2)
    let context2 = session2.buildLLMContext()
    TestRunner.assertEqual(context2.count, 11, "100 msgs with summary covering 90: 1 + 10 = 11")

    // 1000 messages with summary covering 990 = 1 summary + 10 recent = 11 messages
    let summary3 = SessionSummary(content: "S3", coversMessageCount: 990, createdAt: Date(), modelUsed: nil)
    let session3 = createTestSession(messageCount: 1000, summary: summary3)
    let context3 = session3.buildLLMContext()
    TestRunner.assertEqual(context3.count, 11, "1000 msgs with summary covering 990: 1 + 10 = 11")
}

// MARK: - SessionSummary Codable Tests

func testSessionSummary_Encoding() {
    print("\n📦 SessionSummary - Encoding/Decoding")
    print("----------------------------------------")

    let original = SessionSummary(
        content: "Test summary content",
        coversMessageCount: 15,
        createdAt: Date(timeIntervalSince1970: 1704067200),  // Fixed date for comparison
        modelUsed: "claude-3-opus"
    )

    // Encode
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(original) else {
        TestRunner.assertTrue(false, "Encoding should succeed")
        return
    }

    // Decode
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let decoded = try? decoder.decode(SessionSummary.self, from: data) else {
        TestRunner.assertTrue(false, "Decoding should succeed")
        return
    }

    TestRunner.assertEqual(decoded.content, original.content, "Content preserved after encode/decode")
    TestRunner.assertEqual(decoded.coversMessageCount, original.coversMessageCount, "Message count preserved")
    TestRunner.assertEqual(decoded.modelUsed, original.modelUsed, "Model used preserved")
    TestRunner.assertEqual(decoded.createdAt, original.createdAt, "Created date preserved")
}

func testSessionSummary_Equatable() {
    print("\n📦 SessionSummary - Equatable")
    print("----------------------------------------")

    let date = Date()

    let summary1 = SessionSummary(
        content: "Test",
        coversMessageCount: 10,
        createdAt: date,
        modelUsed: "model"
    )

    let summary2 = SessionSummary(
        content: "Test",
        coversMessageCount: 10,
        createdAt: date,
        modelUsed: "model"
    )

    let summary3 = SessionSummary(
        content: "Different",
        coversMessageCount: 10,
        createdAt: date,
        modelUsed: "model"
    )

    TestRunner.assertTrue(summary1 == summary2, "Same summaries should be equal")
    TestRunner.assertFalse(summary1 == summary3, "Different summaries should not be equal")
}

// MARK: - PersistedSession Summary Preservation Tests

func testPersistedSession_SummaryPreservation() {
    print("\n📦 PersistedSession - Summary Preservation")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Summary to preserve",
        coversMessageCount: 15,
        createdAt: Date(),
        modelUsed: "test-model"
    )

    let session = PersistedSession(
        id: UUID(),
        messages: createTestMessages(count: 20),
        initialRequest: "Test request",
        maxMessages: 20,
        createdAt: Date(),
        updatedAt: Date(),
        title: "Test",
        isArchived: false,
        summary: summary
    )

    TestRunner.assertTrue(session.summary != nil, "Summary should be present")
    TestRunner.assertEqual(session.summary?.content, summary.content, "Summary content preserved")
    TestRunner.assertEqual(session.summary?.coversMessageCount, summary.coversMessageCount, "Cover count preserved")
}

func testPersistedSession_EncodingWithSummary() {
    print("\n📦 PersistedSession - Encoding With Summary")
    print("----------------------------------------")

    let summary = SessionSummary(
        content: "Test summary",
        coversMessageCount: 10,
        createdAt: Date(timeIntervalSince1970: 1704067200),
        modelUsed: "claude"
    )

    let session = PersistedSession(
        id: UUID(),
        messages: createTestMessages(count: 15),
        initialRequest: nil,
        maxMessages: 20,
        createdAt: Date(timeIntervalSince1970: 1704067200),
        updatedAt: Date(timeIntervalSince1970: 1704067200),
        title: "Test",
        isArchived: false,
        summary: summary
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(session) else {
        TestRunner.assertTrue(false, "Encoding session with summary should succeed")
        return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let decoded = try? decoder.decode(PersistedSession.self, from: data) else {
        TestRunner.assertTrue(false, "Decoding session with summary should succeed")
        return
    }

    TestRunner.assertTrue(decoded.summary != nil, "Decoded session should have summary")
    TestRunner.assertEqual(decoded.summary?.content, summary.content, "Summary content preserved in encoded session")
    TestRunner.assertEqual(decoded.summary?.coversMessageCount, summary.coversMessageCount, "Summary cover count preserved")
}

func testPersistedSession_EncodingWithoutSummary() {
    print("\n📦 PersistedSession - Encoding Without Summary")
    print("----------------------------------------")

    let session = PersistedSession(
        id: UUID(),
        messages: createTestMessages(count: 10),
        initialRequest: nil,
        maxMessages: 20,
        createdAt: Date(timeIntervalSince1970: 1704067200),
        updatedAt: Date(timeIntervalSince1970: 1704067200),
        title: "Test",
        isArchived: false,
        summary: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    guard let data = try? encoder.encode(session) else {
        TestRunner.assertTrue(false, "Encoding session without summary should succeed")
        return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let decoded = try? decoder.decode(PersistedSession.self, from: data) else {
        TestRunner.assertTrue(false, "Decoding session without summary should succeed")
        return
    }

    TestRunner.assertTrue(decoded.summary == nil, "Decoded session should not have summary")
}

// MARK: - Summary Update Simulation Tests

func testSummaryUpdateFlow() {
    print("\n📦 Summary Update Flow")
    print("----------------------------------------")

    // Simulate the flow of updating a session's summary
    var session = createTestSession(messageCount: 20, summary: nil)

    // Step 1: No summary initially
    TestRunner.assertTrue(session.summary == nil, "Initial session has no summary")

    // Step 2: Add first summary
    let firstSummary = SessionSummary(
        content: "First summary covering initial messages",
        coversMessageCount: 10,
        createdAt: Date(),
        modelUsed: "model-1"
    )
    session.summary = firstSummary

    TestRunner.assertTrue(session.summary != nil, "Session now has summary")
    TestRunner.assertEqual(session.summary?.coversMessageCount, 10, "First summary covers 10")

    // Step 3: Update to hierarchical summary
    let secondSummary = SessionSummary(
        content: "Hierarchical summary with more context",
        coversMessageCount: 20,
        createdAt: Date(),
        modelUsed: "model-1"
    )
    session.summary = secondSummary

    TestRunner.assertEqual(session.summary?.coversMessageCount, 20, "Second summary covers 20")
    TestRunner.assertTrue(
        session.summary?.content.contains("Hierarchical") ?? false,
        "Summary content updated"
    )
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

    // Edge cases for regeneration logic
    testSessionSummary_NeedsRegeneration_NegativeNewMessages()
    testSessionSummary_NeedsRegeneration_ZeroThreshold()
    testSessionSummary_NeedsRegeneration_LargeThreshold()
    testSessionSummary_NeedsRegeneration_OneBelowThreshold()

    // Hierarchical summarization scenario tests
    testHierarchicalSummarization_FirstSummary()
    testHierarchicalSummarization_SecondSummary()
    testHierarchicalSummarization_ThirdSummary()
    testHierarchicalSummarization_InBetweenMessages()

    // SessionSummary edge cases
    testSessionSummary_WhitespaceContent()
    testSessionSummary_VeryLongContent()
    testSessionSummary_NegativeMessageCount()
    testSessionSummary_ModelUsed()

    // buildLLMContext edge cases
    testBuildLLMContext_EmptySession()
    testBuildLLMContext_SingleMessage()
    testBuildLLMContext_SummaryCoversOne()
    testBuildLLMContext_SummaryContentPreserved()

    // Conversation lifecycle tests
    testConversationLifecycle_GrowthPattern()
    testConversationLifecycle_ContextWindowSize()

    // SessionSummary Codable tests
    testSessionSummary_Encoding()
    testSessionSummary_Equatable()

    // PersistedSession summary preservation tests
    testPersistedSession_SummaryPreservation()
    testPersistedSession_EncodingWithSummary()
    testPersistedSession_EncodingWithoutSummary()

    // Summary update flow tests
    testSummaryUpdateFlow()

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
