// MARK: - Generation Model
// Represents the AI-produced response

import Foundation

/// The AI-generated text response
struct Generation: Codable, Equatable, Identifiable {
    let id: UUID
    let instructionId: UUID
    let provider: LLMProviderType
    let content: String
    let createdAt: Date
    let tokenUsage: TokenUsage?
    let latencyMs: Int?
    
    init(
        id: UUID = UUID(),
        instructionId: UUID,
        provider: LLMProviderType,
        content: String,
        createdAt: Date = Date(),
        tokenUsage: TokenUsage? = nil,
        latencyMs: Int? = nil
    ) {
        self.id = id
        self.instructionId = instructionId
        self.provider = provider
        self.content = content
        self.createdAt = createdAt
        self.tokenUsage = tokenUsage
        self.latencyMs = latencyMs
    }
}

// MARK: - Token Usage

/// Token usage information from the LLM provider
struct TokenUsage: Codable, Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
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
    var defaultModel: LLMModel {
        availableModels.first!
    }

    /// Model name used for API calls (default)
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

// MARK: - Generation Status

/// Status of a generation request
enum GenerationStatus: String, Codable, Equatable {
    case pending
    case generating
    case completed
    case failed
    case cancelled
}

