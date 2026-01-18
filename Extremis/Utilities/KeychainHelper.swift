// MARK: - Keychain Helper
// Secure storage for API keys using macOS Keychain
// Uses a SINGLE keychain entry to store all API keys as JSON to minimize keychain prompts

import Foundation
import Security

/// Secure storage implementation using macOS Keychain
/// Stores all API keys in a single keychain entry as JSON to require only ONE keychain access prompt
@MainActor
final class KeychainHelper: @preconcurrency SecureStorage {

    // MARK: - Properties

    /// Service name for keychain items
    private let service: String

    /// Account name for the single keychain entry that stores all API keys
    private let keychainAccount = "api_keys"

    /// In-memory cache for API keys (loaded from single keychain entry)
    private var apiKeys: [String: String] = [:]

    /// Flag to track if keys have been loaded from keychain
    private var isLoaded: Bool = false

    /// Shared instance
    static let shared = KeychainHelper()

    // MARK: - Initialization

    init(service: String = "com.extremis.app") {
        self.service = service
        loadFromKeychain()
    }

    // MARK: - Keychain Storage (Single Entry)

    /// Load all API keys from the single keychain entry
    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        isLoaded = true

        switch status {
        case errSecSuccess:
            if let data = result as? Data,
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                apiKeys = dict
            } else {
                print("[KeychainHelper] Failed to decode keychain data")
            }

        case errSecItemNotFound:
            apiKeys = [:]

        default:
            print("[KeychainHelper] Load failed with status: \(status)")
            apiKeys = [:]
        }
    }

    /// Save all API keys to the single keychain entry
    private func saveToKeychain() throws {
        guard let data = try? JSONEncoder().encode(apiKeys) else {
            print("[KeychainHelper] Failed to encode API keys")
            throw PreferencesError.keychainWriteFailed
        }

        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry (only if we have keys to store)
        if !apiKeys.isEmpty {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]

            let status = SecItemAdd(addQuery as CFDictionary, nil)

            guard status == errSecSuccess else {
                print("[KeychainHelper] Save failed with status: \(status)")
                throw PreferencesError.keychainWriteFailed
            }
        }
    }

    // MARK: - SecureStorage Protocol

    func store(key: String, value: String) throws {
        apiKeys[key] = value
        try saveToKeychain()
    }

    func retrieve(key: String) throws -> String? {
        return apiKeys[key]
    }

    func delete(key: String) throws {
        apiKeys.removeValue(forKey: key)
        try saveToKeychain()
    }

    func exists(key: String) -> Bool {
        return apiKeys[key] != nil && !apiKeys[key]!.isEmpty
    }

    // MARK: - Convenience Methods

    /// Store an API key for a provider
    func storeAPIKey(_ apiKey: String, for provider: LLMProviderType) throws {
        try store(key: "api_key_\(provider.rawValue)", value: apiKey)
    }

    /// Retrieve an API key for a provider
    func retrieveAPIKey(for provider: LLMProviderType) throws -> String? {
        try retrieve(key: "api_key_\(provider.rawValue)")
    }

    /// Delete an API key for a provider
    func deleteAPIKey(for provider: LLMProviderType) throws {
        try delete(key: "api_key_\(provider.rawValue)")
    }

    /// Check if an API key exists for a provider
    func hasAPIKey(for provider: LLMProviderType) -> Bool {
        exists(key: "api_key_\(provider.rawValue)")
    }
}

