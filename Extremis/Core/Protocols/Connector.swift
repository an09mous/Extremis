// MARK: - Connector Protocol
// Defines the contract for connectors (MCP servers and built-in integrations)

import Foundation

// MARK: - Connector State

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

    var statusIcon: String {
        switch self {
        case .disconnected: return "circle"          // SF Symbol
        case .connecting: return "circle.dotted"
        case .connected: return "circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var statusColor: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "yellow"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

// MARK: - Connector Protocol

/// Protocol for all connectors (built-in and custom MCP servers)
@MainActor
protocol Connector: AnyObject, Identifiable, ObservableObject {
    /// Unique identifier for this connector
    var id: String { get }

    /// Display name for the connector
    var name: String { get }

    /// Current connection state
    var state: ConnectorState { get }

    /// Tools discovered from this connector
    var tools: [ConnectorTool] { get }

    /// Whether this connector is enabled in config
    var isEnabled: Bool { get }

    /// Connect to the connector
    /// - Throws: ConnectorError on failure
    func connect() async throws

    /// Disconnect from the connector
    func disconnect() async

    /// Execute a tool call
    /// - Parameter call: The tool call to execute
    /// - Returns: The result of the tool execution
    /// - Throws: ConnectorError on failure
    func executeTool(_ call: ToolCall) async throws -> ToolResult
}

// MARK: - Connector Error

/// Errors that can occur with connectors
enum ConnectorError: LocalizedError, Equatable {
    case notConnected
    case connectionFailed(String)
    case connectionTimeout
    case toolNotFound(String)
    case toolExecutionFailed(String)
    case toolExecutionTimeout
    case invalidResponse(String)
    case processSpawnFailed(String)
    case protocolError(String)
    case authenticationRequired
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connector is not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionTimeout:
            return "Connection timed out"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .toolExecutionTimeout:
            return "Tool execution timed out"
        case .invalidResponse(let detail):
            return "Invalid response from connector: \(detail)"
        case .processSpawnFailed(let reason):
            return "Failed to start connector process: \(reason)"
        case .protocolError(let detail):
            return "Protocol error: \(detail)"
        case .authenticationRequired:
            return "Authentication required for this connector"
        case .unknown(let message):
            return "Connector error: \(message)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .connectionTimeout, .toolExecutionTimeout:
            return true
        case .connectionFailed, .processSpawnFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Connector Constants

/// Constants for connector operations
enum ConnectorConstants {
    /// Connection timeout in seconds
    static let connectionTimeout: TimeInterval = 5.0

    /// Tool execution timeout in seconds
    static let toolExecutionTimeout: TimeInterval = 30.0

    /// Maximum retry attempts for auto-reconnect
    static let maxReconnectAttempts = 3

    /// Base delay for exponential backoff (seconds)
    static let reconnectBaseDelay: TimeInterval = 1.0

    /// Tool discovery timeout in seconds
    static let toolDiscoveryTimeout: TimeInterval = 3.0
}
