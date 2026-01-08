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
    func needsRegeneration(totalMessages: Int, threshold: Int = 10) -> Bool {
        let newMessagesSinceSummary = totalMessages - coversMessageCount
        return newMessagesSinceSummary >= threshold
    }
}
