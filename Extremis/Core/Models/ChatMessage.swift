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

    /// User executed a predefined command with a prompt template
    /// Injects the command's prompt template with context
    case command
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

    /// Tool execution rounds associated with this assistant message
    /// Contains the history of tool calls and their results that produced this response
    /// Only populated for assistant messages that involved tool use
    let toolRounds: [ToolExecutionRoundRecord]?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        context: Context? = nil,
        intent: MessageIntent? = nil,
        toolRounds: [ToolExecutionRoundRecord]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.context = context
        self.intent = intent
        self.toolRounds = toolRounds
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

    /// Create an assistant message with tool execution history
    static func assistant(_ content: String, toolRounds: [ToolExecutionRoundRecord]?) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, toolRounds: toolRounds)
    }

    /// Create a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    // MARK: - Tool Execution Helpers

    /// Whether this message involved tool execution
    var hasToolExecutions: Bool {
        guard let rounds = toolRounds else { return false }
        return !rounds.isEmpty
    }

    /// Total number of tool calls in this message
    var toolCallCount: Int {
        toolRounds?.totalToolCalls ?? 0
    }

    /// All tool call records flattened
    var allToolCalls: [ToolCallRecord] {
        toolRounds?.flatMap { $0.toolCalls } ?? []
    }

    /// All tool result records flattened
    var allToolResults: [ToolResultRecord] {
        toolRounds?.flatMap { $0.results } ?? []
    }
}
