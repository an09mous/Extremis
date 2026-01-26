// MARK: - Custom MCP Server Configuration
// User-configured MCP server settings

import Foundation

/// Configuration for a custom MCP server
struct CustomMCPServerConfig: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID

    /// User-friendly display name
    var name: String

    /// Transport type (stdio or http)
    var type: MCPTransportType

    /// Whether this server is enabled
    var enabled: Bool

    /// Transport-specific configuration
    var transport: MCPTransportConfig

    /// Date when this config was created
    let createdAt: Date

    /// Date when this config was last modified
    var modifiedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        type: MCPTransportType,
        enabled: Bool = true,
        transport: MCPTransportConfig,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.transport = transport
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: - Convenience Initializers

    /// Create a STDIO server config
    static func stdio(
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        enabled: Bool = true
    ) -> CustomMCPServerConfig {
        CustomMCPServerConfig(
            name: name,
            type: .stdio,
            enabled: enabled,
            transport: .stdio(StdioConfig(command: command, args: args, env: env))
        )
    }

    /// Create an HTTP server config
    static func http(
        name: String,
        url: URL,
        headers: [String: String] = [:],
        enabled: Bool = true
    ) -> CustomMCPServerConfig {
        CustomMCPServerConfig(
            name: name,
            type: .http,
            enabled: enabled,
            transport: .http(HTTPConfig(url: url, headers: headers))
        )
    }

    // MARK: - Validation

    /// Validate the configuration
    /// Returns an array of error messages (empty if valid)
    func validate() -> [String] {
        var errors: [String] = []

        // Name validation
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            errors.append("Name cannot be empty")
        } else if trimmedName.count > 100 {
            errors.append("Name must be 100 characters or less")
        }

        // Transport type must match config
        switch (type, transport) {
        case (.stdio, .stdio):
            break // OK
        case (.http, .http):
            break // OK
        default:
            errors.append("Transport type mismatch")
        }

        // Transport-specific validation
        switch transport {
        case .stdio(let config):
            errors.append(contentsOf: config.validate())
        case .http(let config):
            errors.append(contentsOf: config.validate())
        }

        return errors
    }

    /// Whether this config is valid
    var isValid: Bool {
        validate().isEmpty
    }

    /// Whether this server requires OAuth authentication
    var requiresOAuth: Bool {
        switch transport {
        case .stdio(let config):
            return config.requiresOAuth
        case .http(let config):
            return config.requiresOAuth
        }
    }

    /// Get the OAuth config if present
    var oauthConfig: OAuthConfig? {
        switch transport {
        case .stdio(let config):
            return config.oauth
        case .http(let config):
            return config.oauth
        }
    }

    // MARK: - Modification

    /// Create a copy with updated modification date
    func withUpdatedTimestamp() -> CustomMCPServerConfig {
        var copy = self
        copy.modifiedAt = Date()
        return copy
    }
}

// MARK: - Codable Customization

extension CustomMCPServerConfig {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case enabled
        case transport
        case createdAt
        case modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(MCPTransportType.self, forKey: .type)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        transport = try container.decode(MCPTransportConfig.self, forKey: .transport)

        // Handle optional dates for backward compatibility
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}
