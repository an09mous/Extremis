// MARK: - Connector Secrets Storage
// Secure storage for connector secrets using Keychain

import Foundation

/// Service for storing and retrieving connector secrets from Keychain
@MainActor
final class ConnectorSecretsStorage {

    // MARK: - Properties

    /// Reference to the shared keychain helper
    private let keychain: KeychainHelper

    /// Encoder for serializing secrets
    private let encoder: JSONEncoder

    /// Decoder for deserializing secrets
    private let decoder: JSONDecoder

    /// Shared instance
    static let shared = ConnectorSecretsStorage()

    // MARK: - Initialization

    init(keychain: KeychainHelper = .shared) {
        self.keychain = keychain
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Public Methods

    /// Save secrets for a connector
    /// - Parameters:
    ///   - secrets: The secrets to store
    ///   - key: The keychain key for this connector
    /// - Throws: Error if storage fails
    func saveSecrets(_ secrets: ConnectorSecrets, for key: ConnectorKeychainKey) throws {
        // Don't store empty secrets
        if secrets.isEmpty {
            try deleteSecrets(for: key)
            return
        }

        let data = try encoder.encode(secrets)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ConnectorSecretsError.encodingFailed
        }

        try keychain.store(key: key.key, value: jsonString)
    }

    /// Load secrets for a connector
    /// - Parameter key: The keychain key for this connector
    /// - Returns: The stored secrets, or nil if none exist
    /// - Throws: Error if retrieval fails
    func loadSecrets(for key: ConnectorKeychainKey) throws -> ConnectorSecrets? {
        guard let jsonString = try keychain.retrieve(key: key.key) else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ConnectorSecretsError.decodingFailed
        }

        return try decoder.decode(ConnectorSecrets.self, from: data)
    }

    /// Delete secrets for a connector
    /// - Parameter key: The keychain key for this connector
    /// - Throws: Error if deletion fails
    func deleteSecrets(for key: ConnectorKeychainKey) throws {
        try keychain.delete(key: key.key)
    }

    /// Check if secrets exist for a connector
    /// - Parameter key: The keychain key for this connector
    /// - Returns: True if secrets exist
    func hasSecrets(for key: ConnectorKeychainKey) -> Bool {
        keychain.exists(key: key.key)
    }

    // MARK: - Convenience Methods for Custom Servers

    /// Save secrets for a custom MCP server
    func saveSecrets(_ secrets: ConnectorSecrets, forCustomServer id: UUID) throws {
        try saveSecrets(secrets, for: .custom(id))
    }

    /// Load secrets for a custom MCP server
    func loadSecrets(forCustomServer id: UUID) throws -> ConnectorSecrets? {
        try loadSecrets(for: .custom(id))
    }

    /// Delete secrets for a custom MCP server
    func deleteSecrets(forCustomServer id: UUID) throws {
        try deleteSecrets(for: .custom(id))
    }

    /// Check if secrets exist for a custom MCP server
    func hasSecrets(forCustomServer id: UUID) -> Bool {
        hasSecrets(for: .custom(id))
    }

    // MARK: - Convenience Methods for Built-in Connectors

    /// Save secrets for a built-in connector
    func saveSecrets(_ secrets: ConnectorSecrets, forBuiltIn type: BuiltInConnectorType) throws {
        try saveSecrets(secrets, for: .builtIn(type.rawValue))
    }

    /// Load secrets for a built-in connector
    func loadSecrets(forBuiltIn type: BuiltInConnectorType) throws -> ConnectorSecrets? {
        try loadSecrets(for: .builtIn(type.rawValue))
    }

    /// Delete secrets for a built-in connector
    func deleteSecrets(forBuiltIn type: BuiltInConnectorType) throws {
        try deleteSecrets(for: .builtIn(type.rawValue))
    }

    /// Check if secrets exist for a built-in connector
    func hasSecrets(forBuiltIn type: BuiltInConnectorType) -> Bool {
        hasSecrets(for: .builtIn(type.rawValue))
    }

    // MARK: - Environment Building

    /// Build environment variables for a custom MCP server, merging config env with secrets
    /// - Parameters:
    ///   - config: The server configuration
    /// - Returns: Merged environment variables
    func buildEnvironment(for config: CustomMCPServerConfig) throws -> [String: String] {
        // Start with config env vars
        var env: [String: String]

        switch config.transport {
        case .stdio(let stdioConfig):
            env = stdioConfig.env
        case .http:
            env = [:]  // HTTP transport doesn't use env vars
        }

        // Load and merge secrets
        if let secrets = try loadSecrets(forCustomServer: config.id) {
            env = secrets.mergeWithEnv(env)
        }

        return env
    }

    /// Build headers for an HTTP transport, merging config headers with secrets
    /// - Parameters:
    ///   - config: The HTTP configuration
    ///   - serverID: The server ID for loading secrets
    /// - Returns: Merged headers
    func buildHeaders(for config: HTTPConfig, serverID: UUID) throws -> [String: String] {
        var headers = config.headers

        if let secrets = try loadSecrets(forCustomServer: serverID) {
            headers = secrets.mergeWithHeaders(headers)
        }

        return headers
    }
}

// MARK: - Errors

/// Errors specific to connector secrets storage
enum ConnectorSecretsError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode connector secrets"
        case .decodingFailed:
            return "Failed to decode connector secrets"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        }
    }
}
