// MARK: - Connector Config Storage
// Persistence for connector configurations

import Foundation

/// Service for reading and writing connector configuration file
@MainActor
final class ConnectorConfigStorage {

    // MARK: - Properties

    /// File manager
    private let fileManager: FileManager

    /// JSON encoder with pretty printing
    private let encoder: JSONEncoder

    /// JSON decoder
    private let decoder: JSONDecoder

    /// Shared instance
    static let shared = ConnectorConfigStorage()

    /// Config file URL
    var configFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let extremisDir = appSupport.appendingPathComponent("Extremis", isDirectory: true)
        return extremisDir.appendingPathComponent("connectors.json")
    }

    // MARK: - Initialization

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Load configuration from disk
    /// Returns empty config if file doesn't exist
    func load() throws -> ConnectorConfigFile {
        let url = configFileURL

        // If file doesn't exist, return empty config
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }

        // Read and decode
        let data = try Data(contentsOf: url)

        // Use migration-aware loading
        return try ConnectorConfigFile.migrate(from: data)
    }

    /// Save configuration to disk
    func save(_ config: ConnectorConfigFile) throws {
        let url = configFileURL

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Encode and write
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Custom Server Operations

    /// Add a new custom MCP server
    func addCustomServer(_ config: CustomMCPServerConfig) throws {
        var connectorConfig = try load()
        connectorConfig.addCustomServer(config)
        try save(connectorConfig)
    }

    /// Update an existing custom MCP server
    func updateCustomServer(_ config: CustomMCPServerConfig) throws {
        var connectorConfig = try load()
        connectorConfig.updateCustomServer(config)
        try save(connectorConfig)
    }

    /// Remove a custom MCP server
    func removeCustomServer(id: UUID) throws {
        var connectorConfig = try load()
        connectorConfig.removeCustomServer(id: id)
        try save(connectorConfig)
    }

    /// Get a specific custom server
    func customServer(id: UUID) throws -> CustomMCPServerConfig? {
        let config = try load()
        return config.customServer(id: id)
    }

    /// Get all custom servers
    func allCustomServers() throws -> [CustomMCPServerConfig] {
        let config = try load()
        return config.custom
    }

    /// Get all enabled custom servers
    func enabledCustomServers() throws -> [CustomMCPServerConfig] {
        let config = try load()
        return config.enabledCustomServers
    }

    /// Set enabled state for a custom server
    func setEnabled(_ enabled: Bool, forCustomServer id: UUID) throws {
        var config = try load()
        if var serverConfig = config.customServer(id: id) {
            serverConfig.enabled = enabled
            config.updateCustomServer(serverConfig)
            try save(config)
        }
    }

    // MARK: - Built-in Connector Operations (Phase 2 placeholder)

    /// Set built-in connector config
    func setBuiltInConfig(_ builtInConfig: BuiltInConnectorConfig, for type: BuiltInConnectorType) throws {
        var config = try load()
        config.setBuiltIn(type.rawValue, config: builtInConfig)
        try save(config)
    }

    /// Get built-in connector config
    func builtInConfig(for type: BuiltInConnectorType) throws -> BuiltInConnectorConfig? {
        let config = try load()
        return config.builtInConfig(for: type.rawValue)
    }

    /// Check if built-in connector is enabled
    func isBuiltInEnabled(_ type: BuiltInConnectorType) throws -> Bool {
        let config = try load()
        return config.isBuiltInEnabled(type.rawValue)
    }

    /// Set enabled state for built-in connector
    func setBuiltInEnabled(_ enabled: Bool, for type: BuiltInConnectorType) throws {
        var config = try load()
        var builtInConfig = config.builtInConfig(for: type.rawValue) ?? .disabled
        builtInConfig.enabled = enabled
        config.setBuiltIn(type.rawValue, config: builtInConfig)
        try save(config)
    }

    // MARK: - Utility

    /// Check if config file exists
    var configFileExists: Bool {
        fileManager.fileExists(atPath: configFileURL.path)
    }

    /// Delete the config file (for testing/reset)
    func deleteConfigFile() throws {
        if configFileExists {
            try fileManager.removeItem(at: configFileURL)
        }
    }

    /// Create a backup of the config file
    func backupConfigFile() throws -> URL? {
        guard configFileExists else { return nil }

        let backupURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("connectors.backup.json")

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        try fileManager.copyItem(at: configFileURL, to: backupURL)
        return backupURL
    }

    /// Restore from a backup
    func restoreFromBackup() throws {
        let backupURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("connectors.backup.json")

        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ConnectorConfigError.backupNotFound
        }

        if fileManager.fileExists(atPath: configFileURL.path) {
            try fileManager.removeItem(at: configFileURL)
        }

        try fileManager.copyItem(at: backupURL, to: configFileURL)
    }
}

// MARK: - Errors

/// Errors specific to connector config storage
enum ConnectorConfigError: LocalizedError {
    case backupNotFound
    case invalidConfig(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupNotFound:
            return "No backup file found"
        case .invalidConfig(let reason):
            return "Invalid configuration: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write configuration: \(reason)"
        }
    }
}
