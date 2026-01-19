# Data Model: Connectors (MCP Support)

**Feature**: Connectors (MCP Support)
**Date**: 2026-01-18
**Spec**: [spec.md](./spec.md)

## Overview

This document defines the data models for Connectors support in Extremis. The system supports two types of connectors:

1. **Built-in Connectors** - Pre-configured integrations (GitHub, Web Search, Jira)
2. **Custom MCP Servers** - User-configured MCP servers

Models are organized by concern: configuration persistence, runtime state, and tool execution.

---

## Configuration Models

### ConnectorConfigFile

Root structure for the `connectors.json` file.

```swift
/// Root structure for connectors.json
struct ConnectorConfigFile: Codable {
    /// Schema version for migrations
    var version: Int

    /// Built-in connector configurations
    var builtIn: [String: BuiltInConnectorConfig]

    /// Custom MCP server configurations
    var custom: [CustomMCPServerConfig]

    static let currentVersion = 1

    static let empty = ConnectorConfigFile(
        version: currentVersion,
        builtIn: [:],
        custom: []
    )
}
```

### BuiltInConnectorConfig

Configuration for a built-in connector.

```swift
/// Configuration for a built-in connector
struct BuiltInConnectorConfig: Codable, Equatable {
    /// Whether this connector is enabled
    var enabled: Bool

    /// Optional connector-specific settings
    var settings: [String: String]?

    static let disabled = BuiltInConnectorConfig(enabled: false, settings: nil)
}

/// Enum of available built-in connectors
enum BuiltInConnectorType: String, Codable, CaseIterable {
    case github
    case webSearch
    case jira

    /// Display name for UI
    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .webSearch: return "Web Search"
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
}
```

### CustomMCPServerConfig

Configuration for a custom MCP server.

```swift
/// Configuration for a custom MCP server
struct CustomMCPServerConfig: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID

    /// User-friendly display name
    var name: String

    /// Transport type
    var type: MCPTransportType

    /// Whether this server is enabled
    var enabled: Bool

    /// Transport-specific configuration
    var transport: MCPTransportConfig
}

/// Transport type enumeration
enum MCPTransportType: String, Codable {
    case stdio   // Local server via subprocess
    case http    // Remote server via HTTP/SSE
}

/// Transport-specific configuration
enum MCPTransportConfig: Codable, Equatable {
    case stdio(StdioConfig)
    case http(HTTPConfig)
}

/// Configuration for STDIO transport (local servers)
struct StdioConfig: Codable, Equatable {
    /// Command to execute (full path or PATH-resolved)
    var command: String

    /// Command line arguments
    var args: [String]

    /// Environment variables (non-sensitive only - stored in config)
    /// Sensitive values are stored in Keychain and merged at runtime
    var env: [String: String]
}

/// Note: API keys and secrets for custom MCP servers are stored in Keychain.
/// Users enter them via secure input fields in the UI during server configuration.
/// At runtime, secrets are retrieved from Keychain and injected as env vars.

/// Configuration for HTTP transport (remote servers)
struct HTTPConfig: Codable, Equatable {
    /// Server endpoint URL
    var url: URL

    /// Custom headers (non-sensitive)
    var headers: [String: String]
}
```

### Example JSON

```json
{
  "version": 1,
  "builtIn": {
    "github": {
      "enabled": true,
      "settings": null
    },
    "webSearch": {
      "enabled": false,
      "settings": null
    },
    "jira": {
      "enabled": true,
      "settings": {
        "baseUrl": "https://mycompany.atlassian.net"
      }
    }
  },
  "custom": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Filesystem Tools",
      "type": "stdio",
      "enabled": true,
      "transport": {
        "stdio": {
          "command": "/usr/local/bin/mcp-filesystem",
          "args": ["--path", "/Users/me/projects"],
          "env": {}
        }
      }
    },
    {
      "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "name": "Remote API",
      "type": "http",
      "enabled": true,
      "transport": {
        "http": {
          "url": "https://api.example.com/mcp",
          "headers": {}
        }
      }
    }
  ]
}
```

---

## Connector Protocol

### Connector

Base protocol for all connectors (built-in and custom).

```swift
/// Connection state for a connector
enum ConnectorState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Base protocol for all connectors
@MainActor
protocol Connector: AnyObject, Identifiable, ObservableObject {
    /// Unique identifier
    var id: String { get }

    /// Display name
    var name: String { get }

    /// Current connection state
    var state: ConnectorState { get }

    /// Discovered tools from this connector
    var tools: [ConnectorTool] { get }

    /// Connect to the connector
    func connect() async throws

    /// Disconnect from the connector
    func disconnect() async

    /// Execute a tool
    func executeTool(_ call: ToolCall) async throws -> ToolResult
}
```

