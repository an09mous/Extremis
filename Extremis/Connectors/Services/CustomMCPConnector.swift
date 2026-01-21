// MARK: - Custom MCP Connector
// Connector implementation for user-configured MCP servers using MCP Swift SDK

import Foundation
import MCP
import Logging

/// Logger for connector operations
private let connectorLogger = Logger(label: "mcp.connector")

/// Connector for custom MCP servers
@MainActor
final class CustomMCPConnector: Connector, ObservableObject {

    // MARK: - Properties

    /// Immutable config ID for identity (nonisolated access)
    nonisolated let configID: UUID

    /// The server configuration
    private(set) var config: CustomMCPServerConfig

    /// Current connection state
    @Published private(set) var state: ConnectorState = .disconnected

    /// Tools discovered from this server
    @Published private(set) var tools: [ConnectorTool] = []

    /// The MCP client from SDK
    private var client: Client?

    /// The transport for the subprocess (stdio)
    private var processTransport: ProcessTransport?

    /// The transport for HTTP connections
    private var httpTransport: HTTPTransport?

    /// Secrets storage for API keys
    private let secretsStorage: ConnectorSecretsStorage

    // MARK: - Connector Protocol

    nonisolated var id: String {
        configID.uuidString
    }

    var name: String {
        config.name
    }

    var isEnabled: Bool {
        config.enabled
    }

    // MARK: - Initialization

    init(config: CustomMCPServerConfig, secretsStorage: ConnectorSecretsStorage = .shared) {
        self.configID = config.id
        self.config = config
        self.secretsStorage = secretsStorage
    }

    // MARK: - Configuration Updates

    /// Update the server configuration
    func updateConfig(_ newConfig: CustomMCPServerConfig) async {
        let wasConnected = state.isConnected
        let configChanged = config.transport != newConfig.transport

        config = newConfig

        // If transport config changed and we were connected, reconnect
        if configChanged && wasConnected {
            await disconnect()
            if newConfig.enabled {
                try? await connect()
            }
        }
    }

    // MARK: - Connection

    func connect() async throws {
        guard config.enabled else {
            connectorLogger.warning("[\(name)] Cannot connect: server is disabled")
            throw ConnectorError.notConnected
        }

        guard state != .connecting else {
            connectorLogger.debug("[\(name)] Already connecting, skipping")
            return
        }

        connectorLogger.info("[\(name)] Starting connection...")
        print("[MCP:\(name)] Starting connection...")
        state = .connecting
        tools = []

        do {
            // Create MCP client
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let newClient = Client(name: "Extremis", version: appVersion)
            client = newClient

            // Connect based on transport type
            let initResult: Initialize.Result
            switch config.transport {
            case .stdio(let stdioConfig):
                initResult = try await connectStdio(
                    client: newClient,
                    stdioConfig: stdioConfig
                )
            case .http(let httpConfig):
                initResult = try await connectHTTP(
                    client: newClient,
                    httpConfig: httpConfig
                )
            }
            print("[MCP:\(name)] MCP protocol initialized")

            // Log server info
            let serverInfo = initResult.serverInfo
            connectorLogger.info("[\(name)] Server: \(serverInfo.name) v\(serverInfo.version)")
            print("[MCP:\(name)] Server: \(serverInfo.name) v\(serverInfo.version)")

            // Discover tools
            connectorLogger.debug("[\(name)] Discovering tools...")
            print("[MCP:\(name)] Discovering tools...")

            let (sdkTools, _) = try await withTimeout(ConnectorConstants.toolDiscoveryTimeout) {
                try await newClient.listTools()
            }
            print("[MCP:\(name)] Discovered \(sdkTools.count) tools")

            // Convert SDK tools to ConnectorTool
            tools = sdkTools.map { sdkTool in
                ConnectorTool(
                    originalName: sdkTool.name,
                    description: sdkTool.description,
                    inputSchema: convertToJSONSchema(sdkTool.inputSchema),
                    connectorID: id,
                    connectorName: name
                )
            }

            state = .connected
            connectorLogger.info("[\(name)] ✓ Connected with \(tools.count) tools")
            print("[MCP:\(name)] ✓ Connected with \(tools.count) tools")

            if !tools.isEmpty {
                let toolNames = tools.prefix(5).map { $0.originalName }.joined(separator: ", ")
                let suffix = tools.count > 5 ? ", ..." : ""
                connectorLogger.debug("[\(name)] Tools: \(toolNames)\(suffix)")
            }

        } catch {
            let errorMessage = error.localizedDescription
            connectorLogger.error("[\(name)] ✗ Connection failed: \(errorMessage)")
            print("[MCP:\(name)] ✗ Connection failed: \(errorMessage)")
            state = .error(errorMessage)
            client = nil
            processTransport = nil
            httpTransport = nil
            throw error
        }
    }

