// MARK: - Persisted Conversation Model
// Primary model for storing conversation state

import Foundation

/// Codable representation of a conversation for persistence
/// Separate from ChatConversation to avoid polluting the live UI model
struct PersistedConversation: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID                        // Conversation identifier (generated on first save)
    let version: Int                    // Schema version for migrations

    // MARK: - Core Data
    var messages: [PersistedMessage]    // ALL messages with per-message context
    let initialRequest: String?         // Original user instruction (first invocation)
    let maxMessages: Int                // Max messages setting (for LLM context, not storage)

    // MARK: - Metadata
    let createdAt: Date                 // When conversation started (immutable)
    var updatedAt: Date                 // Last modification time
    var title: String?                  // Auto-generated or user-edited title
    var isArchived: Bool                // Soft-delete flag (future: archive old conversations)

    // MARK: - Summary State (P2)
    var summary: ConversationSummary?   // Embedded summary for LLM context efficiency

    // MARK: - Schema Version
    static let currentVersion = 1

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        version: Int = Self.currentVersion,
        messages: [PersistedMessage] = [],
        initialRequest: String? = nil,
        maxMessages: Int = 20,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        isArchived: Bool = false,
        summary: ConversationSummary? = nil
    ) {
        self.id = id
        self.version = version
        self.messages = messages
        self.initialRequest = initialRequest
        self.maxMessages = maxMessages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.isArchived = isArchived
        self.summary = summary
    }

    // MARK: - Computed Properties

    /// Whether conversation has any user content
    var hasContent: Bool {
        messages.contains { $0.role == .user || $0.role == .assistant }
    }

    /// First user message (for title generation, preview)
    var firstUserMessage: PersistedMessage? {
        messages.first { $0.role == .user }
    }

    /// Last message timestamp (for sorting)
    var lastMessageAt: Date? {
        messages.last?.timestamp
    }

    // MARK: - LLM Context Building

    /// Build messages array for LLM API call (uses summary if available)
    /// Returns: Array of messages optimized for LLM context window
    func buildLLMContext() -> [PersistedMessage] {
        guard let summary = summary, summary.isValid else {
            // No valid summary - return all messages
            return messages
        }

        // Use summary + messages after the summarized portion
        let summaryMessage = PersistedMessage(
            id: UUID(),
            role: .system,
            content: "Previous conversation context: \(summary.content)",
            timestamp: summary.createdAt,
            contextData: nil
        )

        let recentMessages = Array(messages.suffix(from: min(summary.coversMessageCount, messages.count)))
        return [summaryMessage] + recentMessages
    }

    /// Estimate token count for LLM context (rough: 1 token ≈ 4 chars)
    func estimateTokenCount() -> Int {
        let contextMessages = buildLLMContext()
        let totalChars = contextMessages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
}

// MARK: - Conversion Extensions

extension PersistedConversation {
    /// Create from live ChatConversation
    /// - Parameters:
    ///   - conversation: The live conversation
    ///   - id: Existing ID (for updates) or nil (for new)
    ///   - currentContext: Current context to attach to latest user message
    @MainActor
    static func from(
        _ conversation: ChatConversation,
        id: UUID? = nil,
        currentContext: Context? = nil
    ) -> PersistedConversation {
        // Convert messages with context attachment
        let persistedMessages = conversation.messages.enumerated().map { index, message -> PersistedMessage in
            var contextData: Data? = nil

            // Attach context to user messages
            // First user message gets originalContext, latest user message gets currentContext
            if message.role == .user {
                if index == conversation.messages.firstIndex(where: { $0.role == .user }) {
                    // First user message - use original context
                    if let ctx = conversation.originalContext {
                        contextData = PersistedMessage.encodeContext(ctx)
                    }
                } else if index == conversation.messages.lastIndex(where: { $0.role == .user }) {
                    // Latest user message - use current context if provided
                    if let ctx = currentContext {
                        contextData = PersistedMessage.encodeContext(ctx)
                    }
                }
            }

            return PersistedMessage(from: message, contextData: contextData)
        }

        return PersistedConversation(
            id: id ?? UUID(),
            messages: persistedMessages,
            initialRequest: conversation.initialRequest,
            maxMessages: conversation.maxMessages,
            title: nil  // Will be auto-generated from first user message
        )
    }

    /// Convert to live ChatConversation
    @MainActor
    func toConversation() -> ChatConversation {
        // Extract original context from first user message
        let originalContext = firstUserMessage?.decodeContext()

        let conversation = ChatConversation(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )

        // Restore messages (avoid triggering trimIfNeeded for each)
        for message in messages {
            conversation.messages.append(message.toChatMessage())
        }

        return conversation
    }
}
