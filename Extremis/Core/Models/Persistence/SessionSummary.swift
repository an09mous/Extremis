// MARK: - Session Summary Model
// Summary of older messages for LLM context efficiency

import Foundation

/// Summary of older messages for LLM context efficiency
struct SessionSummary: Codable, Equatable {
    let content: String             // The summary text
    let coversMessageCount: Int     // Number of messages summarized
    let createdAt: Date             // When summary was generated
    let modelUsed: String?          // Which LLM generated the summary (for debugging)

    // MARK: - Initialization

    init(
        content: String,
        coversMessageCount: Int,
        createdAt: Date = Date(),
        modelUsed: String? = nil
    ) {
        self.content = content
        self.coversMessageCount = coversMessageCount
        self.createdAt = createdAt
        self.modelUsed = modelUsed
    }

    /// Check if summary is still valid (covers at least some messages)
    var isValid: Bool {
        coversMessageCount > 0 && !content.isEmpty
    }

    /// Check if summary needs regeneration (too many new messages since)
    /// Regeneration is needed when there are `threshold` NEW messages beyond what the summary + recent messages covered.
    /// Example: summary covers 10 messages, threshold is 10 (recent to keep)
    /// - At 20 messages: 10 summarized + 10 recent = covered, no regen needed
    /// - At 30 messages: 10 summarized + 10 recent = 20 covered, 10 new → regenerate
    func needsRegeneration(totalMessages: Int, threshold: Int = 10) -> Bool {
        // Total messages covered when summary was created = summarized + recent kept
        let coveredWhenCreated = coversMessageCount + threshold
        // New messages since summary was created
        let newMessagesSinceSummary = totalMessages - coveredWhenCreated
        // Only regenerate if we have `threshold` or more NEW messages
        return newMessagesSinceSummary >= threshold
    }
}
