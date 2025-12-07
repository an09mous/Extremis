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
    var availableModels: [LLMModel] {
        switch self {
        case .openai:
            return [
                LLMModel(id: "gpt-4o", name: "GPT-4o", description: "Most capable, multimodal"),
                LLMModel(id: "gpt-4o-mini", name: "GPT-4o Mini", description: "Fast and affordable"),
                LLMModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", description: "Powerful with vision"),
                LLMModel(id: "gpt-4", name: "GPT-4", description: "Original GPT-4"),
                LLMModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", description: "Fast and cheap"),
            ]
        case .anthropic:
            return [
                LLMModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", description: "Best balance of speed and intelligence"),
                LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", description: "Fast and intelligent"),
                LLMModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", description: "Fastest, most affordable"),
                LLMModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", description: "Most capable"),
                LLMModel(id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", description: "Balanced"),
                LLMModel(id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", description: "Fast and compact"),
            ]
        case .gemini:
            return [
                LLMModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", description: "Latest, fastest"),
                LLMModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", description: "Best for complex tasks"),
                LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", description: "Fast and versatile"),
                LLMModel(id: "gemini-1.0-pro", name: "Gemini 1.0 Pro", description: "Stable, reliable"),
            ]
        case .ollama:
            // Default models - actual list is fetched dynamically from Ollama server
            return [
                LLMModel(id: "llama3.2", name: "Llama 3.2", description: "Meta's latest model"),
                LLMModel(id: "mistral", name: "Mistral", description: "Fast and capable"),
                LLMModel(id: "codellama", name: "Code Llama", description: "Optimized for code"),
                LLMModel(id: "gemma2", name: "Gemma 2", description: "Google's open model"),
            ]
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

