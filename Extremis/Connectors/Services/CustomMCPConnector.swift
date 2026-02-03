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

            let (sdkTools, _) = try await withMCPTimeout(ConnectorConstants.toolDiscoveryTimeout) {
                try await newClient.listTools()
            }
            print("[MCP:\(name)] Discovered \(sdkTools.count) tools")

            // Convert SDK tools to ConnectorTool using shared helper
            tools = sdkTools.map { sdkTool in
                ConnectorTool(
                    originalName: sdkTool.name,
                    description: sdkTool.description,
                    inputSchema: convertSDKSchemaToJSONSchema(sdkTool.inputSchema),
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
            // Convert arguments to SDK Value type using shared helper
            let sdkArguments = convertArgumentsToSDKValues(call.arguments)

            // Use cancellation-aware timeout wrapper using shared helper
            // Note: MCP servers are external processes, so cancellation won't stop them mid-execution.
            // However, we can return early and ignore their result.
            let (content, isError) = try await withCancellableMCPTimeout(ConnectorConstants.toolExecutionTimeout) {
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

            // Convert SDK content to ToolResult using shared helper
            return convertSDKContentToToolResult(
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

        return try await withMCPTimeout(ConnectorConstants.connectionTimeout) {
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

        return try await withMCPTimeout(ConnectorConstants.connectionTimeout) {
            try await client.connect(transport: newTransport)
        }
    }

    // MARK: - Private Helpers

    /// Build environment with secrets
    private func buildEnvironment() throws -> [String: String] {
        try secretsStorage.buildEnvironment(for: config)
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
