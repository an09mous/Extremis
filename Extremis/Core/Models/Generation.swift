// MARK: - Generation Model
// Represents the AI-produced response

import Foundation

/// The AI-generated text response
struct Generation: Codable, Equatable {
    let content: String

    init(content: String) {
        self.content = content
    }
}

// MARK: - Tool-Enabled Generation

/// Response from LLM that may include tool calls
struct ToolEnabledGeneration {
    /// Text content from the response (may be empty if only tool calls)
    let content: String?

    /// Tool calls requested by the LLM
    let toolCalls: [LLMToolCall]

    /// Whether this response is complete (no more tool calls needed)
    var isComplete: Bool {
        toolCalls.isEmpty
    }

    /// Create a text-only response
    static func text(_ content: String) -> ToolEnabledGeneration {
        ToolEnabledGeneration(content: content, toolCalls: [])
    }

    /// Create a response with tool calls
    static func withTools(content: String?, toolCalls: [LLMToolCall]) -> ToolEnabledGeneration {
        ToolEnabledGeneration(content: content, toolCalls: toolCalls)
    }
}

/// Raw tool call from LLM response (before resolution to ConnectorTool)
/// Note: @unchecked Sendable because arguments is [String: Any] which isn't Sendable,
/// but in practice we only pass JSON-serializable types which are safe
struct LLMToolCall: Identifiable, Equatable, @unchecked Sendable {
    /// Call ID from the LLM (used for matching results)
    let id: String

    /// Tool name (disambiguated name from our schema)
    let name: String

    /// Arguments as JSON-compatible dictionary
    let arguments: [String: Any]

    static func == (lhs: LLMToolCall, rhs: LLMToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

// MARK: - LLM Provider Type

/// Supported LLM providers
enum LLMProviderType: String, Codable, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"
    case ollama = "Ollama"

    var id: String { rawValue }

    /// Display name for the provider
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .ollama: return "Ollama (Local)"
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default: return true
        }
    }

    /// Available models for this provider
    /// Cloud providers load from models.json, Ollama uses dynamic API discovery
    @MainActor
    var availableModels: [LLMModel] {
        switch self {
        case .ollama:
            // Models are fetched dynamically from Ollama server
            return []
        default:
            // Cloud providers: load from JSON configuration
            return ModelConfigLoader.shared.models(for: self)
        }
    }

    /// Default model for this provider
    @MainActor
    var defaultModel: LLMModel {
        availableModels.first!
    }

    /// Model name used for API calls (default)
    @MainActor
    var defaultModelId: String {
        defaultModel.id
    }

    /// Base URL for API calls
    var baseURL: URL {
        switch self {
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .ollama: return URL(string: "http://127.0.0.1:11434")!
        }
    }
}

// MARK: - LLM Model

/// Represents an LLM model within a provider
struct LLMModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String

    var displayName: String {
        "\(name)"
    }
}


