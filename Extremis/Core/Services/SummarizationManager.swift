// MARK: - Summarization Manager
// Manages automatic session summarization for LLM context efficiency

import Foundation

/// Manager for session summarization (US3)
/// Triggers summarization when conversations exceed thresholds to keep LLM context manageable
@MainActor
final class SummarizationManager {

    // MARK: - Singleton
    static let shared = SummarizationManager()

    // MARK: - Configuration
    struct Config {
        /// Message count threshold to trigger summarization
        let messageThreshold: Int
        /// Estimated token threshold (1 token ≈ 4 chars)
        let tokenThreshold: Int
        /// Keep this many recent messages unsummarized
        let recentMessagesToKeep: Int
        /// Maximum summary length in characters
        let maxSummaryLength: Int

        static let `default` = Config(
            messageThreshold: 20,
            tokenThreshold: 8000,
            recentMessagesToKeep: 10,
            maxSummaryLength: 2000
        )
    }

    // MARK: - State
    private let config: Config
    private let providerRegistry: LLMProviderRegistry
    private let templateLoader: PromptTemplateLoader
    private var isSummarizing = false

    // MARK: - Initialization

    private init(
        config: Config = .default,
        providerRegistry: LLMProviderRegistry = .shared,
        templateLoader: PromptTemplateLoader = .shared
    ) {
        self.config = config
        self.providerRegistry = providerRegistry
        self.templateLoader = templateLoader
    }

    /// Initialize with custom config (for testing)
    static func forTesting(
        config: Config = .default,
        providerRegistry: LLMProviderRegistry = .shared,
        templateLoader: PromptTemplateLoader = .shared
    ) -> SummarizationManager {
        SummarizationManager(config: config, providerRegistry: providerRegistry, templateLoader: templateLoader)
    }

    // MARK: - Public API

    /// Check if session needs summarization
    /// - Parameter session: The persisted session to check
    /// - Returns: true if summarization should be triggered
    func needsSummarization(_ session: PersistedSession) -> Bool {
        // Skip if already summarizing
        guard !isSummarizing else { return false }

        // Check if existing summary needs regeneration
        if let summary = session.summary, summary.isValid {
            // Summary exists - check if too many new messages since
            return summary.needsRegeneration(
                totalMessages: session.messages.count,
                threshold: config.recentMessagesToKeep
            )
        }

        // No summary - check thresholds
        let messageCount = session.messages.count
        let estimatedTokens = estimateTokenCount(for: session)

        let needsIt = messageCount >= config.messageThreshold ||
                      estimatedTokens >= config.tokenThreshold

        if needsIt {
            print("[SummarizationManager] Session needs summarization: \(messageCount) messages, ~\(estimatedTokens) tokens")
        }

        return needsIt
    }

    /// Generate summary for a session
    /// - Parameter session: The session to summarize
    /// - Returns: Updated session with summary, or original if summarization fails
    /// - Note: Call `needsSummarization()` first to check if summarization is needed
    /// - Note: Uses hierarchical summarization when regenerating - combines previous summary with new messages
    func summarize(_ session: PersistedSession) async -> PersistedSession {
        guard let provider = providerRegistry.activeProvider else {
            print("[SummarizationManager] No active provider - skipping summarization")
            return session
        }

        isSummarizing = true
        defer { isSummarizing = false }

        // Calculate how many messages we want to cover (all except recent N)
        let totalMessages = session.messages.count
        let targetCoverCount = max(0, totalMessages - config.recentMessagesToKeep)

        // Get the existing summary (if any) for hierarchical summarization
        let existingSummary = session.summary

        // Determine which messages to summarize
        // If we have an existing summary, only summarize NEW messages since the summary
        // Otherwise, summarize all messages up to targetCoverCount
        let messagesToSummarize: [PersistedMessage]
        let isHierarchical: Bool

        if let summary = existingSummary, summary.isValid, summary.coversMessageCount > 0 {
            // Hierarchical: get messages from where summary left off to target
            let startIndex = summary.coversMessageCount
            let endIndex = targetCoverCount
            if startIndex < endIndex && endIndex <= session.messages.count {
                messagesToSummarize = Array(session.messages[startIndex..<endIndex])
                isHierarchical = true
            } else {
                print("[SummarizationManager] No new messages to add to summary")
                return session
            }
        } else {
            // First-time: get all messages up to targetCoverCount
            messagesToSummarize = Array(session.messages.prefix(targetCoverCount))
            isHierarchical = false
        }

        guard !messagesToSummarize.isEmpty else {
            print("[SummarizationManager] No messages to summarize")
            return session
        }

        if isHierarchical {
            print("[SummarizationManager] Hierarchical summarization: previous summary + \(messagesToSummarize.count) new messages")
        } else {
            print("[SummarizationManager] First-time summarization: \(messagesToSummarize.count) messages with \(provider.displayName)")
        }

        do {
            // Build summarization prompt (includes previous summary if hierarchical)
            let prompt = buildSummarizationPrompt(
                for: messagesToSummarize,
                previousSummary: isHierarchical ? existingSummary : nil
            )

            // Log the full prompt being sent
            print("\n" + String(repeating: "=", count: 80))
            print("📝 SUMMARIZATION PROMPT (isHierarchical: \(isHierarchical))")
            print(String(repeating: "=", count: 80))
            print(prompt)
            print(String(repeating: "=", count: 80) + "\n")

            // Generate summary using LLM
            let generation = try await provider.generateRaw(prompt: prompt)

            // Create summary object
            let summary = SessionSummary(
                content: generation.content.trimmingCharacters(in: .whitespacesAndNewlines),
                coversMessageCount: targetCoverCount,
                createdAt: Date(),
                modelUsed: provider.currentModel.id
            )

            print("[SummarizationManager] Generated summary covering \(summary.coversMessageCount) messages")
            print("\n" + String(repeating: "-", count: 80))
            print("📋 GENERATED SUMMARY:")
            print(String(repeating: "-", count: 80))
            print(summary.content)
            print(String(repeating: "-", count: 80) + "\n")

            // Return updated session
            var updatedSession = session
            updatedSession.summary = summary
            return updatedSession

        } catch {
            print("[SummarizationManager] Summarization failed: \(error)")
            // Return original session - don't block on summarization failures
            return session
        }
    }

