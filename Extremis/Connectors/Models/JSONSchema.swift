// MARK: - JSON Schema Types
// JSON Schema representation for tool input/output schemas

import Foundation

/// Simplified JSON Schema representation for tool parameters
struct JSONSchema: Codable, Equatable, Sendable {
    /// Schema type (typically "object" for tool inputs)
    let type: String

    /// Property definitions
    let properties: [String: JSONSchemaProperty]?

    /// Required property names
    let required: [String]?

    /// Description of the schema
    let description: String?

    // MARK: - Additional Schema Fields

    /// Title of the schema
    let title: String?

    /// Default value
    let `default`: JSONValue?

    /// Enum values for string types
    let `enum`: [String]?

    // MARK: - Initialization

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

    // MARK: - Factory Methods

    /// Create an empty object schema (no required properties)
    static let emptyObject = JSONSchema(type: "object", properties: [:], required: [])

    /// Create a schema from MCP input schema
    static func from(mcpSchema: MCPInputSchema) -> JSONSchema {
        JSONSchema(
            type: mcpSchema.type,
            properties: mcpSchema.properties?.mapValues { JSONSchemaProperty.from(mcpProperty: $0) },
            required: mcpSchema.required,
            description: mcpSchema.description
        )
    }
}

/// JSON Schema property definition
struct JSONSchemaProperty: Codable, Equatable, Sendable {
    /// Property type
    let type: String?

    /// Property description
    let description: String?

    /// Enum values for string types
    let `enum`: [String]?

    /// Items schema for array types
    let items: JSONSchema?

    /// Nested properties for object types
    let properties: [String: JSONSchemaProperty]?

    /// Required nested properties
    let required: [String]?

    /// Default value
    let `default`: JSONValue?

    /// Minimum value for numbers
    let minimum: Double?

    /// Maximum value for numbers
    let maximum: Double?

    /// Minimum length for strings
    let minLength: Int?

    /// Maximum length for strings
    let maxLength: Int?

    /// Pattern for string validation
    let pattern: String?

    // MARK: - Initialization

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

    // MARK: - Factory Methods

    /// Create a string property
    static func string(description: String? = nil, enum enumValues: [String]? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "string", description: description, enum: enumValues)
    }

    /// Create an integer property
    static func integer(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "integer", description: description, minimum: minimum, maximum: maximum)
    }

    /// Create a number property
    static func number(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "number", description: description, minimum: minimum, maximum: maximum)
    }

    /// Create a boolean property
    static func boolean(description: String? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "boolean", description: description)
    }

    /// Create an array property
    static func array(description: String? = nil, items: JSONSchema) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "array", description: description, items: items)
    }

    /// Create an object property
    static func object(description: String? = nil, properties: [String: JSONSchemaProperty], required: [String]? = nil) -> JSONSchemaProperty {
        JSONSchemaProperty(type: "object", description: description, properties: properties, required: required)
    }

    /// Create from MCP schema property
    static func from(mcpProperty: MCPSchemaProperty) -> JSONSchemaProperty {
        JSONSchemaProperty(
            type: mcpProperty.type,
            description: mcpProperty.description,
            enum: mcpProperty.enum,
            items: mcpProperty.items.map { JSONSchema.from(mcpSchema: $0) },
            properties: mcpProperty.properties?.mapValues { from(mcpProperty: $0) },
            required: mcpProperty.required
        )
    }
}

// MARK: - Codable Customization

extension JSONSchemaProperty {
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case `enum`
        case items
        case properties
        case required
        case `default`
        case minimum
        case maximum
        case minLength
        case maxLength
        case pattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decodeIfPresent(String.self, forKey: .type)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        `enum` = try container.decodeIfPresent([String].self, forKey: .enum)
        items = try container.decodeIfPresent(JSONSchema.self, forKey: .items)
        properties = try container.decodeIfPresent([String: JSONSchemaProperty].self, forKey: .properties)
        required = try container.decodeIfPresent([String].self, forKey: .required)
        `default` = try container.decodeIfPresent(JSONValue.self, forKey: .default)
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(`enum`, forKey: .enum)
        try container.encodeIfPresent(items, forKey: .items)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(`default`, forKey: .default)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
        try container.encodeIfPresent(minLength, forKey: .minLength)
        try container.encodeIfPresent(maxLength, forKey: .maxLength)
        try container.encodeIfPresent(pattern, forKey: .pattern)
    }
}
