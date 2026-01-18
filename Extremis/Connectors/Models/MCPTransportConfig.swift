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

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    /// Validate the configuration
    func validate() -> [String] {
        var errors: [String] = []

        if command.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Command cannot be empty")
        }

        return errors
    }
}

// MARK: - HTTP Configuration

/// Configuration for HTTP transport (remote servers)
struct HTTPConfig: Codable, Equatable {
    /// Server endpoint URL
    var url: URL

    /// Custom headers (non-sensitive)
    /// Sensitive headers (Authorization, etc.) are stored in Keychain
    var headers: [String: String]

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
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

        return errors
    }
}
