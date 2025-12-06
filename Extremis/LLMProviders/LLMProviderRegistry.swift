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
        print("🔧 setActive called for: \(providerType.displayName)")

        guard let provider = provider(for: providerType) else {
            print("❌ Provider not found for: \(providerType)")
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        print("🔧 Provider found: \(provider.displayName), isConfigured: \(provider.isConfigured)")

        guard provider.isConfigured else {
            print("❌ Provider not configured: \(providerType)")
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        activeProvider = provider
        print("🔧 activeProvider set to: \(activeProvider?.displayName ?? "nil")")

        // Save to preferences
        do {
            try userDefaults.setActiveProvider(providerType)
            print("🔧 Saved to preferences: \(providerType)")
        } catch {
            print("❌ Failed to save preference: \(error)")
        }

        print("✅ Active LLM provider set to: \(providerType.displayName)")
    }
    
    func provider(for type: LLMProviderType) -> LLMProvider? {
        providers.first { $0.providerType == type }
    }
    
    func configure(_ providerType: LLMProviderType, apiKey: String) throws {
        print("🔧 configure called for: \(providerType.displayName)")

        guard let provider = provider(for: providerType) else {
            print("❌ Provider not found: \(providerType)")
            throw LLMProviderError.notConfigured(provider: providerType)
        }

        // Store API key securely
        print("🔧 Storing API key in keychain...")
        try keychainHelper.storeAPIKey(apiKey, for: providerType)

        // Configure the provider
        print("🔧 Configuring provider with API key...")
        try provider.configure(apiKey: apiKey)

        print("🔧 Provider isConfigured after configure: \(provider.isConfigured)")
        print("✅ Configured \(providerType.displayName) with API key")
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultProviders() {
        // Register all supported providers
        providers.append(OpenAIProvider())
        providers.append(AnthropicProvider())
        providers.append(GeminiProvider())
    }
    
    private func restoreActiveProvider() {
        let preferredType = userDefaults.activeProvider
        
        // Try to set the preferred provider if configured
        if let provider = provider(for: preferredType), provider.isConfigured {
            activeProvider = provider
            return
        }
        
        // Fall back to first configured provider
        activeProvider = providers.first { $0.isConfigured }
    }
    
    // MARK: - Model Selection

    /// Set the model for a provider
    func setModel(_ model: LLMModel, for providerType: LLMProviderType) {
        guard let provider = provider(for: providerType) else { return }
        provider.setModel(model)
    }

    /// Get available models for a provider
    func availableModels(for providerType: LLMProviderType) -> [LLMModel] {
        providerType.availableModels
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