    /// Summarize session if needed and save via SessionManager
    /// Call this after messages are added to a session
    /// - Parameters:
    ///   - session: The persisted session
    ///   - storage: The storage to save to
    /// - Returns: Updated session (with or without new summary)
    func summarizeIfNeeded(
        _ session: PersistedSession,
        storage: any SessionStorage
    ) async -> PersistedSession {
        guard needsSummarization(session) else {
            return session
        }

        let updatedSession = await summarize(session)

        // Only save if summary was actually generated
        if updatedSession.summary != nil && updatedSession.summary != session.summary {
            do {
                try await storage.saveSession(updatedSession)
                print("[SummarizationManager] Saved session with new summary")
            } catch {
                print("[SummarizationManager] Failed to save summarized session: \(error)")
            }
        }

        return updatedSession
    }

    // MARK: - Private Helpers

    /// Estimate token count for a session (rough: 1 token ≈ 4 chars)
    private func estimateTokenCount(for session: PersistedSession) -> Int {
        let totalChars = session.messages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }

    /// Build the summarization prompt
    /// - Parameters:
    ///   - messages: New messages to incorporate into the summary
    ///   - previousSummary: Optional existing summary for hierarchical summarization
    private func buildSummarizationPrompt(
        for messages: [PersistedMessage],
        previousSummary: SessionSummary? = nil
    ) -> String {
        // Format messages as conversation transcript
        let transcript = messages.map { message -> String in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role): \(message.content)"
        }.joined(separator: "\n\n")

        // Build the content to summarize
        let contentToSummarize: String
        if let summary = previousSummary {
            // Hierarchical: previous summary + new messages
            contentToSummarize = """
            PREVIOUS SUMMARY (covering earlier messages):
            \(summary.content)

            NEW MESSAGES TO INCORPORATE:
            \(transcript)
            """
        } else {
            // First-time: just the messages
            contentToSummarize = transcript
        }

        // Build the appropriate prompt based on whether this is hierarchical
        let instructions: String
        if previousSummary != nil {
            instructions = """
            Update this conversation summary with new messages.

            ## Task
            Integrate the previous summary with the new messages to create a unified, updated summary.

            ## What to Capture
            - **Key Facts**: Names, dates, numbers, file paths, technical specifications
            - **User Preferences**: Stated preferences for tone, format, or approach
            - **Decisions**: Solutions agreed upon, problems resolved
            - **Open Items**: Pending tasks, unresolved questions

            ## Guidelines
            - Under 400 words, organized by relevance
            - Preserve important context from the previous summary
            - Add new topics, decisions, or details from recent messages
            - Remove outdated information if superseded by new messages
            - Be direct and factual - no meta-commentary
            - Preserve exact values rather than paraphrasing
            """
        } else {
            instructions = """
            Create a memory summary for continuing this conversation later.

            ## What to Capture
            - **Key Facts**: Names, dates, numbers, file paths, technical specifications
            - **User Preferences**: Stated preferences for tone, format, or approach
            - **Decisions**: Solutions agreed upon, problems resolved
            - **Open Items**: Pending tasks, unresolved questions

            ## Guidelines
            - Under 400 words, organized by relevance
            - Be direct and factual - no "In this conversation..." or "The user discussed..."
            - Preserve exact values (names, paths, numbers) rather than paraphrasing
            - Focus on information needed to continue the conversation effectively
            """
        }

        return """
        \(instructions)

        Content to summarize:

        \(contentToSummarize)

        Summary:
        """
    }
}
