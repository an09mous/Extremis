// MARK: - Session Index Models
// Lightweight index for fast session listing without loading full session files

import Foundation

// MARK: - Session Index Entry

/// Index entry for a single session (for fast listing)
struct SessionIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID                        // Matches session file name
    var title: String                   // Display title (auto-generated or user-edited)
    let createdAt: Date                 // When session started
    var updatedAt: Date                 // Last activity (for sorting)
    var messageCount: Int               // Total messages (for display)
    var preview: String?                // First user message, truncated to ~100 chars
    var isArchived: Bool                // Soft-delete flag (mirrors session)

    // MARK: - Coding Keys (backward compatibility with old schema)

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messageCount, preview, isArchived
        // Old schema used "lastModifiedAt" instead of "updatedAt"
        case lastModifiedAt
        // Backward compatibility: old key name was "conversations"
        case conversations
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

    /// Create entry from a PersistedSession
    init(from session: PersistedSession) {
        self.id = session.id
        self.title = session.title ?? Self.generateTitle(from: session)
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.messageCount = session.messages.count
        self.preview = Self.generatePreview(from: session)
        self.isArchived = session.isArchived
    }

    // MARK: - Helpers

    /// Generate title from first message in the session
    private static func generateTitle(from session: PersistedSession) -> String {
        // Use first message content, regardless of role
        if let firstMessage = session.messages.first, !firstMessage.content.isEmpty {
            return truncateForTitle(firstMessage.content)
        }
        return "New Session"
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
    private static func generatePreview(from session: PersistedSession) -> String? {
        // Priority 1: First user message
        if let firstUserMessage = session.firstUserMessage, !firstUserMessage.content.isEmpty {
            return truncateForPreview(firstUserMessage.content)
        }

        // Priority 2: Initial request
        if let initialRequest = session.initialRequest, !initialRequest.isEmpty {
            return truncateForPreview(initialRequest)
        }

        // Priority 3: Selected text from context
        if let firstMessage = session.messages.first,
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

// MARK: - Session Index

/// Index file containing all session metadata
struct SessionIndex: Codable, Equatable {
    let version: Int
    var sessions: [SessionIndexEntry]
    var activeSessionId: UUID?     // Currently open session
    var lastUpdated: Date

    static let currentVersion = 1

    // MARK: - Codable (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case version, sessions, activeSessionId, lastUpdated
        // Backward compatibility with old schema
        case conversations, activeConversationId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        // Try new key first, fall back to old key
        if let newSessions = try? container.decode([SessionIndexEntry].self, forKey: .sessions) {
            sessions = newSessions
        } else {
            sessions = try container.decode([SessionIndexEntry].self, forKey: .conversations)
        }

        // Try new key first, fall back to old key
        if let newActiveId = try? container.decodeIfPresent(UUID.self, forKey: .activeSessionId) {
            activeSessionId = newActiveId
        } else {
            activeSessionId = try container.decodeIfPresent(UUID.self, forKey: .activeConversationId)
        }

        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(sessions, forKey: .sessions)
        try container.encodeIfPresent(activeSessionId, forKey: .activeSessionId)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    // MARK: - Initialization

    init(
        version: Int = Self.currentVersion,
        sessions: [SessionIndexEntry] = [],
        activeSessionId: UUID? = nil,
        lastUpdated: Date = Date()
    ) {
        self.version = version
        self.sessions = sessions
        self.activeSessionId = activeSessionId
        self.lastUpdated = lastUpdated
    }

    // MARK: - Query Helpers

    /// Get non-archived sessions sorted by most recent
    var activeSessions: [SessionIndexEntry] {
        sessions
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Get archived sessions
    var archivedSessions: [SessionIndexEntry] {
        sessions
            .filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Find entry by ID
    func entry(for id: UUID) -> SessionIndexEntry? {
        sessions.first { $0.id == id }
    }

    /// Check if session exists
    func contains(id: UUID) -> Bool {
        sessions.contains { $0.id == id }
    }

    // MARK: - Mutation Helpers

    /// Update or insert an entry
    mutating func upsert(_ entry: SessionIndexEntry) {
        if let index = sessions.firstIndex(where: { $0.id == entry.id }) {
            sessions[index] = entry
        } else {
            sessions.append(entry)
        }
        lastUpdated = Date()
    }

    /// Remove entry by ID
    mutating func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = nil
        }
        lastUpdated = Date()
    }
}
