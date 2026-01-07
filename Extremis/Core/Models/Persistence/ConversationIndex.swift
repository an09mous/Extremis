// MARK: - Conversation Index Models
// Lightweight index for fast session listing without loading full conversation files

import Foundation

// MARK: - Conversation Index Entry

/// Index entry for a single conversation (for fast listing)
struct ConversationIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID                        // Matches conversation file name
    var title: String                   // Display title (auto-generated or user-edited)
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last activity (for sorting)
    var messageCount: Int               // Total messages (for display)
    var preview: String?                // First user message, truncated to ~100 chars
    var isArchived: Bool                // Soft-delete flag (mirrors conversation)

    // MARK: - Coding Keys (backward compatibility with old schema)

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messageCount, preview, isArchived
        // Old schema used "lastModifiedAt" instead of "updatedAt"
        case lastModifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Try new key first, fall back to old key
        if let updated = try? container.decode(Date.self, forKey: .updatedAt) {
            updatedAt = updated
        } else {
            updatedAt = try container.decode(Date.self, forKey: .lastModifiedAt)
        }
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encode(isArchived, forKey: .isArchived)
    }

    // MARK: - Initialization

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int,
        preview: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
        self.isArchived = isArchived
    }

    /// Create entry from a PersistedConversation
    init(from conversation: PersistedConversation) {
        self.id = conversation.id
        self.title = conversation.title ?? Self.generateTitle(from: conversation)
        self.createdAt = conversation.createdAt
        self.updatedAt = conversation.updatedAt
        self.messageCount = conversation.messages.count
        self.preview = Self.generatePreview(from: conversation)
        self.isArchived = conversation.isArchived
    }

    // MARK: - Helpers

    /// Generate title from first message in the conversation
    private static func generateTitle(from conversation: PersistedConversation) -> String {
        // Use first message content, regardless of role
        if let firstMessage = conversation.messages.first, !firstMessage.content.isEmpty {
            return truncateForTitle(firstMessage.content)
        }
        return "New Conversation"
    }

    /// Truncate text for title (max 50 chars, word boundary)
    private static func truncateForTitle(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 {
            return trimmed
        }
        let truncated = String(trimmed.prefix(50))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    /// Generate preview from first user message or context
    private static func generatePreview(from conversation: PersistedConversation) -> String? {
        // Priority 1: First user message
        if let firstUserMessage = conversation.firstUserMessage, !firstUserMessage.content.isEmpty {
            return truncateForPreview(firstUserMessage.content)
        }

        // Priority 2: Initial request
        if let initialRequest = conversation.initialRequest, !initialRequest.isEmpty {
            return truncateForPreview(initialRequest)
        }

        // Priority 3: Selected text from context
        if let firstMessage = conversation.messages.first,
           let context = firstMessage.decodeContext(),
           let selectedText = context.selectedText, !selectedText.isEmpty {
            return truncateForPreview(selectedText)
        }

        return nil
    }

    /// Truncate text for preview (max 100 chars)
    private static func truncateForPreview(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 100 {
            return trimmed
        }
        return String(trimmed.prefix(100)) + "…"
    }
}

// MARK: - Conversation Index

/// Index file containing all conversation metadata
struct ConversationIndex: Codable, Equatable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?     // Currently open conversation
    var lastUpdated: Date

    static let currentVersion = 1

    // MARK: - Codable (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case version, conversations, activeConversationId, lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        conversations = try container.decode([ConversationIndexEntry].self, forKey: .conversations)
        activeConversationId = try container.decodeIfPresent(UUID.self, forKey: .activeConversationId)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    // MARK: - Initialization

    init(
        version: Int = Self.currentVersion,
        conversations: [ConversationIndexEntry] = [],
        activeConversationId: UUID? = nil,
        lastUpdated: Date = Date()
    ) {
        self.version = version
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.lastUpdated = lastUpdated
    }

    // MARK: - Query Helpers

    /// Get non-archived conversations sorted by most recent
    var activeConversations: [ConversationIndexEntry] {
        conversations
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Get archived conversations
    var archivedConversations: [ConversationIndexEntry] {
        conversations
            .filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Find entry by ID
    func entry(for id: UUID) -> ConversationIndexEntry? {
        conversations.first { $0.id == id }
    }

    /// Check if conversation exists
    func contains(id: UUID) -> Bool {
        conversations.contains { $0.id == id }
    }

    // MARK: - Mutation Helpers

    /// Update or insert an entry
    mutating func upsert(_ entry: ConversationIndexEntry) {
        if let index = conversations.firstIndex(where: { $0.id == entry.id }) {
            conversations[index] = entry
        } else {
            conversations.append(entry)
        }
        lastUpdated = Date()
    }

    /// Remove entry by ID
    mutating func remove(id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
        }
        lastUpdated = Date()
    }
}