---

## Runtime Models

### BuiltInConnector

Runtime representation of a built-in connector.

```swift
/// Runtime representation of a built-in connector
@MainActor
final class BuiltInConnector: Connector, ObservableObject {
    let type: BuiltInConnectorType

    var id: String { type.rawValue }
    var name: String { type.displayName }

    @Published private(set) var state: ConnectorState = .disconnected
    @Published private(set) var tools: [ConnectorTool] = []

    /// Configuration from file
    var config: BuiltInConnectorConfig

    /// Internal MCP transport (if applicable)
    private var transport: MCPTransport?

    init(type: BuiltInConnectorType, config: BuiltInConnectorConfig) {
        self.type = type
        self.config = config
    }
}
```

### CustomMCPConnector

Runtime representation of a custom MCP server.

```swift
/// Runtime representation of a custom MCP server
@MainActor
final class CustomMCPConnector: Connector, ObservableObject {
    let config: CustomMCPServerConfig

    var id: String { config.id.uuidString }
    var name: String { config.name }

    @Published private(set) var state: ConnectorState = .disconnected
    @Published private(set) var tools: [ConnectorTool] = []

    /// Timestamp of last successful connection
    private(set) var connectedAt: Date?

    /// Last error message
    @Published private(set) var lastError: String?

    /// Transport layer
    private var transport: MCPTransport?

    init(config: CustomMCPServerConfig) {
        self.config = config
    }
}
```

---

## Tool Models

### ConnectorTool

Represents a tool discovered from a connector.

```swift
/// A tool discovered from a connector
struct ConnectorTool: Identifiable, Equatable {
    /// Original tool name from MCP server
    let originalName: String

    /// Human-readable description
    let description: String?

    /// JSON Schema for input parameters
    let inputSchema: JSONSchema

    /// Reference to source connector
    let connectorID: String

    /// Connector display name (for disambiguation)
    let connectorName: String

    /// Unique identifier for this tool instance
    var id: String { "\(connectorID):\(originalName)" }

    /// Disambiguated tool name for LLM (underscore prefix format)
    /// Example: "github_search_issues", "jira_create_issue"
    var name: String {
        let prefix = connectorName.lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(prefix)_\(originalName)"
    }

    /// Display name for UI (readable format)
    var displayName: String { "\(connectorName): \(originalName)" }
}

/// Simplified JSON Schema representation
struct JSONSchema: Codable, Equatable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let description: String?
}

struct JSONSchemaProperty: Codable, Equatable {
    let type: String
    let description: String?
    let `enum`: [String]?
    let items: JSONSchema?
}
```

### ToolCall

Represents a request to execute a tool.

```swift
/// Request to execute a connector tool
struct ToolCall: Identifiable, Equatable {
    /// Unique call identifier (from LLM)
    let id: String

    /// Tool name to invoke
    let toolName: String

    /// Connector ID that provides this tool
    let connectorID: String

    /// Arguments as JSON-compatible dictionary
    let arguments: [String: Any]

    /// Timestamp of request
    let requestedAt: Date

    // Equatable implementation for [String: Any]
    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id &&
        lhs.toolName == rhs.toolName &&
        lhs.connectorID == rhs.connectorID
    }
}
```

### ToolResult

Represents the result of a tool execution.

```swift
/// Result of a tool execution
struct ToolResult: Identifiable, Equatable {
    /// Matches the call ID
    let callID: String

    /// Tool that was executed
    let toolName: String

    /// Execution outcome
    let outcome: ToolOutcome

    /// Execution duration
    let duration: TimeInterval

    /// Identifier
    var id: String { callID }
}

/// Outcome of tool execution
enum ToolOutcome: Equatable {
    case success(ToolContent)
    case error(ToolError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Content returned by successful tool execution
struct ToolContent: Equatable {
    /// Text content (most common)
    let text: String?

    /// Raw JSON data (for complex responses)
    let json: Data?

    /// Image data (base64 encoded)
    let imageData: Data?

    /// MIME type for image
    let imageMimeType: String?

    /// Summary for display (truncated if needed)
    var displaySummary: String {
        if let text = text {
            return text.count > 200 ? String(text.prefix(200)) + "..." : text
        }
        if json != nil {
            return "[JSON data]"
        }
        if imageData != nil {
            return "[Image]"
        }
        return "[Empty result]"
    }
}

/// Error from tool execution
struct ToolError: Equatable, Error {
    /// Error message
    let message: String

    /// Error code (if provided)
    let code: Int?

    /// Whether this error is retryable
    let isRetryable: Bool
}
```

