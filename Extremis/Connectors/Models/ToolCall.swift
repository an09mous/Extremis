// MARK: - Tool Call
// Request to execute a connector tool

import Foundation

/// Request to execute a connector tool
struct ToolCall: Identifiable, Sendable {
    /// Unique call identifier (typically from LLM response)
    let id: String

    /// Disambiguated tool name to invoke (e.g., "github_search_issues")
    let toolName: String

    /// Connector ID that provides this tool
    let connectorID: String

    /// Original tool name (without connector prefix)
    let originalToolName: String

    /// Arguments as JSON-compatible dictionary
    let arguments: [String: JSONValue]

    /// Timestamp of request
    let requestedAt: Date

    // MARK: - Initialization

    init(
        id: String,
        toolName: String,
        connectorID: String,
        originalToolName: String,
        arguments: [String: JSONValue],
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
        self.originalToolName = originalToolName
        self.arguments = arguments
        self.requestedAt = requestedAt
    }

    /// Create from a tool and arguments
    static func create(
        id: String,
        tool: ConnectorTool,
        arguments: [String: JSONValue]
    ) -> ToolCall {
        ToolCall(
            id: id,
            toolName: tool.name,
            connectorID: tool.connectorID,
            originalToolName: tool.originalName,
            arguments: arguments
        )
    }

    /// Create from LLM tool call with tool lookup
    static func from(
        llmCallID: String,
        toolName: String,
        arguments: [String: JSONValue],
        availableTools: [ConnectorTool]
    ) -> ToolCall? {
        guard let tool = availableTools.tool(named: toolName) else {
            return nil
        }

        return ToolCall(
            id: llmCallID,
            toolName: toolName,
            connectorID: tool.connectorID,
            originalToolName: tool.originalName,
            arguments: arguments
        )
    }

    // MARK: - Argument Conversion

    /// Convert arguments to native Swift types for MCP call
    var argumentsAsAny: [String: Any] {
        arguments.mapValues { $0.asAny }
    }

    /// Get arguments as JSON data
    func argumentsAsData() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(arguments)
    }
}

// MARK: - Equatable

extension ToolCall: Equatable {
    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id &&
        lhs.toolName == rhs.toolName &&
        lhs.connectorID == rhs.connectorID
    }
}

// MARK: - Hashable

extension ToolCall: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Debug Description

extension ToolCall: CustomDebugStringConvertible {
    var debugDescription: String {
        "ToolCall(id: \(id), tool: \(toolName), connector: \(connectorID))"
    }
}
