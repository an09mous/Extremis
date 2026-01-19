// MARK: - Model Configuration Loader
// Loads LLM model definitions from JSON configuration file

import Foundation

/// Error types for model config loading
enum ModelConfigError: Error, LocalizedError {
    case configNotFound
    case loadingFailed(underlying: Error)
    case decodingFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Model configuration file 'models.json' not found in bundle"
        case .loadingFailed(let error):
            return "Failed to load model config: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode model config: \(error.localizedDescription)"
        }
    }
}

// MARK: - Configuration Models

/// Root configuration structure
struct ModelConfig: Codable {
    let version: Int
    let providers: [String: ProviderModelConfig]
}

/// Provider-specific model configuration
struct ProviderModelConfig: Codable {
    let models: [LLMModel]
    let defaultModelId: String
    
    enum CodingKeys: String, CodingKey {
        case models
        case defaultModelId = "default"
    }
}

// MARK: - Model Config Loader

/// Loads and caches model configuration from JSON
/// Follows the same pattern as PromptTemplateLoader
@MainActor
final class ModelConfigLoader {
    
    // MARK: - Singleton
    
    static let shared = ModelConfigLoader()
    
    // MARK: - Properties
    
    /// Cached configuration
    private var config: ModelConfig?

    /// Bundle to load resources from
    private let bundle: Bundle
    
    // MARK: - Initialization
    
    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }
    
    // MARK: - Public Methods
    
    /// Get models for a provider
    /// Returns empty array for Ollama (uses API discovery) or if loading fails
    /// - Parameter provider: The LLM provider type
    /// - Returns: Array of available models
    func models(for provider: LLMProviderType) -> [LLMModel] {
        // Ollama uses dynamic API discovery - don't use JSON config
        guard provider != .ollama else { return [] }

        do {
            let config = try loadConfig()
            // Case-insensitive lookup: try exact match first, then lowercase
            let providerKey = provider.rawValue
            let providerConfig = config.providers[providerKey]
                ?? config.providers[providerKey.lowercased()]
                ?? config.providers.first { $0.key.lowercased() == providerKey.lowercased() }?.value
            return providerConfig?.models ?? []
        } catch {
            print("⚠️ ModelConfigLoader: Failed to load models for \(provider.rawValue): \(error.localizedDescription)")
            return []
        }
    }

    /// Get the default model for a provider
    /// - Parameter provider: The LLM provider type
    /// - Returns: Default model or nil if not found
    func defaultModel(for provider: LLMProviderType) -> LLMModel? {
        // Ollama uses dynamic API discovery
        guard provider != .ollama else { return nil }

        do {
            let config = try loadConfig()
            // Case-insensitive lookup: try exact match first, then lowercase
            let providerKey = provider.rawValue
            let providerConfig = config.providers[providerKey]
                ?? config.providers[providerKey.lowercased()]
                ?? config.providers.first { $0.key.lowercased() == providerKey.lowercased() }?.value

            guard let config = providerConfig else { return nil }

            // Find the model matching the default ID
            return config.models.first { $0.id == config.defaultModelId }
                ?? config.models.first
        } catch {
            print("⚠️ ModelConfigLoader: Failed to get default model for \(provider.rawValue): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Preload configuration at startup
    func preload() {
        _ = try? loadConfig()
    }
    
    /// Clear the cache (primarily for testing)
    func clearCache() {
        config = nil
    }
    
    // MARK: - Private Methods
    
    private func loadConfig() throws -> ModelConfig {
        // Return cached config if available
        if let cached = config {
            return cached
        }

        // Load from bundle
        let loaded = try loadFromBundle()
        config = loaded
        return loaded
    }
    
    private func loadFromBundle() throws -> ModelConfig {
        // Try without subdirectory first (SPM flattens resources)
        // Then try with subdirectory (traditional .app bundle)
        let url = bundle.url(forResource: "models", withExtension: "json")
            ?? bundle.url(forResource: "models", withExtension: "json", subdirectory: "Resources")
        
        guard let configURL = url else {
            throw ModelConfigError.configNotFound
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            return try decoder.decode(ModelConfig.self, from: data)
        } catch let error as DecodingError {
            throw ModelConfigError.decodingFailed(underlying: error)
        } catch {
            throw ModelConfigError.loadingFailed(underlying: error)
        }
    }
}