---

## Chat Integration Models

### ChatToolCall

Tool call attachment for chat messages.

```swift
/// Tool call attachment for chat messages
struct ChatToolCall: Codable, Equatable, Identifiable {
    /// Call ID from LLM
    let id: String

    /// Tool name
    let toolName: String

    /// Connector display name (for UI)
    let connectorName: String

    /// Arguments as JSON string
    let arguments: String

    /// Execution state
    var state: ChatToolCallState
}

/// State of a tool call within a chat message
enum ChatToolCallState: Codable, Equatable {
    case pending
    case executing
    case completed(String)  // Result summary
    case failed(String)     // Error message

    var isComplete: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}
```

### ChatToolResult

Tool result in chat context.

```swift
/// Tool result in chat context
struct ChatToolResult: Codable, Equatable {
    /// Matches tool call ID
    let callID: String

    /// Result content for display
    let content: String

    /// Whether execution succeeded
    let isSuccess: Bool
}
```

### ChatMessage Extensions

```swift
extension ChatMessage {
    /// Tool calls requested by this message (assistant messages only)
    var toolCalls: [ChatToolCall]? { get set }

    /// Tool result for this message (tool role messages only)
    var toolResult: ChatToolResult? { get set }
}
```

---

## LLM Provider Models

### Tool Definition Formats

Conversion structures for different LLM providers.

```swift
/// OpenAI function calling format
struct OpenAITool: Codable {
    let type: String = "function"
    let function: OpenAIFunction
}

struct OpenAIFunction: Codable {
    let name: String
    let description: String?
    let parameters: JSONSchema
}

/// Anthropic tool use format
struct AnthropicTool: Codable {
    let name: String
    let description: String?
    let input_schema: JSONSchema
}
```

### GenerationWithToolCalls

Response type for tool-aware generation.

```swift
/// Result of LLM generation that may include tool calls
struct GenerationWithToolCalls {
    /// Text content (may be partial if tools requested)
    let content: String?

    /// Tool calls requested by the model
    let toolCalls: [ToolCall]

    /// Whether generation is complete or awaiting tool results
    let isComplete: Bool

    /// Stop reason
    let stopReason: StopReason
}

enum StopReason {
    case endOfMessage
    case toolUse
    case maxTokens
    case error(String)
}
```

---

## Relationships

```
ConnectorConfigFile (persisted)
    ├── builtIn: [String: BuiltInConnectorConfig]
    └── custom: [CustomMCPServerConfig]

ConnectorRegistry (runtime)
    ├── builtInConnectors: [BuiltInConnector]
    └── customConnectors: [CustomMCPConnector]
            ├── state: ConnectorState
            └── tools: [ConnectorTool]

ChatMessage (conversation)
    ├── toolCalls: [ChatToolCall]?
    └── toolResult: ChatToolResult?

LLMProvider
    └── generateChatWithTools()
            └── returns GenerationWithToolCalls
                    └── toolCalls: [ToolCall]

ToolExecutor
    └── execute(ToolCall) → ToolResult
```

---

## Storage Locations

| Data | Location | Format |
|------|----------|--------|
| Connector configs | `~/Library/Application Support/Extremis/connectors.json` | JSON |
| **Secrets (API keys, tokens)** | **macOS Keychain** | Encrypted |
| Tool discovery cache | Memory only (re-discovered on connect) | Swift objects |
| Conversation history | Existing session persistence | JSON |

**Important**: Secrets are NEVER stored in the config file. The `env` field in config contains only non-sensitive environment variables. All API keys, tokens, and credentials are stored in macOS Keychain.

---

## Secrets Management

### Design Principle

**Keychain-only secrets**: Unlike Claude Desktop (which stores API keys in plain text in config), Extremis stores all secrets in macOS Keychain. This is more secure and follows macOS best practices.

### ConnectorSecrets Model

