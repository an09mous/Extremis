// MARK: - Tool Call Record
// Lightweight, Codable records for persisting tool calls and results in messages

import Foundation

/// Codable record of a tool call for persistence
/// Lighter-weight than ToolCall, designed for storage in ChatMessage
struct ToolCallRecord: Codable, Identifiable, Equatable, Sendable {
    /// Unique call identifier (matches LLM response ID)
    let id: String

    /// Disambiguated tool name (e.g., "github_search_issues")
    let toolName: String

    /// Connector ID that provides this tool
    let connectorID: String

    /// Arguments as JSON-encoded string for compact storage
    let argumentsJSON: String

    /// Timestamp when the call was requested
    let requestedAt: Date

    // MARK: - Initialization

    init(
        id: String,
        toolName: String,
        connectorID: String,
        argumentsJSON: String,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
        self.argumentsJSON = argumentsJSON
        self.requestedAt = requestedAt
    }

    // MARK: - Computed Properties

    /// Get arguments as dictionary (for display)
    var argumentsDisplay: String {
        // Parse JSON and format for display
        guard let data = argumentsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return argumentsJSON
        }

        // Format as key=value pairs
        let formatted = dict.map { key, value in
            let valueStr = String(describing: value)
            let truncated = valueStr.count > 30 ? String(valueStr.prefix(30)) + "..." : valueStr
            return "\(key)=\(truncated)"
        }

        let joined = formatted.joined(separator: ", ")
        return joined.count > 100 ? String(joined.prefix(100)) + "..." : joined
    }
}

// MARK: - Tool Result Record

/// Codable record of a tool execution result for persistence
struct ToolResultRecord: Codable, Identifiable, Equatable, Sendable {
    /// Matches the call ID
    let callID: String

    /// Tool name (for display)
    let toolName: String

    /// Whether execution succeeded
    let isSuccess: Bool

    /// Result content (truncated for storage) or error message
    let content: String

    /// Execution duration in seconds
    let duration: TimeInterval

    /// Timestamp when execution completed
    let completedAt: Date

    // MARK: - Identifiable

    var id: String { callID }

    // MARK: - Initialization

    init(
        callID: String,
        toolName: String,
        isSuccess: Bool,
        content: String,
        duration: TimeInterval,
        completedAt: Date = Date()
    ) {
        self.callID = callID
        self.toolName = toolName
        self.isSuccess = isSuccess
        self.content = content
        self.duration = duration
        self.completedAt = completedAt
    }

    // MARK: - Computed Properties

    /// Display summary (shorter than full content)
    var displaySummary: String {
        content.count > 200 ? String(content.prefix(200)) + "..." : content
    }

    /// Formatted duration string
    var durationString: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        return String(format: "%.1fs", duration)
    }
}

// MARK: - Tool Execution Round Record

/// Codable record of a complete tool execution round (calls + results)
struct ToolExecutionRoundRecord: Codable, Equatable, Sendable {
    /// Tool calls made in this round
    let toolCalls: [ToolCallRecord]

    /// Results from executing those calls
    let results: [ToolResultRecord]

    /// Assistant's text response after this tool round completed
    /// Used to rebuild complete conversation history for follow-up messages
    let assistantResponse: String?

    // MARK: - Initialization

    init(toolCalls: [ToolCallRecord], results: [ToolResultRecord], assistantResponse: String? = nil) {
        self.toolCalls = toolCalls
        self.results = results
        self.assistantResponse = assistantResponse
    }

    // MARK: - Computed Properties

    /// Whether all tool calls succeeded
    var allSucceeded: Bool {
        results.allSatisfy { $0.isSuccess }
    }

    /// Whether any tool calls failed
    var hasFailures: Bool {
        results.contains { !$0.isSuccess }
    }

    /// Total duration of all tool executions
    var totalDuration: TimeInterval {
        results.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Collection Extensions

extension Array where Element == ToolExecutionRoundRecord {
    /// Total number of tool calls across all rounds
    var totalToolCalls: Int {
        reduce(0) { $0 + $1.toolCalls.count }
    }

    /// Total number of failed tool calls
    var totalFailures: Int {
        reduce(0) { sum, round in
            sum + round.results.filter { !$0.isSuccess }.count
        }
    }

}
