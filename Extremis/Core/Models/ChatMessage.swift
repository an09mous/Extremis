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

// MARK: - Message Intent

/// Describes the user's intent for a message, used to inject appropriate prompt templates
/// This enables extensible prompt injection based on how the user triggered Extremis
enum MessageIntent: String, Codable, Equatable {
    /// Standard chat message - no special prompt injection
    case chat

    /// User selected text and provided an instruction (transform, question, etc.)
    /// Injects rules for focused responses on selected text
    case selectionTransform

    /// User selected text but provided no instruction - default to summarization
    /// Injects summarization rules (concise summary, key points, etc.)
    case summarize

    /// Follow-up message in an existing conversation - no injection needed
    case followUp
}

// MARK: - Chat Message

/// A single message in a chat session
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    /// Context captured when this message was created (only relevant for user messages)
    let context: Context?
    /// Intent of the message - determines which prompt rules to inject (only relevant for user messages)
    let intent: MessageIntent?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        context: Context? = nil,
        intent: MessageIntent? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.context = context
        self.intent = intent
    }

    /// Create a user message (for follow-up chat messages)
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content, intent: .followUp)
    }

    /// Create a user message with context and intent
    static func user(_ content: String, context: Context?, intent: MessageIntent = .chat) -> ChatMessage {
        ChatMessage(role: .user, content: content, context: context, intent: intent)
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

    /// Summary of earlier messages (for context efficiency)
    /// When present, messagesForLLM() returns summary + recent messages instead of truncating
    var summary: SessionSummary?

    /// Number of messages covered by the summary
    /// Used to calculate which messages are "recent" (not covered by summary)
    var summaryCoversCount: Int = 0

    init(
        originalContext: Context? = nil,
        initialRequest: String? = nil,
        maxMessages: Int = 20,
        summary: SessionSummary? = nil,
        summaryCoversCount: Int = 0
    ) {
        self.originalContext = originalContext
        self.initialRequest = initialRequest
        self.maxMessages = maxMessages
        self.summary = summary
        self.summaryCoversCount = summaryCoversCount
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
            timestamp: existing.timestamp,
            context: existing.context
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
            timestamp: existing.timestamp,
            context: existing.context
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

    /// Get messages for LLM context
    /// Uses summary + recent messages if summary is available, otherwise truncates to maxMessages.
    /// This returns a trimmed copy - the original messages array is preserved for persistence.
    func messagesForLLM() -> [ChatMessage] {
        // If we have a valid summary, use summary + recent messages
        if let summary = summary, summary.isValid, summaryCoversCount > 0 {
            // Create a system message with the summary
            let summaryMessage = ChatMessage.system("Previous session context: \(summary.content)")

            // Get messages after the summarized portion
            let recentStartIndex = min(summaryCoversCount, messages.count)
            let recentMessages = Array(messages.suffix(from: recentStartIndex))

            let result = [summaryMessage] + recentMessages
            print("[ChatSession] messagesForLLM: using summary + \(recentMessages.count) recent messages (summary covers \(summaryCoversCount))")
            return result
        }

        // No summary - fall back to simple truncation
        guard messages.count > maxMessages else { return messages }

        // Keep system messages at the start
        let systemMessages = messages.prefix(while: { $0.role == .system })
        let nonSystemMessages = messages.dropFirst(systemMessages.count)

        // Keep only recent non-system messages
        let keepCount = maxMessages - systemMessages.count
        let recentMessages = nonSystemMessages.suffix(keepCount)

        let trimmed = Array(systemMessages) + Array(recentMessages)
        print("[ChatSession] messagesForLLM: returning \(trimmed.count) of \(messages.count) messages (no summary)")
        return trimmed
    }

    /// Update the summary (called after summarization completes)
    func updateSummary(_ newSummary: SessionSummary, coversCount: Int) {
        self.summary = newSummary
        self.summaryCoversCount = coversCount
        print("[ChatSession] Updated summary covering \(coversCount) messages")
    }
}