```swift
/// Secrets stored in Keychain for a connector
struct ConnectorSecrets: Codable {
    /// Environment variables that contain secrets (injected at runtime)
    var secretEnvVars: [String: String]

    /// HTTP headers that contain secrets (for HTTP transport)
    var secretHeaders: [String: String]

    /// Any additional secret values specific to the connector
    var additionalSecrets: [String: String]

    static let empty = ConnectorSecrets(
        secretEnvVars: [:],
        secretHeaders: [:],
        additionalSecrets: [:]
    )
}
```

### Keychain Storage

```swift
/// Keychain keys for connector credentials
enum ConnectorKeychainKey {
    case builtIn(BuiltInConnectorType)
    case custom(UUID)

    var key: String {
        switch self {
        case .builtIn(let type):
            return "connector.builtin.\(type.rawValue)"
        case .custom(let id):
            return "connector.custom.\(id.uuidString)"
        }
    }
}

/// Secrets storage service
final class ConnectorSecretsStorage {
    private let keychain: KeychainHelper

    /// Save secrets for a connector
    func saveSecrets(_ secrets: ConnectorSecrets, for key: ConnectorKeychainKey) throws

    /// Load secrets for a connector
    func loadSecrets(for key: ConnectorKeychainKey) throws -> ConnectorSecrets?

    /// Delete secrets for a connector
    func deleteSecrets(for key: ConnectorKeychainKey) throws
}
```

### Runtime Secret Injection

When connecting to a connector, secrets are retrieved from Keychain and injected:

```swift
/// At connection time:
func buildProcessEnvironment(config: CustomMCPServerConfig) async throws -> [String: String] {
    // 1. Start with non-sensitive env vars from config
    var env = config.transport.stdio?.env ?? [:]

    // 2. Load secrets from Keychain
    let keychainKey = ConnectorKeychainKey.custom(config.id)
    if let secrets = try secretsStorage.loadSecrets(for: keychainKey) {
        // 3. Merge secret env vars (secrets override config values)
        for (key, value) in secrets.secretEnvVars {
            env[key] = value
        }
    }

    return env
}
```

### Authentication Configuration

Each built-in connector defines its authentication requirements. The design is extensible to support OAuth in the future.

```swift
/// Authentication method for a connector
enum ConnectorAuthMethod {
    /// API key or token entered manually by user
    case apiKey(ApiKeyAuthConfig)

    /// OAuth flow (future support)
    // case oauth(OAuthConfig)
}

/// Configuration for API key authentication (current implementation)
struct ApiKeyAuthConfig {
    /// Fields the user needs to provide
    let fields: [AuthField]
}

/// Configuration for OAuth authentication (future)
struct OAuthConfig {
    let authorizationURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: [String]
    let redirectScheme: String  // e.g., "extremis://oauth"
}

/// Describes an authentication field for UI
struct AuthField {
    let key: String           // Environment variable name or credential key
    let label: String         // UI label
    let placeholder: String
    let helpText: String
    let isSecret: Bool        // If true, use secure text field and store in Keychain

    static func secret(key: String, label: String, placeholder: String, helpText: String) -> AuthField {
        AuthField(key: key, label: label, placeholder: placeholder, helpText: helpText, isSecret: true)
    }

    static func text(key: String, label: String, placeholder: String, helpText: String) -> AuthField {
        AuthField(key: key, label: label, placeholder: placeholder, helpText: helpText, isSecret: false)
    }
}
```

### Built-in Connector Auth Requirements

```swift
extension BuiltInConnectorType {
    /// Authentication method for this connector
    var authMethod: ConnectorAuthMethod {
        switch self {
        case .github:
            // Future: Could be .oauth(OAuthConfig(...)) for "Login with GitHub"
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
                    key: "TAVILY_API_KEY",
                    label: "Tavily API Key",
                    placeholder: "tvly-xxxxxxxxxxxx",
                    helpText: "Get your API key at tavily.com"
                )
            ]))

        case .jira:
            // Future: Could be .oauth(OAuthConfig(...)) for Atlassian OAuth
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

    /// Whether this connector supports OAuth (future extensibility)
    var supportsOAuth: Bool {
        switch self {
        case .github, .jira: return true  // Can add OAuth later
        case .webSearch: return false      // API key only
        }
    }
}
```

### Authentication Protocol (Extensible)

