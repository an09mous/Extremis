// MARK: - Connector Tool
// Represents a tool discovered from a connector

import Foundation

/// A tool discovered from a connector
struct ConnectorTool: Identifiable, Equatable, Sendable {
    /// Original tool name from MCP server
    let originalName: String

    /// Human-readable description
    let description: String?

    /// JSON Schema for input parameters
    let inputSchema: JSONSchema

    /// Reference to source connector ID
    let connectorID: String

    /// Connector display name (for disambiguation)
    let connectorName: String

    // MARK: - Computed Properties

    /// Unique identifier for this tool instance
    var id: String { "\(connectorID):\(originalName)" }

    /// Disambiguated tool name for LLM (underscore prefix format)
    /// Example: "github_search_issues", "jira_create_issue", "myserver_read_file"
    var name: String {
        let prefix = connectorName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return "\(prefix)_\(originalName)"
    }

    /// Display name for UI (readable format)
    var displayName: String { "\(connectorName): \(originalName)" }

    /// Short display name (just the original name)
    var shortName: String { originalName }

    // MARK: - Initialization

    init(
        originalName: String,
        description: String?,
        inputSchema: JSONSchema,
        connectorID: String,
        connectorName: String
    ) {
        self.originalName = originalName
        self.description = description
        self.inputSchema = inputSchema
        self.connectorID = connectorID
        self.connectorName = connectorName
    }

    /// Create from MCP tool
    static func from(
        mcpTool: MCPTool,
        connectorID: String,
        connectorName: String
    ) -> ConnectorTool {
        ConnectorTool(
            originalName: mcpTool.name,
            description: mcpTool.description,
            inputSchema: JSONSchema.from(mcpSchema: mcpTool.inputSchema),
            connectorID: connectorID,
            connectorName: connectorName
        )
    }

    // MARK: - Equatable

    static func == (lhs: ConnectorTool, rhs: ConnectorTool) -> Bool {
        lhs.id == rhs.id &&
        lhs.originalName == rhs.originalName &&
        lhs.connectorID == rhs.connectorID &&
        lhs.connectorName == rhs.connectorName
    }
}

// MARK: - Tool Lookup

extension Array where Element == ConnectorTool {
    /// Find a tool by its disambiguated name
    func tool(named name: String) -> ConnectorTool? {
        first { $0.name == name }
    }

    /// Find a tool by original name and connector ID
    func tool(originalName: String, connectorID: String) -> ConnectorTool? {
        first { $0.originalName == originalName && $0.connectorID == connectorID }
    }

    /// Get all tools from a specific connector
    func tools(forConnector connectorID: String) -> [ConnectorTool] {
        filter { $0.connectorID == connectorID }
    }

    /// Check for name collisions (tools with same original name from different connectors)
    var hasNameCollisions: Bool {
        let originalNames = map { $0.originalName }
        return originalNames.count != Set(originalNames).count
    }

    /// Group tools by connector
    var groupedByConnector: [String: [ConnectorTool]] {
        Dictionary(grouping: self) { $0.connectorID }
    }
}
