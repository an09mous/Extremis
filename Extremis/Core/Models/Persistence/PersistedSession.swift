// MARK: - Persisted Session Model
// Primary model for storing session state

import Foundation

/// Codable representation of a session for persistence
/// Separate from ChatSession to avoid polluting the live UI model
struct PersistedSession: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID                        // Session identifier (generated on first save)
    let version: Int                    // Schema version for migrations

    // MARK: - Core Data
    var messages: [PersistedMessage]    // ALL messages with per-message context
    let initialRequest: String?         // Original user instruction (first invocation)
    let maxMessages: Int                // Max messages setting (for LLM context, not storage)

    // MARK: - Metadata
    let createdAt: Date                 // When session started (immutable)
    var updatedAt: Date                 // Last modification time
    var title: String?                  // Auto-generated or user-edited title
    var isArchived: Bool                // Soft-delete flag (future: archive old sessions)

    // MARK: - Summary State (P2)
    var summary: SessionSummary?        // Embedded summary for LLM context efficiency

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
        summary: SessionSummary? = nil
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

    /// First user message (for title generation, preview)
    var firstUserMessage: PersistedMessage? {
        messages.first { $0.role == .user }
    }

    // MARK: - LLM Context Building (for future summarization - US3)

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
            content: "Previous session context: \(summary.content)",
            timestamp: summary.createdAt,
            contextData: nil
        )

        let recentMessages = Array(messages.suffix(from: min(summary.coversMessageCount, messages.count)))
        return [summaryMessage] + recentMessages
    }
}

// MARK: - Conversion Extensions

extension PersistedSession {
    /// Create from live ChatSession
    /// - Parameters:
    ///   - session: The live session
    ///   - id: Existing ID (for updates) or nil (for new)
    ///   - currentContext: Current context to attach to latest user message (fallback)
    ///   - messageContexts: Dictionary mapping message IDs to their contexts
    @MainActor
    static func from(
        _ session: ChatSession,
        id: UUID? = nil,
        currentContext: Context? = nil,
        messageContexts: [UUID: Context] = [:]
    ) -> PersistedSession {
        // Convert messages with context attachment
        let persistedMessages = session.messages.enumerated().map { index, message -> PersistedMessage in
            var contextData: Data? = nil

            // Attach context to user messages
            if message.role == .user {
                // Priority 1: Use context from messageContexts dictionary (per-message tracking)
                if let ctx = messageContexts[message.id] {
                    contextData = PersistedMessage.encodeContext(ctx)
                }
                // Priority 2: First user message - use original context
                else if index == session.messages.firstIndex(where: { $0.role == .user }) {
                    if let ctx = session.originalContext {
                        contextData = PersistedMessage.encodeContext(ctx)
                    }
                }
                // Priority 3: Latest user message - use current context if provided
                else if index == session.messages.lastIndex(where: { $0.role == .user }) {
                    if let ctx = currentContext {
                        contextData = PersistedMessage.encodeContext(ctx)
                    }
                }
            }

            return PersistedMessage(from: message, contextData: contextData)
        }

        return PersistedSession(
            id: id ?? UUID(),
            messages: persistedMessages,
            initialRequest: session.initialRequest,
            maxMessages: session.maxMessages,
            title: nil,  // Will be auto-generated from first user message
            summary: session.summary
        )
    }

    /// Convert to live ChatSession
    @MainActor
    func toSession() -> ChatSession {
        // Extract original context from first user message
        let originalContext = firstUserMessage?.decodeContext()

        let session = ChatSession(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages,
            summary: summary,
            summaryCoversCount: summary?.coversMessageCount ?? 0
        )

        // Restore messages (avoid triggering trimIfNeeded for each)
        for message in messages {
            session.messages.append(message.toChatMessage())
        }

        return session
    }

    /// Restore message contexts dictionary from persisted messages
    /// Used when loading a session to restore context viewing capability
    func restoreMessageContexts() -> [UUID: Context] {
        var contexts: [UUID: Context] = [:]
        for message in messages {
            if message.role == .user, let context = message.decodeContext() {
                contexts[message.id] = context
            }
        }
        return contexts
    }
}
