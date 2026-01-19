// MARK: - Chat Tool Call
// UI model for displaying tool calls in chat messages

import Foundation

/// Represents a tool call for display in the chat UI
/// This is a view model layer between LLMToolCall and the UI
struct ChatToolCall: Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier (from LLM response)
    let id: String

    /// Display name of the tool (e.g., "github_search_issues")
    let toolName: String

    /// Connector that provides this tool
    let connectorID: String

    /// Human-readable description of arguments
    let argumentsSummary: String

    /// Current execution state
    var state: ToolCallState

    /// Result summary (for display after completion)
    var resultSummary: String?

    /// Error message (if execution failed)
    var errorMessage: String?

    /// Execution duration (after completion)
    var duration: TimeInterval?

    // MARK: - Computed Properties

    /// Whether execution is in progress
    var isExecuting: Bool {
        state == .executing
    }

    /// Whether execution completed (success or failure)
    var isComplete: Bool {
        switch state {
        case .completed, .failed:
            return true
        case .pending, .executing:
            return false
        }
    }

    /// Formatted duration string
    var durationString: String? {
        guard let duration = duration else { return nil }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        return String(format: "%.1fs", duration)
    }

    /// Icon for current state
    var stateIcon: String {
        switch state {
        case .pending:
            return "clock"
        case .executing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    /// Color for current state
    var stateColorName: String {
        switch state {
        case .pending:
            return "secondary"
        case .executing:
            return "blue"
        case .completed:
            return "green"
        case .failed:
            return "red"
        }
    }

    // MARK: - Initialization

    init(
        id: String,
        toolName: String,
        connectorID: String,
        argumentsSummary: String,
        state: ToolCallState = .pending,
        resultSummary: String? = nil,
        errorMessage: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
        self.argumentsSummary = argumentsSummary
        self.state = state
        self.resultSummary = resultSummary
        self.errorMessage = errorMessage
        self.duration = duration
    }

    // MARK: - Factory Methods

    /// Create from an LLMToolCall
    static func from(_ llmCall: LLMToolCall, connectorID: String) -> ChatToolCall {
        let summary = formatArgumentsSummary(llmCall.arguments)
        return ChatToolCall(
            id: llmCall.id,
            toolName: llmCall.name,
            connectorID: connectorID,
            argumentsSummary: summary
        )
    }

    /// Create from a ToolCall (already resolved)
    static func from(_ toolCall: ToolCall) -> ChatToolCall {
        let summary = formatArgumentsSummary(toolCall.argumentsAsAny)
        return ChatToolCall(
            id: toolCall.id,
            toolName: toolCall.toolName,
            connectorID: toolCall.connectorID,
            argumentsSummary: summary
        )
    }

    // MARK: - State Updates

    /// Mark as executing
    mutating func markExecuting() {
        state = .executing
    }

    /// Mark as completed with result
    mutating func markCompleted(resultSummary: String, duration: TimeInterval) {
        state = .completed
        self.resultSummary = resultSummary
        self.duration = duration
    }

    /// Mark as failed with error
    mutating func markFailed(error: String, duration: TimeInterval) {
        state = .failed
        self.errorMessage = error
        self.duration = duration
    }

    // MARK: - Private Helpers

    /// Format arguments dictionary into human-readable summary
    private static func formatArgumentsSummary(_ args: [String: Any]) -> String {
        guard !args.isEmpty else { return "(no arguments)" }

        // Format as key=value pairs, truncating long values
        let formatted = args.map { key, value in
            let valueStr = String(describing: value)
            let truncated = valueStr.count > 30 ? String(valueStr.prefix(30)) + "..." : valueStr
            return "\(key)=\(truncated)"
        }

        let joined = formatted.joined(separator: ", ")
        return joined.count > 100 ? String(joined.prefix(100)) + "..." : joined
    }
}

// MARK: - Tool Call State

/// Execution state of a tool call
enum ToolCallState: Equatable {
    /// Waiting to execute
    case pending
    /// Currently executing
    case executing
    /// Completed successfully
    case completed
    /// Execution failed
    case failed
}

// MARK: - Tool Calls Collection

/// Extension for managing collections of tool calls
extension Array where Element == ChatToolCall {

    /// Find a tool call by ID
    func toolCall(withID id: String) -> ChatToolCall? {
        first { $0.id == id }
    }

    /// Update a tool call's state
    mutating func updateState(id: String, state: ToolCallState) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].state = state
    }

    /// Mark a tool call as completed
    mutating func markCompleted(id: String, resultSummary: String, duration: TimeInterval) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].markCompleted(resultSummary: resultSummary, duration: duration)
    }

    /// Mark a tool call as failed
    mutating func markFailed(id: String, error: String, duration: TimeInterval) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].markFailed(error: error, duration: duration)
    }

    /// Whether all tool calls are complete
    var allComplete: Bool {
        allSatisfy { $0.isComplete }
    }

    /// Whether any tool calls failed
    var hasFailures: Bool {
        contains { $0.state == .failed }
    }
}
