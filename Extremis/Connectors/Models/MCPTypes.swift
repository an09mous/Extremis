// MARK: - MCP Protocol Types
// Model Context Protocol message types (JSON-RPC 2.0 based)
// Implemented directly since MCP Swift SDK requires Swift 6.0+ and project uses Swift 5.9

import Foundation

// MARK: - JSON-RPC Base Types

/// JSON-RPC 2.0 request message
struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId
    let method: String
    let params: JSONValue?

    init(id: JSONRPCId, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response message
struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId
    let result: JSONValue?
    let error: JSONRPCError?
}

/// JSON-RPC 2.0 notification (request without id)
struct JSONRPCNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: JSONValue?

    init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// JSON-RPC error object
struct JSONRPCError: Codable, Error {
    let code: Int
    let message: String
    let data: JSONValue?
}

/// JSON-RPC ID can be string, number, or null
enum JSONRPCId: Codable, Hashable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(intValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        }
    }
}

// MARK: - JSON Value Type

/// Generic JSON value for dynamic content
indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Convert to native Swift dictionary/array
    var asAny: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.asAny }
        case .object(let v): return v.mapValues { $0.asAny }
        }
    }

    /// Create JSONValue from Any
    /// Note: Order matters - we check numeric types via NSNumber carefully
    /// to distinguish between booleans and numbers (JSON parsers often use NSNumber for both)
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        case let number as NSNumber:
            // NSNumber can represent bool, int, or double
            // CFBooleanGetTypeID() identifies actual booleans vs numeric 0/1
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            } else if number.doubleValue == Double(number.intValue) {
                // It's an integer (no fractional part)
                return .int(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        default:
            return .null
        }
    }
}

// MARK: - MCP Protocol Messages

/// MCP initialization request parameters
struct MCPInitializeParams: Codable {
    let protocolVersion: String
    let capabilities: MCPClientCapabilities
    let clientInfo: MCPClientInfo

    init(protocolVersion: String = "2024-11-05", clientInfo: MCPClientInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = MCPClientCapabilities()
        self.clientInfo = clientInfo
    }
}

/// MCP client capabilities
struct MCPClientCapabilities: Codable {
    let roots: MCPRootsCapability?
    let sampling: JSONValue?

    init(roots: MCPRootsCapability? = nil, sampling: JSONValue? = nil) {
        self.roots = roots
        self.sampling = sampling
    }
}

/// MCP roots capability
struct MCPRootsCapability: Codable {
    let listChanged: Bool?
}

/// MCP client info
struct MCPClientInfo: Codable {
    let name: String
    let version: String
}

/// MCP initialization result
struct MCPInitializeResult: Codable {
    let protocolVersion: String
    let capabilities: MCPServerCapabilities
    let serverInfo: MCPServerInfo?
}

/// MCP server capabilities
struct MCPServerCapabilities: Codable {
    let tools: MCPToolsCapability?
    let resources: MCPResourcesCapability?
    let prompts: MCPPromptsCapability?
    let logging: JSONValue?
}

/// MCP tools capability
struct MCPToolsCapability: Codable {
    let listChanged: Bool?
}

/// MCP resources capability
struct MCPResourcesCapability: Codable {
    let subscribe: Bool?
    let listChanged: Bool?
}

/// MCP prompts capability
struct MCPPromptsCapability: Codable {
    let listChanged: Bool?
}

/// MCP server info
struct MCPServerInfo: Codable {
    let name: String
    let version: String?
}

// MARK: - MCP Tool Types

/// MCP tool definition
struct MCPTool: Codable {
    let name: String
    let description: String?
    let inputSchema: MCPInputSchema
}

/// MCP input schema (JSON Schema subset)
struct MCPInputSchema: Codable {
    let type: String
    let properties: [String: MCPSchemaProperty]?
    let required: [String]?
    let description: String?

    init(type: String = "object", properties: [String: MCPSchemaProperty]? = nil, required: [String]? = nil, description: String? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
        self.description = description
    }
}

/// MCP schema property
struct MCPSchemaProperty: Codable {
    let type: String?
    let description: String?
    let `enum`: [String]?
    let items: MCPInputSchema?
    let properties: [String: MCPSchemaProperty]?
    let required: [String]?
}

/// MCP tools list result
struct MCPToolsListResult: Codable {
    let tools: [MCPTool]
}

/// MCP tool call request parameters
struct MCPToolCallParams: Codable {
    let name: String
    let arguments: [String: JSONValue]?
}

/// MCP tool call result
struct MCPToolCallResult: Codable {
    let content: [MCPContent]
    let isError: Bool?
}

// MARK: - MCP Content Types

/// MCP content (text, image, or resource)
enum MCPContent: Codable {
    case text(MCPTextContent)
    case image(MCPImageContent)
    case resource(MCPEmbeddedResourceContent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try MCPTextContent(from: decoder))
        case "image":
            self = .image(try MCPImageContent(from: decoder))
        case "resource":
            self = .resource(try MCPEmbeddedResourceContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        }
    }
}

/// MCP text content
struct MCPTextContent: Codable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

/// MCP image content
struct MCPImageContent: Codable {
    let type: String
    let data: String  // base64 encoded
    let mimeType: String

    init(data: String, mimeType: String) {
        self.type = "image"
        self.data = data
        self.mimeType = mimeType
    }
}

/// MCP embedded resource content
struct MCPEmbeddedResourceContent: Codable {
    let type: String
    let resource: MCPResourceContents

    init(resource: MCPResourceContents) {
        self.type = "resource"
        self.resource = resource
    }
}

/// MCP resource contents
struct MCPResourceContents: Codable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?  // base64 encoded
}

// MARK: - MCP Method Names

/// Standard MCP method names
enum MCPMethod {
    static let initialize = "initialize"
    static let initialized = "notifications/initialized"
    static let ping = "ping"
    static let toolsList = "tools/list"
    static let toolsCall = "tools/call"
    static let resourcesList = "resources/list"
    static let resourcesRead = "resources/read"
    static let promptsList = "prompts/list"
    static let promptsGet = "prompts/get"
}

// MARK: - MCP Error Codes

/// Standard JSON-RPC and MCP error codes
enum MCPErrorCode {
    // JSON-RPC standard errors
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603

    // MCP-specific errors
    static let connectionClosed = -1
    static let requestTimeout = -2
}
