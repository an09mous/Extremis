// MARK: - LLM Provider Protocol
// Defines the contract for LLM service providers

import Foundation

/// Protocol for LLM service providers (OpenAI, Anthropic, Gemini)
@MainActor
protocol LLMProvider: AnyObject {
    /// Provider type identifier
    var providerType: LLMProviderType { get }

    /// Human-readable name
    var displayName: String { get }

    /// Whether API key is configured
    var isConfigured: Bool { get }

    /// Currently selected model
    var currentModel: LLMModel { get }

    /// Configure the provider with an API key
    /// - Parameter apiKey: The API key to use
    /// - Throws: LLMProviderError.invalidAPIKey if key is invalid
    func configure(apiKey: String) throws

    /// Set the model to use
    /// - Parameter model: The model to use for generation
    func setModel(_ model: LLMModel)

    /// Generate a response from a raw prompt (non-streaming)
    /// Use this when the prompt is already fully built (e.g., summarization)
    /// - Parameter prompt: The complete prompt to send to the LLM
    /// - Returns: Generated response
    /// - Throws: LLMProviderError on failure
    func generateRaw(prompt: String) async throws -> Generation

    /// Generate a response from a raw prompt with streaming
    /// Use this when the prompt is already fully built (e.g., summarization)
    /// - Parameter prompt: The complete prompt to send to the LLM
    /// - Returns: Async stream of text chunks
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error>

    /// Generate a chat response from a conversation (non-streaming)
    /// - Parameters:
    ///   - messages: Array of chat messages in the conversation (each message may have embedded context)
    /// - Returns: Generated response
    /// - Throws: LLMProviderError on failure
    func generateChat(messages: [ChatMessage]) async throws -> Generation

    /// Generate a chat response with streaming
    /// - Parameters:
    ///   - messages: Array of chat messages in the conversation (each message may have embedded context)
    /// - Returns: Async stream of text chunks
    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>

    /// Generate a chat response with tool support (non-streaming)
    /// - Parameters:
    ///   - messages: Array of chat messages in the conversation
    ///   - tools: Available tools for the LLM to use
    ///   - toolRounds: History of tool execution rounds (each round pairs tool calls with their results)
    /// - Returns: Response that may contain text and/or tool calls
    /// - Throws: LLMProviderError on failure
    func generateChatWithTools(
        messages: [ChatMessage],
        tools: [ConnectorTool],
        toolRounds: [ToolExecutionRound]
    ) async throws -> ToolEnabledGeneration

    /// Generate a chat response with tool support (streaming)
    /// Streams text content while also returning tool calls at the end
    /// - Parameters:
    ///   - messages: Array of chat messages in the conversation
    ///   - tools: Available tools for the LLM to use
    ///   - toolRounds: History of tool execution rounds (each round pairs tool calls with their results)
    /// - Returns: Stream of events (text chunks and/or tool calls)
    func generateChatWithToolsStream(
        messages: [ChatMessage],
        tools: [ConnectorTool],
        toolRounds: [ToolExecutionRound]
    ) -> AsyncThrowingStream<ToolStreamEvent, Error>
}

// MARK: - Tool Stream Event

/// Events emitted during tool-enabled streaming generation
/// Note: @unchecked Sendable because LLMToolCall contains [String: Any]
/// which isn't Sendable, but we ensure safe usage in practice
enum ToolStreamEvent: @unchecked Sendable {
    /// Text content chunk from LLM
    case textChunk(String)

    /// LLM is done streaming, provides final tool calls (may be empty)
    case complete(toolCalls: [LLMToolCall])
}

// MARK: - Tool Execution Round

/// Represents a single round of tool execution (tool calls + their results)
/// Used to build proper conversation history for multi-turn tool interactions
struct ToolExecutionRound {
    /// Tool calls made by the LLM in this round
    let toolCalls: [LLMToolCall]

    /// Results from executing those tool calls
    let results: [ToolResult]

    init(toolCalls: [LLMToolCall], results: [ToolResult]) {
        self.toolCalls = toolCalls
        self.results = results
    }
}

// MARK: - LLM Provider Registry Protocol

/// Registry for managing LLM providers
@MainActor
protocol LLMProviderRegistryProtocol {
    /// All available providers
    var providers: [LLMProvider] { get }
    
    /// Currently active provider
    var activeProvider: LLMProvider? { get }
    
    /// Set the active provider
    /// - Parameter providerType: The provider type to activate
    /// - Throws: LLMProviderError.notConfigured if provider has no API key
    func setActive(_ providerType: LLMProviderType) throws
    
    /// Get provider by type
    func provider(for type: LLMProviderType) -> LLMProvider?
    
    /// Configure a provider with an API key
    func configure(_ providerType: LLMProviderType, apiKey: String) throws
}

// MARK: - LLM Provider Error

/// Errors that can occur with LLM providers
enum LLMProviderError: LocalizedError, Equatable {
    case notConfigured(provider: LLMProviderType)
    case invalidAPIKey
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            if provider == .ollama {
                return "Ollama server is not running. Please start Ollama and try again."
            }
            return "\(provider.rawValue) is not configured. Please add your API key in Preferences."
        case .invalidAPIKey:
            return "Invalid API key. Please check your API key in Preferences."
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded. Please try again in \(Int(seconds)) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .invalidResponse:
            return "Received invalid response from AI provider."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .unknown(let message):
            return "AI generation failed: \(message)"
        }
    }

    // Custom Equatable
    static func == (lhs: LLMProviderError, rhs: LLMProviderError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured(let a), .notConfigured(let b)): return a == b
        case (.invalidAPIKey, .invalidAPIKey): return true
        case (.rateLimitExceeded(let a), .rateLimitExceeded(let b)): return a == b
        case (.invalidResponse, .invalidResponse): return true
        case (.serverError(let c1, let m1), .serverError(let c2, let m2)): return c1 == c2 && m1 == m2
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

