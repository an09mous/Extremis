// MARK: - Tool Call Record Factory Extensions
// Factory methods that depend on runtime types (ToolCall, ToolResult, etc.)
// Separated from ToolCallRecord.swift for clean standalone compilation of Codable structs

import Foundation

// MARK: - ToolCallRecord Factory

extension ToolCallRecord {
    /// Create from a ToolCall
    static func from(_ toolCall: ToolCall) -> ToolCallRecord {
        // Encode arguments to JSON string
        let argsJSON: String
        if let data = try? JSONEncoder().encode(toolCall.arguments),
           let str = String(data: data, encoding: .utf8) {
            argsJSON = str
        } else {
            argsJSON = "{}"
        }

        return ToolCallRecord(
            id: toolCall.id,
            toolName: toolCall.toolName,
            connectorID: toolCall.connectorID,
            argumentsJSON: argsJSON,
            requestedAt: toolCall.requestedAt
        )
    }

    /// Create from an LLMToolCall with connector info
    static func from(_ llmCall: LLMToolCall, connectorID: String) -> ToolCallRecord {
        // Encode arguments to JSON string
        let argsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: llmCall.arguments),
           let str = String(data: data, encoding: .utf8) {
            argsJSON = str
        } else {
            argsJSON = "{}"
        }

        return ToolCallRecord(
            id: llmCall.id,
            toolName: llmCall.name,
            connectorID: connectorID,
            argumentsJSON: argsJSON,
            requestedAt: Date()
        )
    }
}

// MARK: - ToolResultRecord Factory

extension ToolResultRecord {
    /// Create from a ToolResult
    static func from(_ result: ToolResult) -> ToolResultRecord {
        let content: String
        let isSuccess: Bool

        switch result.outcome {
        case .success(let toolContent):
            isSuccess = true
            // Truncate content for storage (keep first 2000 chars for reasonable storage)
            let fullContent = toolContent.contentForLLM
            content = fullContent.count > 2000 ? String(fullContent.prefix(2000)) + "..." : fullContent
        case .error(let error):
            isSuccess = false
            content = error.message
        }

        return ToolResultRecord(
            callID: result.callID,
            toolName: result.toolName,
            isSuccess: isSuccess,
            content: content,
            duration: result.duration,
            completedAt: result.completedAt
        )
    }
}

// MARK: - ToolExecutionRoundRecord Factory

extension ToolExecutionRoundRecord {
    /// Create from internal ToolCall and ToolResult arrays
    static func from(
        toolCalls: [ToolCall],
        results: [ToolResult]
    ) -> ToolExecutionRoundRecord {
        ToolExecutionRoundRecord(
            toolCalls: toolCalls.map { ToolCallRecord.from($0) },
            results: results.map { ToolResultRecord.from($0) }
        )
    }
}

// MARK: - Array Extension for ToolExecutionRound Conversion

extension Array where Element == ToolExecutionRoundRecord {
    /// Convert persisted records back to ToolExecutionRound for LLM context
    /// This allows previous tool executions to be included in follow-up requests
    func toToolExecutionRounds() -> [ToolExecutionRound] {
        map { record in
            // Convert ToolCallRecord -> LLMToolCall
            let llmCalls = record.toolCalls.map { callRecord in
                // Parse arguments JSON back to dictionary
                var args: [String: Any] = [:]
                if let data = callRecord.argumentsJSON.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    args = dict
                }

                return LLMToolCall(
                    id: callRecord.id,
                    name: callRecord.toolName,
                    arguments: args
                )
            }

            // Convert ToolResultRecord -> ToolResult
            let results = record.results.map { resultRecord in
                let outcome: ToolOutcome
                if resultRecord.isSuccess {
                    outcome = .success(ToolContent.text(resultRecord.content))
                } else {
                    outcome = .error(ToolError(message: resultRecord.content))
                }

                return ToolResult(
                    callID: resultRecord.callID,
                    toolName: resultRecord.toolName,
                    outcome: outcome,
                    duration: resultRecord.duration,
                    completedAt: resultRecord.completedAt
                )
            }

            return ToolExecutionRound(toolCalls: llmCalls, results: results)
        }
    }
}
