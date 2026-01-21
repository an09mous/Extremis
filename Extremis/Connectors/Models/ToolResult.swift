// MARK: - Tool Result
// Result of a tool execution

import Foundation

/// Result of a tool execution
struct ToolResult: Identifiable, Sendable {
    /// Matches the call ID
    let callID: String

    /// Tool that was executed (disambiguated name)
    let toolName: String

    /// Execution outcome
    let outcome: ToolOutcome

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
        outcome: ToolOutcome,
        duration: TimeInterval,
        completedAt: Date = Date()
    ) {
        self.callID = callID
        self.toolName = toolName
        self.outcome = outcome
        self.duration = duration
        self.completedAt = completedAt
    }

    // MARK: - Convenience

    /// Whether execution succeeded
    var isSuccess: Bool {
        outcome.isSuccess
    }

    /// Whether execution failed
    var isError: Bool {
        outcome.isError
    }

    /// Get the error if execution failed
    var error: ToolError? {
        if case .error(let error) = outcome {
            return error
        }
        return nil
    }

    /// Get the content if execution succeeded
    var content: ToolContent? {
        if case .success(let content) = outcome {
            return content
        }
        return nil
    }

    // MARK: - Factory Methods

    /// Create a successful result
    static func success(
        callID: String,
        toolName: String,
        content: ToolContent,
        duration: TimeInterval
    ) -> ToolResult {
        ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .success(content),
            duration: duration
        )
    }

    /// Create an error result
    static func failure(
        callID: String,
        toolName: String,
        error: ToolError,
        duration: TimeInterval
    ) -> ToolResult {
        ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .error(error),
            duration: duration
        )
    }

    /// Create a rejection result (tool execution denied by user)
    /// Used when human-in-loop approval denies the tool call
    static func rejection(
        callID: String,
        toolName: String,
        reason: String
    ) -> ToolResult {
        let message = "Tool execution was rejected by user: \(reason)"
        return ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .error(ToolError(message: message, isRetryable: false)),
            duration: 0
        )
    }

    /// Create from MCP call result
    static func from(
        mcpResult: MCPToolCallResult,
        callID: String,
        toolName: String,
        duration: TimeInterval
    ) -> ToolResult {
        if mcpResult.isError == true {
            let errorMessage = mcpResult.content.compactMap { content -> String? in
                if case .text(let textContent) = content {
                    return textContent.text
                }
                return nil
            }.joined(separator: "\n")

            return ToolResult(
                callID: callID,
                toolName: toolName,
                outcome: .error(ToolError(message: errorMessage.isEmpty ? "Tool execution failed" : errorMessage)),
                duration: duration
            )
        }

        let content = ToolContent.from(mcpContent: mcpResult.content)
        return ToolResult(
            callID: callID,
            toolName: toolName,
            outcome: .success(content),
            duration: duration
        )
    }
}

// MARK: - Tool Outcome

/// Outcome of tool execution
enum ToolOutcome: Sendable {
    case success(ToolContent)
    case error(ToolError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Equatable

extension ToolOutcome: Equatable {
    static func == (lhs: ToolOutcome, rhs: ToolOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.success(let lhsContent), .success(let rhsContent)):
            return lhsContent == rhsContent
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Tool Content

/// Content returned by successful tool execution
struct ToolContent: Equatable, Sendable {
    /// Text content (most common)
    let text: String?

    /// Raw JSON data (for complex responses)
    let json: Data?

    /// Image data (base64 decoded)
    let imageData: Data?

    /// MIME type for image
    let imageMimeType: String?

    // MARK: - Initialization

    init(
        text: String? = nil,
        json: Data? = nil,
        imageData: Data? = nil,
        imageMimeType: String? = nil
    ) {
        self.text = text
        self.json = json
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }

    // MARK: - Computed Properties

    /// Summary for display (truncated if needed)
    var displaySummary: String {
        if let text = text {
            return text.count > 200 ? String(text.prefix(200)) + "..." : text
        }
        if json != nil {
            return "[JSON data]"
        }
        if imageData != nil {
            return "[Image]"
        }
        return "[Empty result]"
    }

    /// Full text content for LLM
    var contentForLLM: String {
        if let text = text {
            return text
        }
        if let json = json, let jsonString = String(data: json, encoding: .utf8) {
            return jsonString
        }
        if imageData != nil {
            return "[Image content - see attached image]"
        }
        return ""
    }

    // MARK: - Factory Methods

    /// Create text content
    static func text(_ text: String) -> ToolContent {
        ToolContent(text: text)
    }

    /// Create JSON content
    static func json(_ data: Data) -> ToolContent {
        ToolContent(json: data)
    }

    /// Create image content
    static func image(data: Data, mimeType: String) -> ToolContent {
        ToolContent(imageData: data, imageMimeType: mimeType)
    }

    /// Create from MCP content array
    static func from(mcpContent: [MCPContent]) -> ToolContent {
        var textParts: [String] = []
        var imageData: Data?
        var imageMimeType: String?

        for content in mcpContent {
            switch content {
            case .text(let textContent):
                textParts.append(textContent.text)
            case .image(let imageContent):
                imageData = Data(base64Encoded: imageContent.data)
                imageMimeType = imageContent.mimeType
            case .resource(let resourceContent):
                if let text = resourceContent.resource.text {
                    textParts.append(text)
                } else if let blob = resourceContent.resource.blob {
                    textParts.append("[Binary resource: \(resourceContent.resource.uri)]")
                    // Could store blob data if needed
                    _ = blob
                }
            }
        }

        return ToolContent(
            text: textParts.isEmpty ? nil : textParts.joined(separator: "\n"),
            json: nil,
            imageData: imageData,
            imageMimeType: imageMimeType
        )
    }
}

// MARK: - Tool Error

/// Error from tool execution
struct ToolError: Equatable, Error, Sendable {
    /// Error message
    let message: String

    /// Error code (if provided)
    let code: Int?

    /// Whether this error is retryable
    let isRetryable: Bool

    init(message: String, code: Int? = nil, isRetryable: Bool = false) {
        self.message = message
        self.code = code
        self.isRetryable = isRetryable
    }

    /// Create from connector error
    static func from(connectorError: ConnectorError) -> ToolError {
        ToolError(
            message: connectorError.localizedDescription,
            isRetryable: connectorError.isRetryable
        )
    }
}

extension ToolError: LocalizedError {
    var errorDescription: String? {
        message
    }
}
