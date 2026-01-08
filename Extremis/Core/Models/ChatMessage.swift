// MARK: - Chat Message Models
// Models for multi-turn chat sessions

import Foundation

// MARK: - Chat Role

/// Role of a participant in a chat session
enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

// MARK: - Chat Message

/// A single message in a chat session
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    /// Create a user message
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
    
    /// Create an assistant message
    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }
    
    /// Create a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

// MARK: - Chat Session

/// Manages a multi-turn chat session
@MainActor
final class ChatSession: ObservableObject {
    /// All messages in the session
    @Published var messages: [ChatMessage] = []

    /// Original context when session started (for system prompt)
    let originalContext: Context?

    /// Original request that started the session (instruction or "summarize")
    let initialRequest: String?

    /// Maximum messages to keep (for context window management)
    let maxMessages: Int
    
    init(
        originalContext: Context? = nil,
        initialRequest: String? = nil,
        maxMessages: Int = 20
    ) {
        self.originalContext = originalContext
        self.initialRequest = initialRequest
        self.maxMessages = maxMessages
    }
    
    /// Initialize with an existing assistant response
    convenience init(
        initialResponse: String,
        originalContext: Context? = nil,
        initialRequest: String? = nil,
        maxMessages: Int = 20
    ) {
        self.init(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )
        addAssistantMessage(initialResponse)
    }
    
    // MARK: - Message Management

    /// Add a message to the session
    /// Note: Messages are NOT trimmed here - all messages are preserved for persistence.
    /// Use messagesForLLM() when building LLM context to get trimmed messages.
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    /// Add a user message
    func addUserMessage(_ content: String) {
        addMessage(.user(content))
    }
    
    /// Add an assistant message
    func addAssistantMessage(_ content: String) {
        addMessage(.assistant(content))
    }
    
    /// Update the last assistant message (for streaming)
    func updateLastAssistantMessage(_ content: String) {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else {
            // No assistant message yet, add one
            addAssistantMessage(content)
            return
        }
        let existing = messages[lastIndex]
        messages[lastIndex] = ChatMessage(
            id: existing.id,
            role: .assistant,
            content: content,
            timestamp: existing.timestamp
        )
    }
    
    /// Append to the last assistant message (for streaming chunks)
    func appendToLastAssistantMessage(_ chunk: String) {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else {
            addAssistantMessage(chunk)
            return
        }
        let existing = messages[lastIndex]
        messages[lastIndex] = ChatMessage(
            id: existing.id,
            role: .assistant,
            content: existing.content + chunk,
            timestamp: existing.timestamp
        )
    }
    
    /// Remove a message by its ID and all messages that follow it
    /// Returns the user message that preceded the removed assistant message (for retry)
    @discardableResult
    func removeMessageAndFollowing(id: UUID) -> ChatMessage? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        // Find the user message that preceded this assistant message (for retry)
        var precedingUserMessage: ChatMessage?
        if index > 0 {
            // Look backwards for the most recent user message before this assistant message
            for i in stride(from: index - 1, through: 0, by: -1) {
                if messages[i].role == .user {
                    precedingUserMessage = messages[i]
                    break
                }
            }
        }

        // Remove the message and all following messages
        messages.removeSubrange(index...)
        print("[ChatSession] Removed message at index \(index) and following, now have \(messages.count) messages")

        return precedingUserMessage
    }

    // MARK: - Computed Properties

    /// The last assistant message
    var lastAssistantMessage: ChatMessage? {
        messages.last { $0.role == .assistant }
    }

    /// Content of the last assistant message (for Insert/Copy)
    var lastAssistantContent: String {
        lastAssistantMessage?.content ?? ""
    }

    /// Whether the session has any messages
    var isEmpty: Bool {
        messages.isEmpty
    }

    /// Number of messages
    var count: Int {
        messages.count
    }
    
    // MARK: - LLM Context

    /// Get messages for LLM context (trimmed to maxMessages)
    /// This returns a trimmed copy - the original messages array is preserved for persistence.
    func messagesForLLM() -> [ChatMessage] {
        guard messages.count > maxMessages else { return messages }

        // Keep system messages at the start
        let systemMessages = messages.prefix(while: { $0.role == .system })
        let nonSystemMessages = messages.dropFirst(systemMessages.count)

        // Keep only recent non-system messages
        let keepCount = maxMessages - systemMessages.count
        let recentMessages = nonSystemMessages.suffix(keepCount)

        let trimmed = Array(systemMessages) + Array(recentMessages)
        print("[ChatSession] messagesForLLM: returning \(trimmed.count) of \(messages.count) messages")
        return trimmed
    }
}

