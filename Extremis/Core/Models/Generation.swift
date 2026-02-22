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

// MARK: - Model Capabilities

/// Model capabilities - extensible for future features (vision, embeddings, etc.)
struct ModelCapabilities: Codable, Equatable, Hashable {
    /// Whether the model supports tool/function calling
    let supportsTools: Bool

    /// Whether the model supports image/vision input
    let supportsImages: Bool

    init(supportsTools: Bool, supportsImages: Bool = false) {
        self.supportsTools = supportsTools
        self.supportsImages = supportsImages
    }

    // Backward-compatible decoding: default supportsImages to false if key missing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsTools = try container.decode(Bool.self, forKey: .supportsTools)
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case supportsTools
        case supportsImages
    }

    /// Default capabilities (assumes tool support for cloud models)
    static let `default` = ModelCapabilities(supportsTools: true, supportsImages: false)

    /// No capabilities (for models that don't support tools)
    static let none = ModelCapabilities(supportsTools: false, supportsImages: false)
}

// MARK: - LLM Model

/// Represents an LLM model within a provider
struct LLMModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let description: String

    /// Model capabilities (nil = use defaults based on provider)
    let capabilities: ModelCapabilities?

    var displayName: String {
        "\(name)"
    }

    /// Whether this model supports tool/function calling
    /// Defaults to true if capabilities not specified (most cloud models support tools)
    var supportsTools: Bool {
        capabilities?.supportsTools ?? true
    }

    /// Whether this model supports image/vision input
    /// Defaults to false if capabilities not specified
    var supportsImages: Bool {
        capabilities?.supportsImages ?? false
    }

    // MARK: - Initializers

    /// Full initializer with capabilities
    init(id: String, name: String, description: String, capabilities: ModelCapabilities? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.capabilities = capabilities
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, description, capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities)
    }
}


