// MARK: - Persisted Message Model
// Message model for persistence with per-message context support

import Foundation

/// A single message in a persisted conversation
/// Uses contextData for compact JSON storage while ChatMessage uses Context directly
struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?  // Encoded Context (optional, for user messages)

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        contextData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
    }

    // MARK: - Convenience Initializers

    /// Create from existing ChatMessage (context is embedded in message)
    init(from message: ChatMessage) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = Self.encodeContext(message.context)
    }

    /// Convert to ChatMessage (restores embedded context)
    func toChatMessage() -> ChatMessage {
        ChatMessage(id: id, role: role, content: content, timestamp: timestamp, context: decodeContext())
    }

    // MARK: - Context Helpers

    /// Decode context if present
    func decodeContext() -> Context? {
        guard let data = contextData else { return nil }
        return try? JSONDecoder().decode(Context.self, from: data)
    }

    /// Encode context to Data
    static func encodeContext(_ context: Context?) -> Data? {
        guard let context = context else { return nil }
        return try? JSONEncoder().encode(context)
    }

    /// Check if message has context attached
    var hasContext: Bool {
        contextData != nil
    }
}
