// MARK: - Keychain Helper
// Secure storage for API keys using macOS Keychain

import Foundation
import Security

/// Secure storage implementation using macOS Keychain
final class KeychainHelper: SecureStorage {
    
    // MARK: - Properties
    
    /// Service name for keychain items
    private let service: String
    
    /// Shared instance
    static let shared = KeychainHelper()
    
    // MARK: - Initialization
    
    init(service: String = "com.extremis.app") {
        self.service = service
    }
    
    // MARK: - SecureStorage Protocol
    
    func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw PreferencesError.keychainWriteFailed
        }
        
        // Delete existing item first
        try? delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw PreferencesError.keychainWriteFailed
        }
    }
    
    func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw PreferencesError.keychainAccessDenied
        }
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PreferencesError.keychainAccessDenied
        }
    }
    
    func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
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

