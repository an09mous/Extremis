// MARK: - Connector Configuration File
// Root structure for connectors.json persistence

import Foundation

/// Root structure for connectors.json
struct ConnectorConfigFile: Codable, Equatable {
    /// Schema version for migrations
    var version: Int

    /// Built-in connector configurations (placeholder for Phase 2)
    var builtIn: [String: BuiltInConnectorConfig]

    /// Custom MCP server configurations
    var custom: [CustomMCPServerConfig]

    // MARK: - Constants

    static let currentVersion = 1

    // MARK: - Factory

    /// Empty configuration file
    static let empty = ConnectorConfigFile(
        version: currentVersion,
        builtIn: [:],
        custom: []
    )

    // MARK: - Initialization

    init(version: Int = currentVersion, builtIn: [String: BuiltInConnectorConfig] = [:], custom: [CustomMCPServerConfig] = []) {
        self.version = version
        self.builtIn = builtIn
        self.custom = custom
    }

    // MARK: - Custom Server Management

    /// Add a custom MCP server
    mutating func addCustomServer(_ config: CustomMCPServerConfig) {
        // Remove any existing config with same ID
        custom.removeAll { $0.id == config.id }
        custom.append(config)
    }

    /// Update a custom MCP server
    mutating func updateCustomServer(_ config: CustomMCPServerConfig) {
        if let index = custom.firstIndex(where: { $0.id == config.id }) {
            custom[index] = config.withUpdatedTimestamp()
        }
    }

    /// Remove a custom MCP server by ID
    mutating func removeCustomServer(id: UUID) {
        custom.removeAll { $0.id == id }
    }

    /// Get a custom server by ID
    func customServer(id: UUID) -> CustomMCPServerConfig? {
        custom.first { $0.id == id }
    }

    /// All enabled custom servers
    var enabledCustomServers: [CustomMCPServerConfig] {
        custom.filter { $0.enabled }
    }

    // MARK: - Built-in Connector Management (Phase 2 placeholder)

    /// Set built-in connector config
    mutating func setBuiltIn(_ type: String, config: BuiltInConnectorConfig) {
        builtIn[type] = config
    }

    /// Get built-in connector config
    func builtInConfig(for type: String) -> BuiltInConnectorConfig? {
        builtIn[type]
    }

    /// Check if built-in connector is enabled
    func isBuiltInEnabled(_ type: String) -> Bool {
        builtIn[type]?.enabled ?? false
    }
}

// MARK: - Built-in Connector Config (Phase 2 placeholder)

/// Configuration for a built-in connector
struct BuiltInConnectorConfig: Codable, Equatable {
    /// Whether this connector is enabled
    var enabled: Bool

    /// Optional connector-specific settings
    var settings: [String: String]?

    static let disabled = BuiltInConnectorConfig(enabled: false, settings: nil)

    init(enabled: Bool, settings: [String: String]? = nil) {
        self.enabled = enabled
        self.settings = settings
    }
}

// MARK: - Migration Support

extension ConnectorConfigFile {
    /// Migrate from older versions if needed
    static func migrate(from data: Data) throws -> ConnectorConfigFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode with current version
        var config = try decoder.decode(ConnectorConfigFile.self, from: data)

        // Apply migrations based on version
        if config.version < currentVersion {
            config = applyMigrations(config, from: config.version)
        }

        return config
    }

    /// Apply migrations from a given version to current
    private static func applyMigrations(_ config: ConnectorConfigFile, from version: Int) -> ConnectorConfigFile {
        var migrated = config

        // Version 1 is the initial version, no migrations needed yet
        // Future migrations would be added here:
        // if version < 2 { migrated = migrateV1ToV2(migrated) }

        migrated.version = currentVersion
        return migrated
    }
}
