// MARK: - Tool Schema Converter Tests
// Tests for provider-specific tool schema conversion

import Foundation

// MARK: - Test Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentSuite = ""

    static func suite(_ name: String) {
        currentSuite = name
        print("\n📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got '\(value!)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        if !condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected false but got true"))
            print("  ✗ \(testName): Expected false but got true")
        }
    }

    static func printSummary() {
        print("\n==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - JSONValue (Inline)

enum JSONValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    var asAny: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.asAny }
        case .object(let obj): return obj.mapValues { $0.asAny }
        }
    }

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let b as Bool: return .bool(b)
        case let arr as [Any]: return .array(arr.map { from($0) })
        case let dict as [String: Any]: return .object(dict.mapValues { from($0) })
        case is NSNull: return .null
        default: return .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if container.decodeNil() { self = .null }
        else if let arr = try? container.decode([JSONValue].self) { self = .array(arr) }
        else if let obj = try? container.decode([String: JSONValue].self) { self = .object(obj) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }
}

// MARK: - JSONSchema (Inline)

struct JSONSchema: Codable, Equatable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let description: String?
    let title: String?
    let `default`: JSONValue?
    let `enum`: [String]?

    init(
        type: String = "object",
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        description: String? = nil,
        title: String? = nil,
        default defaultValue: JSONValue? = nil,
        enum enumValues: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.description = description
        self.title = title
        self.default = defaultValue
        self.enum = enumValues
    }

    static let emptyObject = JSONSchema(type: "object", properties: [:], required: [])
}

struct JSONSchemaProperty: Codable, Equatable {
    let type: String?
    let description: String?
    let `enum`: [String]?
    let items: JSONSchema?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let `default`: JSONValue?
    let minimum: Double?
    let maximum: Double?
    let minLength: Int?
    let maxLength: Int?
    let pattern: String?

    init(
        type: String? = nil,
        description: String? = nil,
        enum enumValues: [String]? = nil,
        items: JSONSchema? = nil,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        default defaultValue: JSONValue? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil
    ) {
        self.type = type
        self.description = description
        self.enum = enumValues
        self.items = items
        self.properties = properties
        self.required = required
        self.default = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
    }

    static func string(description: String? = nil, enum enumValues: [String]? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "string", description: description, enum: enumValues)
    }

    static func integer(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "integer", description: description, minimum: minimum, maximum: maximum)
    }

    static func number(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "number", description: description, minimum: minimum, maximum: maximum)
    }

    static func boolean(description: String? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "boolean", description: description)
    }

    static func array(description: String? = nil, items: JSONSchema) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "array", description: description, items: items)
    }

    static func object(description: String? = nil, properties: [String: JSONSchemaProperty], required: [String]? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "object", description: description, properties: properties, required: required)
    }
}

// MARK: - ConnectorTool (Inline)

struct ConnectorTool: Identifiable, Equatable, Sendable {
    let originalName: String
    let description: String?
    let inputSchema: JSONSchema
    let connectorID: String
    let connectorName: String

    var id: String { "\(connectorID):\(originalName)" }

    var name: String {
        let prefix = connectorName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return "\(prefix)_\(originalName)"
    }
}

extension Array where Element == ConnectorTool {
    func tool(named name: String) -> ConnectorTool? {
        first { $0.name == name }
    }
}

// MARK: - ToolCall (Inline)

struct ToolCall: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let toolName: String
    let connectorID: String
    let originalToolName: String
    let arguments: [String: JSONValue]
    let requestedAt: Date

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

    var argumentsAsAny: [String: Any] {
        arguments.mapValues { $0.asAny }
    }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id && lhs.toolName == rhs.toolName && lhs.connectorID == rhs.connectorID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ToolError, ToolContent, ToolOutcome, ToolResult (Inline)

struct ToolError: Equatable, Error, Sendable {
    let message: String
    let code: Int?
    let isRetryable: Bool

