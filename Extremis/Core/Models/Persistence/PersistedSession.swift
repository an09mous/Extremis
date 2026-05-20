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

        // Defensive: validate summary consistency
        // This catches edge cases where summary state got out of sync (e.g., after retry)
        if summary.coversMessageCount > messages.count {
            print("[PersistedSession] Warning: summary.coversMessageCount (\(summary.coversMessageCount)) > messages.count (\(messages.count)) - using all messages")
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
    /// Create from live ChatSession, saving images to disk
    /// - Parameters:
    ///   - session: The live session
    ///   - id: Existing ID (for updates) or nil (for new)
    ///   - currentContext: Current context (fallback for originalContext if not set)
    @MainActor
    static func from(
        _ session: ChatSession,
        id: UUID? = nil,
        currentContext: Context? = nil
    ) async -> PersistedSession {
        // Convert messages - save images to disk for messages that have them
        var persistedMessages: [PersistedMessage] = []
        for message in session.messages {
            if message.hasImages, let images = message.imageAttachments {
                // Save images to disk and create refs
                do {
                    let refs = try await ImagePersistence.shared.save(images)
                    persistedMessages.append(PersistedMessage(from: message, imageRefs: refs))
                } catch {
                    print("[PersistedSession] Failed to save images for message \(message.id): \(error)")
                    persistedMessages.append(PersistedMessage(from: message))
                }
            } else {
                persistedMessages.append(PersistedMessage(from: message))
            }
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

    /// Convert to live ChatSession, restoring images from disk
    @MainActor
    func toSession() async -> ChatSession {
        // Extract original context from first user message
        let originalContext = firstUserMessage?.decodeContext()

        let session = ChatSession(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages,
            summary: summary,
            summaryCoversCount: summary?.coversMessageCount ?? 0
        )

        // Restore messages with embedded context and images
        for message in messages {
            if message.hasImages, let refs = message.imageRefs {
                // Restore images from disk (per-image errors are logged internally)
                let attachments = await ImagePersistence.shared.restore(from: refs)
                session.messages.append(message.toChatMessage(imageAttachments: attachments.isEmpty ? nil : attachments))
            } else {
                session.messages.append(message.toChatMessage())
            }
        }

        return session
    }
}
