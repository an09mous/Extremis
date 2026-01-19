// MARK: - Persisted Message Model
// Message model for persistence with per-message context and tool execution support

import Foundation

/// A single message in a persisted conversation
/// Uses contextData for compact JSON storage while ChatMessage uses Context directly
/// For assistant messages, also stores tool execution history (toolRoundsData)
struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?  // Encoded Context (optional, for user messages)
    let toolRoundsData: Data?  // Encoded [ToolExecutionRoundRecord] (optional, for assistant messages)

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        contextData: Data? = nil,
        toolRoundsData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
        self.toolRoundsData = toolRoundsData
    }

    // MARK: - Convenience Initializers

    /// Create from existing ChatMessage (context and tool rounds are embedded in message)
    init(from message: ChatMessage) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = Self.encodeContext(message.context)
        self.toolRoundsData = Self.encodeToolRounds(message.toolRounds)
    }

    /// Convert to ChatMessage (restores embedded context and tool rounds)
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            context: decodeContext(),
            intent: nil,
            toolRounds: decodeToolRounds()
        )
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

    // MARK: - Tool Rounds Helpers

    /// Decode tool execution rounds if present
    func decodeToolRounds() -> [ToolExecutionRoundRecord]? {
        guard let data = toolRoundsData else { return nil }
        return try? JSONDecoder().decode([ToolExecutionRoundRecord].self, from: data)
    }

    /// Encode tool execution rounds to Data
    static func encodeToolRounds(_ toolRounds: [ToolExecutionRoundRecord]?) -> Data? {
        guard let toolRounds = toolRounds, !toolRounds.isEmpty else { return nil }
        return try? JSONEncoder().encode(toolRounds)
    }

    /// Check if message has tool execution history
    var hasToolExecutions: Bool {
        toolRoundsData != nil
    }
}
