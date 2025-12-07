// MARK: - LLM Provider Registry
// Manages available LLM providers

import Foundation

/// Registry for managing LLM providers
final class LLMProviderRegistry: LLMProviderRegistryProtocol {
    
    // MARK: - Properties
    
    /// All registered providers
    private(set) var providers: [LLMProvider] = []
    
    /// Currently active provider
    private(set) var activeProvider: LLMProvider?
    
    /// Keychain helper for API key storage
    private let keychainHelper: KeychainHelper
    
    /// User defaults for preferences
    private let userDefaults: UserDefaultsHelper
    
    /// Shared instance
    static let shared = LLMProviderRegistry()
    
    // MARK: - Initialization
    
    init(
        keychainHelper: KeychainHelper = .shared,
        userDefaults: UserDefaultsHelper = .shared
    ) {
        self.keychainHelper = keychainHelper
        self.userDefaults = userDefaults
        
        // Register default providers
        registerDefaultProviders()
        
        // Restore active provider from preferences
        restoreActiveProvider()
    }
    
    // MARK: - LLMProviderRegistryProtocol
    
    func setActive(_ providerType: LLMProviderType) throws {
        guard let provider = provider(for: providerType) else {
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        guard provider.isConfigured else {
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        activeProvider = provider

        // Save to preferences
        try userDefaults.setActiveProvider(providerType)
    }
    
    func provider(for type: LLMProviderType) -> LLMProvider? {
        providers.first { $0.providerType == type }
    }
    
    func configure(_ providerType: LLMProviderType, apiKey: String) throws {
        guard let provider = provider(for: providerType) else {
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        // Store API key securely
        try keychainHelper.storeAPIKey(apiKey, for: providerType)

        // Configure the provider
        try provider.configure(apiKey: apiKey)
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultProviders() {
        // Register all supported providers
        providers.append(OpenAIProvider())
        providers.append(AnthropicProvider())
        providers.append(GeminiProvider())
        providers.append(OllamaProvider())
    }
    
    private func restoreActiveProvider() {
        let preferredType = userDefaults.activeProvider

        // Always set the preferred provider (even if not configured yet)
        // This respects user choice and allows Ollama to connect later
        if let provider = provider(for: preferredType) {
            activeProvider = provider
            return
        }

        // Fall back to Ollama (default) or first available provider
        activeProvider = provider(for: .ollama) ?? providers.first
    }
    
    // MARK: - Model Selection

    /// Set the model for a provider
    func setModel(_ model: LLMModel, for providerType: LLMProviderType) {
        guard let provider = provider(for: providerType) else { return }
        provider.setModel(model)
    }

    /// Get available models for a provider
    func availableModels(for providerType: LLMProviderType) -> [LLMModel] {
        // For Ollama, return dynamically fetched models if available
        if providerType == .ollama,
           let ollamaProvider = provider(for: .ollama) as? OllamaProvider,
           !ollamaProvider.availableModelsFromServer.isEmpty {
            return ollamaProvider.availableModelsFromServer
        }
        return providerType.availableModels
    }

    /// Get current model for a provider
    func currentModel(for providerType: LLMProviderType) -> LLMModel? {
        provider(for: providerType)?.currentModel
    }

    // MARK: - Convenience Methods

    /// Get all configured providers
    var configuredProviders: [LLMProvider] {
        providers.filter { $0.isConfigured }
    }

    /// Check if any provider is configured
    var hasConfiguredProvider: Bool {
        !configuredProviders.isEmpty
    }

    /// Get the active provider type
    var activeProviderType: LLMProviderType? {
        activeProvider?.providerType
    }

    /// Get active provider's current model
    var activeModel: LLMModel? {
        activeProvider?.currentModel
    }
}