    init(message: String, code: Int? = nil, isRetryable: Bool = false) {
        self.message = message
        self.code = code
        self.isRetryable = isRetryable
    }
}

struct ToolContent: Equatable, Sendable {
    let text: String?
    let json: Data?
    let imageData: Data?
    let imageMimeType: String?

    init(text: String? = nil, json: Data? = nil, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.text = text
        self.json = json
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }

    var contentForLLM: String {
        if let text = text { return text }
        if let json = json, let jsonString = String(data: json, encoding: .utf8) {
            return jsonString
        }
        if imageData != nil { return "[Image content - see attached image]" }
        return ""
    }

    static func text(_ text: String) -> ToolContent {
        ToolContent(text: text)
    }
}

enum ToolOutcome: Sendable, Equatable {
    case success(ToolContent)
    case error(ToolError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

struct ToolResult: Identifiable, Sendable {
    let callID: String
    let toolName: String
    let outcome: ToolOutcome
    let duration: TimeInterval
    let completedAt: Date

    var id: String { callID }

    init(callID: String, toolName: String, outcome: ToolOutcome, duration: TimeInterval, completedAt: Date = Date()) {
        self.callID = callID
        self.toolName = toolName
        self.outcome = outcome
        self.duration = duration
        self.completedAt = completedAt
    }

    var content: ToolContent? {
        if case .success(let content) = outcome { return content }
        return nil
    }

    var error: ToolError? {
        if case .error(let error) = outcome { return error }
        return nil
    }

    static func success(callID: String, toolName: String, content: ToolContent, duration: TimeInterval) -> ToolResult {
        ToolResult(callID: callID, toolName: toolName, outcome: .success(content), duration: duration)
    }

    static func failure(callID: String, toolName: String, error: ToolError, duration: TimeInterval) -> ToolResult {
        ToolResult(callID: callID, toolName: toolName, outcome: .error(error), duration: duration)
    }
}

// MARK: - ToolSchemaConverter (Inline - Copy of real implementation)

enum ToolSchemaConverter {

    // MARK: - OpenAI Format

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

    static func toAnthropic(tools: [ConnectorTool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description ?? "No description available",
                "input_schema": toAnthropicInputSchema(tool.inputSchema)
            ]
        }
    }

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

    static func toOpenAIJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toOpenAI(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }

    static func toAnthropicJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toAnthropic(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }

    static func toGeminiJSON(tools: [ConnectorTool]) throws -> Data {
        let toolDicts = toGemini(tools: tools)
        return try JSONSerialization.data(withJSONObject: toolDicts, options: [])
    }

    // MARK: - Tool Call Parsing

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

    // MARK: - Tool Result Formatting

    static func formatOpenAIToolResult(callID: String, result: ToolResult) -> [String: Any] {
        [
            "tool_call_id": callID,
            "role": "tool",
            "content": result.content?.contentForLLM ?? (result.error?.message ?? "No result")
        ]
    }
}

// MARK: - Test Helpers

func createTestTool(
    name: String = "search",
    description: String? = "Search for items",
    connectorID: String = "test-connector",
    connectorName: String = "Test",
    properties: [String: JSONSchemaProperty] = [:],
    required: [String] = []
) -> ConnectorTool {
    ConnectorTool(
        originalName: name,
        description: description,
        inputSchema: JSONSchema(
            type: "object",
            properties: properties,
            required: required
        ),
        connectorID: connectorID,
        connectorName: connectorName
    )
}

// MARK: - Tests

func testOpenAIConversion() {
    TestRunner.suite("OpenAI Format Conversion")

    // Test basic tool conversion
    let tool = createTestTool(
        name: "search",
        description: "Search for items",
        connectorName: "GitHub",
        properties: [
            "query": .string(description: "Search query"),
            "limit": .integer(description: "Max results", minimum: 1, maximum: 100)
        ],
        required: ["query"]
    )

    let openAITools = ToolSchemaConverter.toOpenAI(tools: [tool])

    // Verify structure
    TestRunner.assertEqual(openAITools.count, 1, "One tool converted")

    let toolDict = openAITools[0]
    TestRunner.assertEqual(toolDict["type"] as? String, "function", "Type is function")

    let function = toolDict["function"] as? [String: Any]
    TestRunner.assertNotNil(function, "Function exists")
    TestRunner.assertEqual(function?["name"] as? String, "github_search", "Name is prefixed")
    TestRunner.assertEqual(function?["description"] as? String, "Search for items", "Description preserved")

    let params = function?["parameters"] as? [String: Any]
    TestRunner.assertNotNil(params, "Parameters exist")
    TestRunner.assertEqual(params?["type"] as? String, "object", "Parameters type is object")

    let props = params?["properties"] as? [String: Any]
    TestRunner.assertNotNil(props, "Properties exist")
    TestRunner.assertTrue(props?["query"] != nil, "Query property exists")
    TestRunner.assertTrue(props?["limit"] != nil, "Limit property exists")

    let required = params?["required"] as? [String]
    TestRunner.assertEqual(required, ["query"], "Required fields preserved")

    // Test property details
    let queryProp = props?["query"] as? [String: Any]
    TestRunner.assertEqual(queryProp?["type"] as? String, "string", "Query type is string")
    TestRunner.assertEqual(queryProp?["description"] as? String, "Search query", "Query description preserved")
}

func testAnthropicConversion() {
    TestRunner.suite("Anthropic Format Conversion")

    let tool = createTestTool(
        name: "create_issue",
        description: "Create a new issue",
        connectorName: "JIRA",
        properties: [
            "title": .string(description: "Issue title"),
            "priority": .string(description: "Priority level", enum: ["low", "medium", "high"])
        ],
        required: ["title"]
    )

    let anthropicTools = ToolSchemaConverter.toAnthropic(tools: [tool])

    TestRunner.assertEqual(anthropicTools.count, 1, "One tool converted")

    let toolDict = anthropicTools[0]
    TestRunner.assertEqual(toolDict["name"] as? String, "jira_create_issue", "Name is prefixed")
    TestRunner.assertEqual(toolDict["description"] as? String, "Create a new issue", "Description preserved")

    let inputSchema = toolDict["input_schema"] as? [String: Any]
    TestRunner.assertNotNil(inputSchema, "Input schema exists")
    TestRunner.assertEqual(inputSchema?["type"] as? String, "object", "Schema type is object")

    let props = inputSchema?["properties"] as? [String: Any]
    TestRunner.assertNotNil(props, "Properties exist")

    let priorityProp = props?["priority"] as? [String: Any]
    TestRunner.assertNotNil(priorityProp, "Priority property exists")
    let enumValues = priorityProp?["enum"] as? [String]
    TestRunner.assertEqual(enumValues, ["low", "medium", "high"], "Enum values preserved")
}

func testGeminiConversion() {
    TestRunner.suite("Gemini Format Conversion")

    let tool = createTestTool(
        name: "fetch",
        description: "Fetch a URL",
        connectorName: "Web",
        properties: [
            "url": .string(description: "URL to fetch"),
            "timeout": .number(description: "Timeout in seconds")
        ],
        required: ["url"]
    )

    let geminiTools = ToolSchemaConverter.toGemini(tools: [tool])

    // Gemini wraps tools in function_declarations array
    TestRunner.assertEqual(geminiTools.count, 1, "One wrapper object")

    let wrapper = geminiTools[0]
    let declarations = wrapper["function_declarations"] as? [[String: Any]]
    TestRunner.assertNotNil(declarations, "Function declarations exist")
    TestRunner.assertEqual(declarations?.count, 1, "One function declaration")

    let funcDecl = declarations?[0]
    TestRunner.assertEqual(funcDecl?["name"] as? String, "web_fetch", "Name is prefixed")
    TestRunner.assertEqual(funcDecl?["description"] as? String, "Fetch a URL", "Description preserved")

    let params = funcDecl?["parameters"] as? [String: Any]
    TestRunner.assertNotNil(params, "Parameters exist")
    TestRunner.assertEqual(params?["type"] as? String, "OBJECT", "Type is UPPERCASE")

    let props = params?["properties"] as? [String: Any]
    let urlProp = props?["url"] as? [String: Any]
    TestRunner.assertEqual(urlProp?["type"] as? String, "STRING", "Property type is UPPERCASE")
}

func testNestedObjectConversion() {
    TestRunner.suite("Nested Object Conversion")

    let tool = createTestTool(
        name: "create",
        description: "Create an entity",
        connectorName: "DB",
        properties: [
            "data": .object(
                description: "Entity data",
                properties: [
                    "name": .string(description: "Entity name"),
                    "config": .object(
                        description: "Configuration",
                        properties: [
                            "enabled": .boolean(description: "Is enabled")
                        ],
                        required: ["enabled"]
                    )
                ],
                required: ["name"]
            )
        ],
        required: ["data"]
    )

    // Test OpenAI nested
    let openAITools = ToolSchemaConverter.toOpenAI(tools: [tool])
    let params = (openAITools[0]["function"] as? [String: Any])?["parameters"] as? [String: Any]
    let props = params?["properties"] as? [String: Any]
    let dataProp = props?["data"] as? [String: Any]

    TestRunner.assertEqual(dataProp?["type"] as? String, "object", "Data is object type")
    TestRunner.assertNotNil(dataProp?["properties"], "Data has nested properties")

    let nestedProps = dataProp?["properties"] as? [String: Any]
    TestRunner.assertNotNil(nestedProps?["name"], "Nested name exists")
    TestRunner.assertNotNil(nestedProps?["config"], "Nested config exists")

    let configProp = nestedProps?["config"] as? [String: Any]
    TestRunner.assertEqual(configProp?["type"] as? String, "object", "Config is object")

    let configRequired = configProp?["required"] as? [String]
    TestRunner.assertEqual(configRequired, ["enabled"], "Nested required preserved")
}

func testArrayPropertyConversion() {
    TestRunner.suite("Array Property Conversion")

    let tool = createTestTool(
        name: "batch",
        description: "Process items in batch",
        connectorName: "Batch",
        properties: [
            "items": .array(
                description: "Items to process",
                items: JSONSchema(
                    type: "object",
                    properties: [
                        "id": JSONSchemaProperty(type: "string"),
                        "value": JSONSchemaProperty(type: "number")
                    ],
                    required: ["id"]
                )
            )
        ],
        required: ["items"]
    )

    let openAITools = ToolSchemaConverter.toOpenAI(tools: [tool])
    let params = (openAITools[0]["function"] as? [String: Any])?["parameters"] as? [String: Any]
    let props = params?["properties"] as? [String: Any]
    let itemsProp = props?["items"] as? [String: Any]

    TestRunner.assertEqual(itemsProp?["type"] as? String, "array", "Items is array type")

    let items = itemsProp?["items"] as? [String: Any]
    TestRunner.assertNotNil(items, "Array items schema exists")
    TestRunner.assertEqual(items?["type"] as? String, "object", "Items type is object")

    let itemsProps = items?["properties"] as? [String: Any]
    TestRunner.assertNotNil(itemsProps?["id"], "Items has id property")
    TestRunner.assertNotNil(itemsProps?["value"], "Items has value property")
}

func testNoDescriptionTool() {
    TestRunner.suite("Tool Without Description")

    let tool = ConnectorTool(
        originalName: "ping",
        description: nil,
        inputSchema: JSONSchema.emptyObject,
        connectorID: "test",
        connectorName: "Test"
    )

    let openAITools = ToolSchemaConverter.toOpenAI(tools: [tool])
    let function = openAITools[0]["function"] as? [String: Any]
    TestRunner.assertEqual(
        function?["description"] as? String,
        "No description available",
        "Default description used"
    )

    let anthropicTools = ToolSchemaConverter.toAnthropic(tools: [tool])
    TestRunner.assertEqual(
        anthropicTools[0]["description"] as? String,
        "No description available",
        "Anthropic default description"
    )
}

func testMultipleToolsConversion() {
    TestRunner.suite("Multiple Tools Conversion")

    let tools = [
        createTestTool(name: "search", connectorName: "GitHub"),
        createTestTool(name: "create", connectorName: "JIRA"),
        createTestTool(name: "send", connectorName: "Slack")
    ]

    let openAITools = ToolSchemaConverter.toOpenAI(tools: tools)
    TestRunner.assertEqual(openAITools.count, 3, "Three OpenAI tools")

    let names = openAITools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
    TestRunner.assertTrue(names.contains("github_search"), "GitHub tool present")
    TestRunner.assertTrue(names.contains("jira_create"), "JIRA tool present")
    TestRunner.assertTrue(names.contains("slack_send"), "Slack tool present")

    let anthropicTools = ToolSchemaConverter.toAnthropic(tools: tools)
    TestRunner.assertEqual(anthropicTools.count, 3, "Three Anthropic tools")

    let geminiTools = ToolSchemaConverter.toGemini(tools: tools)
    let declarations = geminiTools[0]["function_declarations"] as? [[String: Any]]
    TestRunner.assertEqual(declarations?.count, 3, "Three Gemini declarations")
}

func testJSONSerialization() {
    TestRunner.suite("JSON Serialization")

    let tool = createTestTool(
        name: "test",
        description: "Test tool",
        connectorName: "Test",
        properties: [
            "input": .string(description: "Input value")
        ],
        required: ["input"]
    )

    // Test OpenAI JSON
    do {
        let data = try ToolSchemaConverter.toOpenAIJSON(tools: [tool])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        TestRunner.assertNotNil(parsed, "OpenAI JSON parses back")
        TestRunner.assertEqual(parsed?.count, 1, "One tool in parsed JSON")
    } catch {
        TestRunner.assertTrue(false, "OpenAI JSON serialization failed: \(error)")
    }

    // Test Anthropic JSON
    do {
        let data = try ToolSchemaConverter.toAnthropicJSON(tools: [tool])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        TestRunner.assertNotNil(parsed, "Anthropic JSON parses back")
    } catch {
        TestRunner.assertTrue(false, "Anthropic JSON serialization failed: \(error)")
    }

    // Test Gemini JSON
    do {
        let data = try ToolSchemaConverter.toGeminiJSON(tools: [tool])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        TestRunner.assertNotNil(parsed, "Gemini JSON parses back")
    } catch {
        TestRunner.assertTrue(false, "Gemini JSON serialization failed: \(error)")
    }
}

func testOpenAIToolCallParsing() {
    TestRunner.suite("OpenAI Tool Call Parsing")

    let tools = [
        createTestTool(name: "search", connectorName: "GitHub"),
        createTestTool(name: "create_issue", connectorName: "JIRA")
    ]

    // Valid tool call
    let validJSON = "{\"query\": \"swift concurrency\", \"limit\": 10}"
    let validCall = ToolSchemaConverter.parseOpenAIToolCall(
        id: "call_123",
        functionName: "github_search",
        argumentsJSON: validJSON,
        availableTools: tools
    )

    TestRunner.assertNotNil(validCall, "Valid call parsed")
    TestRunner.assertEqual(validCall?.id, "call_123", "Call ID preserved")
    TestRunner.assertEqual(validCall?.toolName, "github_search", "Tool name preserved")
    TestRunner.assertEqual(validCall?.connectorID, "test-connector", "Connector ID resolved")
    TestRunner.assertEqual(validCall?.originalToolName, "search", "Original name resolved")

    let queryArg = validCall?.arguments["query"]
    if case .string(let q) = queryArg {
        TestRunner.assertEqual(q, "swift concurrency", "Query argument parsed")
    } else {
        TestRunner.assertTrue(false, "Query argument type incorrect")
    }

    // Unknown tool
    let unknownCall = ToolSchemaConverter.parseOpenAIToolCall(
        id: "call_456",
        functionName: "unknown_tool",
        argumentsJSON: "{}",
        availableTools: tools
    )
    TestRunner.assertNil(unknownCall, "Unknown tool returns nil")

    // Invalid JSON
    let invalidCall = ToolSchemaConverter.parseOpenAIToolCall(
        id: "call_789",
        functionName: "github_search",
        argumentsJSON: "not json",
        availableTools: tools
    )
    TestRunner.assertNil(invalidCall, "Invalid JSON returns nil")

    // Empty arguments
    let emptyArgsCall = ToolSchemaConverter.parseOpenAIToolCall(
        id: "call_empty",
        functionName: "github_search",
        argumentsJSON: "{}",
        availableTools: tools
    )
    TestRunner.assertNotNil(emptyArgsCall, "Empty args call parsed")
    TestRunner.assertTrue(emptyArgsCall?.arguments.isEmpty ?? false, "Arguments are empty")
}

func testAnthropicToolUseParsing() {
    TestRunner.suite("Anthropic Tool Use Parsing")

    let tools = [
        createTestTool(name: "send_message", connectorName: "Slack")
    ]

    // Valid tool use
    let input: [String: Any] = [
        "channel": "#general",
        "message": "Hello world",
        "thread_ts": "1234567890.123456"
    ]

    let validCall = ToolSchemaConverter.parseAnthropicToolUse(
        id: "toolu_abc123",
        name: "slack_send_message",
        input: input,
        availableTools: tools
    )

    TestRunner.assertNotNil(validCall, "Valid call parsed")
    TestRunner.assertEqual(validCall?.id, "toolu_abc123", "Call ID preserved")
    TestRunner.assertEqual(validCall?.toolName, "slack_send_message", "Tool name preserved")
    TestRunner.assertEqual(validCall?.originalToolName, "send_message", "Original name resolved")

    let channelArg = validCall?.arguments["channel"]
    if case .string(let ch) = channelArg {
        TestRunner.assertEqual(ch, "#general", "Channel argument parsed")
    } else {
        TestRunner.assertTrue(false, "Channel argument type incorrect")
    }

    // Unknown tool
    let unknownCall = ToolSchemaConverter.parseAnthropicToolUse(
        id: "toolu_xyz",
        name: "unknown_tool",
        input: [:],
        availableTools: tools
    )
    TestRunner.assertNil(unknownCall, "Unknown tool returns nil")
}

func testGeminiFunctionCallParsing() {
    TestRunner.suite("Gemini Function Call Parsing")

    let tools = [
        createTestTool(name: "fetch_url", connectorName: "Web")
    ]

    let args: [String: Any] = [
        "url": "https://example.com",
        "headers": ["Authorization": "Bearer token"]
    ]

    let validCall = ToolSchemaConverter.parseGeminiFunctionCall(
        name: "web_fetch_url",
        args: args,
        availableTools: tools
    )

    TestRunner.assertNotNil(validCall, "Valid call parsed")
    TestRunner.assertFalse(validCall?.id.isEmpty ?? true, "UUID generated for call ID")
    TestRunner.assertEqual(validCall?.toolName, "web_fetch_url", "Tool name preserved")
    TestRunner.assertEqual(validCall?.originalToolName, "fetch_url", "Original name resolved")

    let urlArg = validCall?.arguments["url"]
    if case .string(let url) = urlArg {
        TestRunner.assertEqual(url, "https://example.com", "URL argument parsed")
    } else {
        TestRunner.assertTrue(false, "URL argument type incorrect")
    }

    // Nested object argument
    let headersArg = validCall?.arguments["headers"]
    if case .object(let headers) = headersArg {
        TestRunner.assertNotNil(headers["Authorization"], "Nested headers parsed")
    } else {
        TestRunner.assertTrue(false, "Headers argument type incorrect")
    }

    // Unknown tool
    let unknownCall = ToolSchemaConverter.parseGeminiFunctionCall(
        name: "unknown",
        args: [:],
        availableTools: tools
    )
    TestRunner.assertNil(unknownCall, "Unknown tool returns nil")
}

func testToolResultFormatting() {
    TestRunner.suite("Tool Result Formatting")

    // Success result
    let successResult = ToolResult.success(
        callID: "call_123",
        toolName: "search",
        content: ToolContent.text("Found 5 results"),
        duration: 0.5
    )

    let successFormatted = ToolSchemaConverter.formatOpenAIToolResult(
        callID: "call_123",
        result: successResult
    )

    TestRunner.assertEqual(successFormatted["tool_call_id"] as? String, "call_123", "Call ID in result")
    TestRunner.assertEqual(successFormatted["role"] as? String, "tool", "Role is tool")
    TestRunner.assertEqual(successFormatted["content"] as? String, "Found 5 results", "Content preserved")

    // Error result
    let errorResult = ToolResult.failure(
        callID: "call_456",
        toolName: "fetch",
        error: ToolError(message: "Connection timeout"),
        duration: 30.0
    )

    let errorFormatted = ToolSchemaConverter.formatOpenAIToolResult(
        callID: "call_456",
        result: errorResult
    )

    TestRunner.assertEqual(errorFormatted["content"] as? String, "Connection timeout", "Error message in content")
}

func testEmptyToolsList() {
    TestRunner.suite("Empty Tools List")

    let emptyTools: [ConnectorTool] = []

    let openAI = ToolSchemaConverter.toOpenAI(tools: emptyTools)
    TestRunner.assertTrue(openAI.isEmpty, "OpenAI empty for no tools")

    let anthropic = ToolSchemaConverter.toAnthropic(tools: emptyTools)
    TestRunner.assertTrue(anthropic.isEmpty, "Anthropic empty for no tools")

    let gemini = ToolSchemaConverter.toGemini(tools: emptyTools)
    let declarations = gemini[0]["function_declarations"] as? [[String: Any]]
    TestRunner.assertTrue(declarations?.isEmpty ?? false, "Gemini declarations empty for no tools")
}

func testSpecialCharactersInNames() {
    TestRunner.suite("Special Characters in Names")

    // Connector name with special characters
    let tool = ConnectorTool(
        originalName: "search-items",
        description: "Search for items",
        inputSchema: JSONSchema.emptyObject,
        connectorID: "my-connector",
        connectorName: "My Connector - Test"
    )

    // Name should be sanitized (spaces and dashes become underscores)
    // "My Connector - Test" → "my_connector___test" (space, dash, space → ___)
    TestRunner.assertEqual(tool.name, "my_connector___test_search-items", "Name sanitized")

    let openAI = ToolSchemaConverter.toOpenAI(tools: [tool])
    let name = (openAI[0]["function"] as? [String: Any])?["name"] as? String
    TestRunner.assertTrue(name?.contains("my_connector") ?? false, "Connector prefix in name")
}

// MARK: - Main

@main
struct ToolSchemaConverterTestsMain {
    static func main() {
        print("🧪 Tool Schema Converter Tests")
        print("==================================================")

        testOpenAIConversion()
        testAnthropicConversion()
        testGeminiConversion()
        testNestedObjectConversion()
        testArrayPropertyConversion()
        testNoDescriptionTool()
        testMultipleToolsConversion()
        testJSONSerialization()
        testOpenAIToolCallParsing()
        testAnthropicToolUseParsing()
        testGeminiFunctionCallParsing()
        testToolResultFormatting()
        testEmptyToolsList()
        testSpecialCharactersInNames()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
