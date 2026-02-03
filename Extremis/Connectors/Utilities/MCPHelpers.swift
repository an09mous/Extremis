// MARK: - MCP Helpers
// Shared utilities for MCP connector implementations

import Foundation
import MCP

// MARK: - Schema Conversion

/// Converts MCP SDK Value (inputSchema) to our JSONSchema type
func convertSDKSchemaToJSONSchema(_ sdkSchema: Value) -> JSONSchema {
    guard case .object(let schemaDict) = sdkSchema else {
        return JSONSchema(type: "object", properties: [:], required: [])
    }

    // Extract type (should be "object")
    let schemaType: String
    if case .string(let typeStr) = schemaDict["type"] {
        schemaType = typeStr
    } else {
        schemaType = "object"
    }

    // Extract properties
    var properties: [String: JSONSchemaProperty] = [:]
    if case .object(let propsDict) = schemaDict["properties"] {
        for (key, value) in propsDict {
            properties[key] = JSONSchemaProperty(
                type: extractTypeFromSDKValue(value),
                description: extractDescriptionFromSDKValue(value)
            )
        }
    }

    // Extract required
    var required: [String] = []
    if case .array(let reqArray) = schemaDict["required"] {
        for item in reqArray {
            if case .string(let reqName) = item {
                required.append(reqName)
            }
        }
    }

    return JSONSchema(
        type: schemaType,
        properties: properties,
        required: required
    )
}

/// Extract type from SDK Value
private func extractTypeFromSDKValue(_ value: Value) -> String {
    if case .object(let dict) = value {
        if case .string(let typeStr) = dict["type"] {
            return typeStr
        }
    }
    return "string"
}

/// Extract description from SDK Value
private func extractDescriptionFromSDKValue(_ value: Value) -> String? {
    if case .object(let dict) = value {
        if case .string(let desc) = dict["description"] {
            return desc
        }
    }
    return nil
}

// MARK: - Argument Conversion

/// Converts our arguments dictionary to SDK Value dictionary
func convertArgumentsToSDKValues(_ arguments: [String: JSONValue]) -> [String: Value] {
    var result: [String: Value] = [:]
    for (key, value) in arguments {
        result[key] = convertJSONValueToSDKValue(value)
    }
    return result
}

/// Convert our JSONValue to SDK Value
private func convertJSONValueToSDKValue(_ jsonValue: JSONValue) -> Value {
    switch jsonValue {
    case .null:
        return .null
    case .bool(let b):
        return .bool(b)
    case .int(let i):
        return .int(i)
    case .double(let d):
        return .double(d)
    case .string(let s):
        return .string(s)
    case .array(let arr):
        return .array(arr.map { convertJSONValueToSDKValue($0) })
    case .object(let dict):
        var result: [String: Value] = [:]
        for (k, v) in dict {
            result[k] = convertJSONValueToSDKValue(v)
        }
        return .object(result)
    }
}

// MARK: - Result Conversion

/// Convert SDK tool result content to our ToolResult
func convertSDKContentToToolResult(
    content: [Tool.Content],
    isError: Bool?,
    callID: String,
    toolName: String,
    duration: TimeInterval
) -> ToolResult {
    var textParts: [String] = []

    for item in content {
        switch item {
        case .text(let text):
            textParts.append(text)
        case .image(data: _, mimeType: let mimeType, metadata: _):
            textParts.append("[Image: \(mimeType)]")
        case .resource(uri: let uri, mimeType: _, text: let text):
            if let text = text {
                textParts.append(text)
            } else {
                textParts.append("[Resource: \(uri)]")
            }
        case .audio(data: _, mimeType: let mimeType):
            textParts.append("[Audio: \(mimeType)]")
        }
    }

    let resultText = textParts.joined(separator: "\n")

    if isError == true {
        return ToolResult.failure(
            callID: callID,
            toolName: toolName,
            error: ToolError(message: resultText.isEmpty ? "Tool execution failed" : resultText),
            duration: duration
        )
    } else {
        return ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .success(ToolContent.text(resultText)),
            duration: duration
        )
    }
}

// MARK: - Timeout Helpers

/// Execute an operation with timeout using TaskGroup racing
func withMCPTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw ConnectorError.connectionTimeout
        }
        guard let result = try await group.next() else {
            throw ConnectorError.connectionTimeout
        }
        group.cancelAll()
        return result
    }
}

/// Execute an operation with timeout and proper cancellation propagation
func withCancellableMCPTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try Task.checkCancellation()

    return try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ConnectorError.connectionTimeout
            }
            guard let result = try await group.next() else {
                throw ConnectorError.connectionTimeout
            }
            group.cancelAll()
            return result
        }
    } onCancel: {
        // Parent cancelled - TaskGroup will throw CancellationError
    }
}
