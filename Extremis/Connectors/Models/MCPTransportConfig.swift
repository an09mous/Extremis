// MARK: - MCP Transport Configuration
// Transport type and configuration for MCP servers

import Foundation

// MARK: - Transport Type

/// Transport type enumeration
enum MCPTransportType: String, Codable, CaseIterable {
    case stdio   // Local server via subprocess (stdin/stdout)
    case http    // Remote server via HTTP/SSE

    var displayName: String {
        switch self {
        case .stdio: return "Local (STDIO)"
        case .http: return "Remote (HTTP)"
        }
    }

    var description: String {
        switch self {
        case .stdio: return "Runs as a local subprocess, communicates via stdin/stdout"
        case .http: return "Connects to a remote server via HTTP with Server-Sent Events"
        }
    }
}

// MARK: - Transport Configuration

/// Transport-specific configuration
enum MCPTransportConfig: Codable, Equatable {
    case stdio(StdioConfig)
    case http(HTTPConfig)

    private enum CodingKeys: String, CodingKey {
        case stdio
        case http
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stdioConfig = try container.decodeIfPresent(StdioConfig.self, forKey: .stdio) {
            self = .stdio(stdioConfig)
        } else if let httpConfig = try container.decodeIfPresent(HTTPConfig.self, forKey: .http) {
            self = .http(httpConfig)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "No valid transport configuration found"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stdio(let config):
            try container.encode(config, forKey: .stdio)
        case .http(let config):
            try container.encode(config, forKey: .http)
        }
    }

    /// Get the transport type
    var type: MCPTransportType {
        switch self {
        case .stdio: return .stdio
        case .http: return .http
        }
    }
}

// MARK: - STDIO Configuration

/// Configuration for STDIO transport (local servers)
struct StdioConfig: Codable, Equatable {
    /// Command to execute (full path or PATH-resolved)
    var command: String

    /// Command line arguments
    var args: [String]

    /// Environment variables (non-sensitive only - stored in config)
    /// Sensitive values are stored in Keychain and merged at runtime
    var env: [String: String]

    /// OAuth configuration (optional - for OAuth-protected servers)
    var oauth: OAuthConfig?

    init(command: String, args: [String] = [], env: [String: String] = [:], oauth: OAuthConfig? = nil) {
        self.command = command
        self.args = args
        self.env = env
        self.oauth = oauth
    }

    /// Validate the configuration
    func validate() -> [String] {
        var errors: [String] = []

        if command.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Command cannot be empty")
        }

        // Validate OAuth config if present
        if let oauthConfig = oauth {
            errors.append(contentsOf: oauthConfig.validate().map { "OAuth: \($0)" })
        }

        return errors
    }

    /// Whether this config requires OAuth authentication
    var requiresOAuth: Bool {
        oauth != nil
    }
}

// MARK: - HTTP Configuration

/// Configuration for HTTP transport (remote servers)
struct HTTPConfig: Equatable {
    /// Server endpoint URL
    var url: URL

    /// Custom headers (non-sensitive)
    /// Sensitive headers (Authorization, etc.) are stored in Keychain
    var headers: [String: String]

    /// OAuth configuration (optional - for OAuth-protected servers with manual config)
    var oauth: OAuthConfig?

    /// Whether to use MCP OAuth auto-discovery (RFC 9728 / RFC 8414)
    /// When true, OAuth endpoints are discovered automatically from the server
    var useAutoDiscovery: Bool

    /// Client ID for OAuth (required when useAutoDiscovery is true)
    /// This identifies the application to the OAuth provider
    var oauthClientId: String?

    init(url: URL, headers: [String: String] = [:], oauth: OAuthConfig? = nil, useAutoDiscovery: Bool = false, oauthClientId: String? = nil) {
        self.url = url
        self.headers = headers
        self.oauth = oauth
        self.useAutoDiscovery = useAutoDiscovery
        self.oauthClientId = oauthClientId
    }

    /// Validate the configuration
    func validate() -> [String] {
        var errors: [String] = []

        // Must be HTTPS for security
        if url.scheme?.lowercased() != "https" {
            errors.append("URL must use HTTPS for security")
        }

        if url.host?.isEmpty ?? true {
            errors.append("URL must have a valid host")
        }

        // Validate OAuth config if present
        if let oauthConfig = oauth {
            errors.append(contentsOf: oauthConfig.validate().map { "OAuth: \($0)" })
        }

        // Validate auto-discovery config
        if useAutoDiscovery {
            if oauthClientId?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                errors.append("OAuth Client ID is required for auto-discovery")
            }
        }

        return errors
    }

    /// Whether this config requires OAuth authentication
    var requiresOAuth: Bool {
        oauth != nil || useAutoDiscovery
    }

    /// Whether this config uses auto-discovery for OAuth
    var usesAutoDiscovery: Bool {
        useAutoDiscovery && oauthClientId != nil && !oauthClientId!.isEmpty
    }
}

// MARK: - HTTPConfig Codable (Backwards Compatible)

extension HTTPConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case url
        case headers
        case oauth
        case useAutoDiscovery
        case oauthClientId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        url = try container.decode(URL.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        oauth = try container.decodeIfPresent(OAuthConfig.self, forKey: .oauth)

        // New fields with backwards-compatible defaults
        useAutoDiscovery = try container.decodeIfPresent(Bool.self, forKey: .useAutoDiscovery) ?? false
        oauthClientId = try container.decodeIfPresent(String.self, forKey: .oauthClientId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(url, forKey: .url)
        try container.encode(headers, forKey: .headers)
        try container.encodeIfPresent(oauth, forKey: .oauth)
        try container.encode(useAutoDiscovery, forKey: .useAutoDiscovery)
        try container.encodeIfPresent(oauthClientId, forKey: .oauthClientId)
    }
}