    func disconnect() async {
        connectorLogger.info("[\(name)] Disconnecting...")

        if let client = client {
            await client.disconnect()
        }

        client = nil
        processTransport = nil
        httpTransport = nil
        tools = []
        state = .disconnected

        connectorLogger.info("[\(name)] Disconnected")
    }

    // MARK: - Tool Execution

    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        // Check for cancellation before starting
        if Task.isCancelled {
            connectorLogger.info("[\(name)] Tool '\(call.toolName)' cancelled before execution")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: 0
            )
        }

        guard state.isConnected, let client = client else {
            connectorLogger.warning("[\(name)] Cannot execute tool '\(call.toolName)': not connected")
            throw ConnectorError.notConnected
        }

        // Find the tool to get original name
        let toolOriginalName: String
        if let tool = tools.first(where: { $0.name == call.toolName }) {
            toolOriginalName = tool.originalName
        } else if let tool = tools.first(where: { $0.originalName == call.toolName }) {
            toolOriginalName = tool.originalName
        } else {
            connectorLogger.error("[\(name)] Tool not found: '\(call.toolName)'")
            throw ConnectorError.toolNotFound(call.toolName)
        }

        connectorLogger.debug("[\(name)] Executing tool '\(toolOriginalName)'...")
        let startTime = Date()

        do {
            // Convert arguments to SDK Value type
            let sdkArguments = convertToSDKValues(call.arguments)

            // Use cancellation-aware timeout wrapper
            // Note: MCP servers are external processes, so cancellation won't stop them mid-execution.
            // However, we can return early and ignore their result.
            let (content, isError) = try await withCancellableTimeout(ConnectorConstants.toolExecutionTimeout) {
                try await client.callTool(name: toolOriginalName, arguments: sdkArguments)
            }

            // Check for cancellation after tool returns
            if Task.isCancelled {
                let duration = Date().timeIntervalSince(startTime)
                connectorLogger.info("[\(name)] Tool '\(toolOriginalName)' cancelled after completion (result discarded)")
                return ToolResult.failure(
                    callID: call.id,
                    toolName: call.toolName,
                    error: ToolError(message: "Execution cancelled"),
                    duration: duration
                )
            }

            let duration = Date().timeIntervalSince(startTime)
            connectorLogger.info("[\(name)] Tool '\(toolOriginalName)' completed in \(String(format: "%.2f", duration))s")

            // Convert SDK content to ToolResult
            return convertToolResult(
                content: content,
                isError: isError,
                callID: call.id,
                toolName: call.toolName,
                duration: duration
            )

        } catch is CancellationError {
            let duration = Date().timeIntervalSince(startTime)
            connectorLogger.info("[\(name)] Tool '\(toolOriginalName)' cancelled after \(String(format: "%.2f", duration))s")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: duration
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            connectorLogger.error("[\(name)] Tool '\(toolOriginalName)' failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: error.localizedDescription),
                duration: duration
            )
        }
    }

    // MARK: - Transport Connection Helpers

    /// Connect using STDIO transport (subprocess)
    private func connectStdio(
        client: Client,
        stdioConfig: StdioConfig
    ) async throws -> Initialize.Result {
        // Build environment with secrets
        let environment = try buildEnvironment()

        // Create transport configuration
        let transportConfig = ProcessTransport.Configuration(
            command: stdioConfig.command,
            args: stdioConfig.args,
            environment: environment
        )

        // Create process transport
        connectorLogger.debug("[\(name)] Creating process transport...")
        print("[MCP:\(name)] Creating process transport...")
        let newTransport = ProcessTransport(
            config: transportConfig,
            logger: Logger(label: "mcp.transport.\(name)")
        )
        processTransport = newTransport

        // Connect to MCP server (MCP protocol handshake)
        connectorLogger.debug("[\(name)] Connecting to MCP server (stdio)...")
        print("[MCP:\(name)] Connecting to MCP server (stdio)...")

        return try await withTimeout(ConnectorConstants.connectionTimeout) {
            try await client.connect(transport: newTransport)
        }
    }

    /// Connect using HTTP transport (remote server)
    private func connectHTTP(
        client: Client,
        httpConfig: HTTPConfig
    ) async throws -> Initialize.Result {
        // Build headers with secrets (e.g., Authorization header)
        var headers = httpConfig.headers

        // Merge secret headers from Keychain
        if let secrets = try? secretsStorage.loadSecrets(forCustomServer: config.id) {
            headers = secrets.mergeWithHeaders(headers)
        }

        // Create HTTP transport configuration
        let transportConfig = HTTPTransport.Configuration(
            url: httpConfig.url,
            headers: headers,
            streaming: true  // Enable SSE for server-to-client messages
        )

        // Create HTTP transport
        connectorLogger.debug("[\(name)] Creating HTTP transport...")
        print("[MCP:\(name)] Creating HTTP transport to \(httpConfig.url.absoluteString)...")
        let newTransport = HTTPTransport(
            config: transportConfig,
            logger: Logger(label: "mcp.transport.\(name)")
        )
        httpTransport = newTransport

        // Connect to MCP server
        connectorLogger.debug("[\(name)] Connecting to MCP server (http)...")
        print("[MCP:\(name)] Connecting to MCP server (http)...")

        return try await withTimeout(ConnectorConstants.connectionTimeout) {
            try await client.connect(transport: newTransport)
        }
    }

    // MARK: - Private Helpers

    /// Build environment with secrets
    private func buildEnvironment() throws -> [String: String] {
        try secretsStorage.buildEnvironment(for: config)
    }

    /// Convert SDK Value (inputSchema) to our JSONSchema
    private func convertToJSONSchema(_ sdkSchema: Value) -> JSONSchema {
        // The inputSchema is a Value that represents a JSON Schema object
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
                    type: extractType(from: value),
                    description: extractDescription(from: value)
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
    private func extractType(from value: Value) -> String {
        // Try to extract type from the value structure
        if case .object(let dict) = value {
            if case .string(let typeStr) = dict["type"] {
                return typeStr
            }
        }
        return "string" // Default
    }

    /// Extract description from SDK Value
    private func extractDescription(from value: Value) -> String? {
        if case .object(let dict) = value {
            if case .string(let desc) = dict["description"] {
                return desc
            }
        }
        return nil
    }

    /// Convert our arguments dictionary to SDK Value dictionary
    private func convertToSDKValues(_ arguments: [String: JSONValue]) -> [String: Value] {
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

    /// Convert SDK tool result to our ToolResult
    private func convertToolResult(
        content: [Tool.Content],
        isError: Bool?,
        callID: String,
        toolName: String,
        duration: TimeInterval
    ) -> ToolResult {
        // Extract text content from SDK Tool.Content enum
        var textParts: [String] = []

        for item in content {
            switch item {
            case .text(let text):
                // SDK .text case contains the text directly
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

    /// Execute with timeout using async let racing
    nonisolated private func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }

            // Add the timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ConnectorError.connectionTimeout
            }

            // Get the first result (either success or timeout)
            guard let result = try await group.next() else {
                throw ConnectorError.connectionTimeout
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }

    /// Execute with timeout and proper cancellation propagation
    /// When the parent task is cancelled, this throws CancellationError immediately
    nonisolated private func withCancellableTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        // Check for cancellation before starting
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                // Add the main operation
                group.addTask {
                    try await operation()
                }

                // Add the timeout
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ConnectorError.connectionTimeout
                }

                // Get the first result (either success or timeout)
                guard let result = try await group.next() else {
                    throw ConnectorError.connectionTimeout
                }

                // Cancel remaining tasks
                group.cancelAll()

                return result
            }
        } onCancel: {
            // When parent is cancelled, we can't stop the external process
            // but the TaskGroup will be cancelled and throw CancellationError
        }
    }
}

// MARK: - Hashable

extension CustomMCPConnector: Hashable {
    nonisolated static func == (lhs: CustomMCPConnector, rhs: CustomMCPConnector) -> Bool {
        lhs.configID == rhs.configID
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(configID)
    }
}