```swift
/// Protocol for handling connector authentication
/// Extensible for future OAuth support
protocol ConnectorAuthHandler {
    /// Check if connector is authenticated
    func isAuthenticated(for connector: BuiltInConnectorType) async -> Bool

    /// Get credentials for connecting (retrieves from Keychain)
    func getCredentials(for connector: BuiltInConnectorType) async throws -> ConnectorCredentials

    /// Save credentials (stores in Keychain)
    func saveCredentials(_ credentials: ConnectorCredentials, for connector: BuiltInConnectorType) async throws

    /// Clear credentials
    func clearCredentials(for connector: BuiltInConnectorType) async throws
}

/// Credentials retrieved for a connector
enum ConnectorCredentials {
    /// API key credentials (env vars to inject)
    case apiKey([String: String])

    /// OAuth credentials (future)
    // case oauth(accessToken: String, refreshToken: String?, expiresAt: Date?)
}

/// Current implementation: API key auth handler
final class ApiKeyAuthHandler: ConnectorAuthHandler {
    private let secretsStorage: ConnectorSecretsStorage

    func isAuthenticated(for connector: BuiltInConnectorType) async -> Bool {
        guard let secrets = try? secretsStorage.loadSecrets(for: .builtIn(connector)) else {
            return false
        }
        // Check all required fields are present
        let required = connector.authMethod.requiredKeys
        return required.allSatisfy { secrets.secretEnvVars[$0] != nil }
    }

    func getCredentials(for connector: BuiltInConnectorType) async throws -> ConnectorCredentials {
        guard let secrets = try secretsStorage.loadSecrets(for: .builtIn(connector)) else {
            throw AuthError.notAuthenticated
        }
        return .apiKey(secrets.secretEnvVars)
    }

    // ... save and clear implementations
}

/// Future: OAuth auth handler would implement same protocol
// final class OAuthAuthHandler: ConnectorAuthHandler { ... }

extension ConnectorAuthMethod {
    /// Keys that must be present for authentication to be complete
    var requiredKeys: [String] {
        switch self {
        case .apiKey(let config):
            return config.fields.filter { $0.isSecret }.map { $0.key }
        }
    }
}
```

### Adding OAuth in Future

To add OAuth support for a built-in connector (e.g., GitHub):

1. **Update auth method**:
```swift
case .github:
    return .oauth(OAuthConfig(
        authorizationURL: URL(string: "https://github.com/login/oauth/authorize")!,
        tokenURL: URL(string: "https://github.com/login/oauth/access_token")!,
        clientID: "your-client-id",
        scopes: ["repo", "read:user"],
        redirectScheme: "extremis"
    ))
```

2. **Implement OAuthAuthHandler** conforming to `ConnectorAuthHandler`

3. **Update UI** to show "Login with GitHub" button instead of text fields

4. **No changes needed** to connector connection logic - it just calls `getCredentials()` and gets back the token

### Custom MCP Server Secrets

For custom servers, users enter API keys directly in input fields during configuration. Extremis handles storage automatically:

**UI Flow (Simplified):**
1. User adds custom MCP server
2. User enters server details: name, command, args
3. User enters API keys in dedicated "API Keys" section (secure text fields)
4. Extremis stores API keys in Keychain automatically
5. Non-sensitive env vars (DEBUG_MODE, etc.) stored in config file
6. At runtime, secrets from Keychain are merged with config env vars

**No manual "mark as secret" needed** - the UI has separate sections:
- "Environment Variables" - stored in config (visible, shareable)
- "API Keys / Secrets" - stored in Keychain (encrypted, never exported)

### Config File (No Secrets)

The config file contains only non-sensitive data:

```json
{
  "version": 1,
  "builtIn": {
    "github": {
      "enabled": true,
      "settings": null
    }
  },
  "custom": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "My API Server",
      "type": "stdio",
      "enabled": true,
      "transport": {
        "stdio": {
          "command": "/usr/local/bin/my-server",
          "args": ["--verbose"],
          "env": {
            "DEBUG_MODE": "true",
            "LOG_LEVEL": "info"
          }
        }
      }
    }
  ]
}
```

**Note**: No secret values or secret field names in config. All secrets are stored in Keychain under `connector.custom.{uuid}`.

---

## Validation Rules

### BuiltInConnectorConfig
- `settings`: Must contain all `requiredSettings` for the connector type

### CustomMCPServerConfig
- `name`: Non-empty, max 100 characters
- `command` (STDIO): Must be valid path or resolvable command
- `url` (HTTP): Must be valid HTTPS URL
- `id`: Must be unique across all custom configs

### ConnectorTool
- `name`: Non-empty, alphanumeric with underscores
- `inputSchema`: Must be valid JSON Schema

### ToolCall
- `id`: Non-empty
- `arguments`: Must validate against tool's inputSchema
