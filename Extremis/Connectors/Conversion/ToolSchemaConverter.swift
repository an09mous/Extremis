// MARK: - Tool Schema Converter
// Converts ConnectorTool to provider-specific formats

import Foundation

/// Converts ConnectorTool schemas to LLM provider-specific formats
enum ToolSchemaConverter {

    // MARK: - OpenAI Format

    /// Convert tools to OpenAI function calling format
    static func toOpenAI(tools: [ConnectorTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description ?? "No description available",
                    "parameters": toOpenAIParameters(tool.inputSchema)
                ] as [String: Any]
            ]
        }
    }

    /// Convert JSON Schema to OpenAI parameters format
    private static func toOpenAIParameters(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [
            "type": schema.type
        ]

        if let properties = schema.properties {
            result["properties"] = properties.mapValues { toOpenAIProperty($0) }
        }

        if let required = schema.required, !required.isEmpty {
            result["required"] = required
        }

        return result
    }

    /// Convert JSON Schema property to OpenAI format
    private static func toOpenAIProperty(_ property: JSONSchemaProperty) -> [String: Any] {
        var result: [String: Any] = [:]

        if let type = property.type {
            result["type"] = type
        }

        if let description = property.description {
            result["description"] = description
        }

        if let enumValues = property.enum {
            result["enum"] = enumValues
        }

        if let items = property.items {
            result["items"] = toOpenAIParameters(items)
        }

        if let nestedProperties = property.properties {
            result["properties"] = nestedProperties.mapValues { toOpenAIProperty($0) }
        }

        if let required = property.required {
            result["required"] = required
        }

        return result
    }

    // MARK: - Anthropic Format

    /// Convert tools to Anthropic tool use format
    static func toAnthropic(tools: [ConnectorTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description ?? "No description available",
                "input_schema": toAnthropicInputSchema(tool.inputSchema)
            ]
        }
    }

    /// Convert JSON Schema to Anthropic input_schema format
    private static func toAnthropicInputSchema(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [
            "type": schema.type
        ]

        if let properties = schema.properties {
            result["properties"] = properties.mapValues { toAnthropicProperty($0) }
        }

        if let required = schema.required, !required.isEmpty {
            result["required"] = required
        }

        return result
    }

    /// Convert JSON Schema property to Anthropic format
    private static func toAnthropicProperty(_ property: JSONSchemaProperty) -> [String: Any] {
        var result: [String: Any] = [:]

        if let type = property.type {
            result["type"] = type
        }

        if let description = property.description {
            result["description"] = description
        }

        if let enumValues = property.enum {
            result["enum"] = enumValues
        }

        if let items = property.items {
            result["items"] = toAnthropicInputSchema(items)
        }

        if let nestedProperties = property.properties {
            result["properties"] = nestedProperties.mapValues { toAnthropicProperty($0) }
        }

        if let required = property.required {
            result["required"] = required
        }

        return result
    }

    // MARK: - Gemini Format

    /// Convert tools to Gemini function declarations format
    static func toGemini(tools: [ConnectorTool]) -> [[String: Any]] {
        [
            [
                "function_declarations": tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description ?? "No description available",
                        "parameters": toGeminiParameters(tool.inputSchema)
                    ] as [String: Any]
                }
            ]
        ]
    }

    /// Convert JSON Schema to Gemini parameters format
    private static func toGeminiParameters(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [
            "type": schema.type.uppercased()  // Gemini uses uppercase types
        ]

        if let properties = schema.properties {
            result["properties"] = properties.mapValues { toGeminiProperty($0) }
        }

        if let required = schema.required, !required.isEmpty {
            result["required"] = required
        }

        return result
    }

    /// Convert JSON Schema property to Gemini format
    private static func toGeminiProperty(_ property: JSONSchemaProperty) -> [String: Any] {
        var result: [String: Any] = [:]

        if let type = property.type {
            result["type"] = type.uppercased()
        }

        if let description = property.description {
            result["description"] = description
        }

        if let enumValues = property.enum {
            result["enum"] = enumValues
        }

        if let items = property.items {
            result["items"] = toGeminiParameters(items)
        }

        if let nestedProperties = property.properties {
            result["properties"] = nestedProperties.mapValues { toGeminiProperty($0) }
        }

        if let required = property.required {
            result["required"] = required
        }

        return result
    }

    // MARK: - JSON Encoding

    /// Convert tools to JSON data for OpenAI
    static func toOpenAIJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toOpenAI(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }

    /// Convert tools to JSON data for Anthropic
    static func toAnthropicJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toAnthropic(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }

    /// Convert tools to JSON data for Gemini
    static func toGeminiJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toGemini(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }
}

// MARK: - Tool Call Parsing

extension ToolSchemaConverter {

    /// Parse OpenAI tool call response
    static func parseOpenAIToolCall(
        id: String,
        functionName: String,
        argumentsJSON: String,
        availableTools: [ConnectorTool]
    ) -> ToolCall? {
        guard let tool = availableTools.tool(named: functionName) else {
            return nil
        }

        guard let data = argumentsJSON.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let arguments = jsonDict.mapValues { JSONValue.from($0) }

        return ToolCall(
            id: id,
            toolName: functionName,
            connectorID: tool.connectorID,
            originalToolName: tool.originalName,
            arguments: arguments
        )
    }

    /// Parse Anthropic tool use block
    static func parseAnthropicToolUse(
        id: String,
        name: String,
        input: [String: Any],
        availableTools: [ConnectorTool]
    ) -> ToolCall? {
        guard let tool = availableTools.tool(named: name) else {
            return nil
        }

        let arguments = input.mapValues { JSONValue.from($0) }

        return ToolCall(
            id: id,
            toolName: name,
            connectorID: tool.connectorID,
            originalToolName: tool.originalName,
            arguments: arguments
        )
    }

    /// Parse Gemini function call
    static func parseGeminiFunctionCall(
        name: String,
        args: [String: Any],
        availableTools: [ConnectorTool]
    ) -> ToolCall? {
        guard let tool = availableTools.tool(named: name) else {
            return nil
        }

        let arguments = args.mapValues { JSONValue.from($0) }

        return ToolCall(
            id: UUID().uuidString,  // Gemini doesn't provide call IDs
            toolName: name,
            connectorID: tool.connectorID,
            originalToolName: tool.originalName,
            arguments: arguments
        )
    }
}

// MARK: - Tool Result Formatting

extension ToolSchemaConverter {

    /// Format tool result for OpenAI (also used by Ollama which uses OpenAI-compatible API)
    static func formatOpenAIToolResult(callID: String, result: ToolResult) -> [String: Any] {
        [
            "tool_call_id": callID,
            "role": "tool",
            "content": result.content?.contentForLLM ?? (result.error?.message ?? "No result")
        ]
    }
}
