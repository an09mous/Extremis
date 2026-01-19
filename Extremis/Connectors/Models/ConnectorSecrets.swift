// MARK: - Connector Secrets
// Secrets stored in Keychain for connectors

import Foundation

/// Secrets stored in Keychain for a connector
struct ConnectorSecrets: Codable, Equatable {
    /// Environment variables that contain secrets (injected at runtime)
    var secretEnvVars: [String: String]

    /// HTTP headers that contain secrets (for HTTP transport)
    var secretHeaders: [String: String]

    /// Any additional secret values specific to the connector
    var additionalSecrets: [String: String]

    // MARK: - Factory

    static let empty = ConnectorSecrets(
        secretEnvVars: [:],
        secretHeaders: [:],
        additionalSecrets: [:]
    )

    // MARK: - Initialization

    init(
        secretEnvVars: [String: String] = [:],
        secretHeaders: [String: String] = [:],
        additionalSecrets: [String: String] = [:]
    ) {
        self.secretEnvVars = secretEnvVars
        self.secretHeaders = secretHeaders
        self.additionalSecrets = additionalSecrets
    }

    // MARK: - Convenience

    /// Whether any secrets are stored
    var isEmpty: Bool {
        secretEnvVars.isEmpty && secretHeaders.isEmpty && additionalSecrets.isEmpty
    }

    /// Total number of secrets
    var count: Int {
        secretEnvVars.count + secretHeaders.count + additionalSecrets.count
    }

    /// Merge environment variables with secrets (secrets take precedence)
    func mergeWithEnv(_ baseEnv: [String: String]) -> [String: String] {
        var merged = baseEnv
        for (key, value) in secretEnvVars {
            merged[key] = value
        }
        return merged
    }

    /// Merge headers with secret headers (secrets take precedence)
    func mergeWithHeaders(_ baseHeaders: [String: String]) -> [String: String] {
        var merged = baseHeaders
        for (key, value) in secretHeaders {
            merged[key] = value
        }
        return merged
    }
}

// MARK: - Keychain Key

/// Keychain keys for connector credentials
enum ConnectorKeychainKey {
    case builtIn(String)  // Built-in connector type name (e.g., "github")
    case custom(UUID)     // Custom MCP server UUID

    /// The actual keychain key string
    var key: String {
        switch self {
        case .builtIn(let type):
            return "connector.builtin.\(type)"
        case .custom(let id):
            return "connector.custom.\(id.uuidString)"
        }
    }

    /// Create from a connector ID string
    static func from(connectorID: String) -> ConnectorKeychainKey? {
        if connectorID.starts(with: "builtin.") {
            let type = String(connectorID.dropFirst("builtin.".count))
            return .builtIn(type)
        } else if let uuid = UUID(uuidString: connectorID) {
            return .custom(uuid)
        }
        return nil
    }
}

// MARK: - Built-in Connector Auth (Phase 2 placeholder)

/// Authentication method for a connector
enum ConnectorAuthMethod {
    /// API key or token entered manually by user
    case apiKey(ApiKeyAuthConfig)

    // Future: OAuth flow
    // case oauth(OAuthConfig)
}

/// Configuration for API key authentication
struct ApiKeyAuthConfig {
    /// Fields the user needs to provide
    let fields: [AuthField]
}

/// Describes an authentication field for UI
struct AuthField {
    /// Environment variable name or credential key
    let key: String

    /// UI label
    let label: String

    /// Placeholder text
    let placeholder: String

    /// Help text explaining where to get this value
    let helpText: String

    /// If true, use secure text field and store in Keychain
    let isSecret: Bool

    /// Create a secret field
    static func secret(key: String, label: String, placeholder: String, helpText: String) -> AuthField {
        AuthField(key: key, label: label, placeholder: placeholder, helpText: helpText, isSecret: true)
    }

    /// Create a regular text field
    static func text(key: String, label: String, placeholder: String, helpText: String) -> AuthField {
        AuthField(key: key, label: label, placeholder: placeholder, helpText: helpText, isSecret: false)
    }
}

// MARK: - Built-in Connector Type (Phase 2 placeholder)

/// Enum of available built-in connectors
enum BuiltInConnectorType: String, Codable, CaseIterable {
    case github
    case webSearch
    case jira

    /// Display name for UI
    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .webSearch: return "Brave Search"
        case .jira: return "Jira"
        }
    }

    /// Icon for UI (SF Symbol name)
    var iconName: String {
        switch self {
        case .github: return "link"
        case .webSearch: return "magnifyingglass"
        case .jira: return "list.clipboard"
        }
    }

    /// Description for UI
    var description: String {
        switch self {
        case .github: return "Access GitHub repositories, issues, and pull requests"
        case .webSearch: return "Search the web for current information"
        case .jira: return "Manage Jira issues and projects"
        }
    }

    /// Settings required for this connector (beyond just enabling)
    var requiredSettings: [String] {
        switch self {
        case .github: return []  // Just needs PAT in Keychain
        case .webSearch: return []  // Just needs API key in Keychain
        case .jira: return ["baseUrl"]  // Needs Jira instance URL
        }
    }

    /// Authentication method for this connector
    var authMethod: ConnectorAuthMethod {
        switch self {
        case .github:
            return .apiKey(ApiKeyAuthConfig(fields: [
                .secret(
                    key: "GITHUB_PERSONAL_ACCESS_TOKEN",
                    label: "Personal Access Token",
                    placeholder: "ghp_xxxxxxxxxxxx",
                    helpText: "Create at GitHub → Settings → Developer settings → Personal access tokens"
                )
            ]))

        case .webSearch:
            return .apiKey(ApiKeyAuthConfig(fields: [
                .secret(
                    key: "BRAVE_API_KEY",
                    label: "Brave Search API Key",
                    placeholder: "BSA...",
                    helpText: "Get your API key at brave.com/search/api"
                )
            ]))

        case .jira:
            return .apiKey(ApiKeyAuthConfig(fields: [
                .secret(
                    key: "JIRA_API_TOKEN",
                    label: "API Token",
                    placeholder: "Your Jira API token",
                    helpText: "Create at Atlassian → Account settings → Security → API tokens"
                ),
                .text(
                    key: "JIRA_EMAIL",
                    label: "Email",
                    placeholder: "you@company.com",
                    helpText: "Your Atlassian account email"
                )
            ]))
        }
    }
}
