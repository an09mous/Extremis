// MARK: - Web Fetch Connector
// Built-in connector for web fetching via remote MCP server

import Foundation
import MCP
import Logging

/// Logger for Web Fetch connector operations
private let webFetchLogger = Logger(label: "mcp.connector.webfetch")

/// Built-in connector for web fetching using a hosted MCP server
/// Provides tools for fetching and processing web content
@MainActor
final class WebFetchConnector: Connector, ObservableObject {

    // MARK: - Constants

    private enum Constants {
        static let mcpEndpoint = URL(string: "https://remote.mcpservers.org/fetch/mcp")!
    }

    // MARK: - Connector Protocol

    nonisolated var id: String { "webfetch" }

    var name: String { "Web Fetch" }

    @Published private(set) var state: ConnectorState = .disconnected

    @Published private(set) var tools: [ConnectorTool] = []

    var isEnabled: Bool {
        UserDefaults.standard.webFetchConnectorEnabled
    }

    // MARK: - Private Properties

    private var client: Client?
    private var httpTransport: HTTPTransport?

    // MARK: - Initialization

    init() {}

    // MARK: - Connector Methods

    func connect() async throws {
        guard isEnabled else {
            state = .disconnected
            return
        }

        guard state != .connecting else {
            webFetchLogger.debug("[WebFetch] Already connecting, skipping")
            return
        }

        webFetchLogger.info("[WebFetch] Starting connection...")
        print("[WebFetch] Starting connection...")
        state = .connecting
        tools = []

        do {
            // Create HTTP transport (no auth required)
            let transportConfig = HTTPTransport.Configuration(
                url: Constants.mcpEndpoint,
                headers: [:],
                streaming: true
            )

            let transport = HTTPTransport(
                config: transportConfig,
                logger: Logger(label: "mcp.transport.webfetch")
            )
            httpTransport = transport

            // Create MCP client
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let mcpClient = Client(name: "Extremis", version: appVersion)
            client = mcpClient

            // Connect to MCP server
            webFetchLogger.debug("[WebFetch] Connecting to MCP server (http)...")
            print("[WebFetch] Connecting to remote MCP server...")

            let initResult = try await withMCPTimeout(ConnectorConstants.connectionTimeout) {
                try await mcpClient.connect(transport: transport)
            }

            // Log server info
            let serverInfo = initResult.serverInfo
            webFetchLogger.info("[WebFetch] Server: \(serverInfo.name) v\(serverInfo.version)")
            print("[WebFetch] Server: \(serverInfo.name) v\(serverInfo.version)")

            // Discover tools
            webFetchLogger.debug("[WebFetch] Discovering tools...")
            print("[WebFetch] Discovering tools...")

            let (sdkTools, _) = try await withMCPTimeout(ConnectorConstants.toolDiscoveryTimeout) {
                try await mcpClient.listTools()
            }
            print("[WebFetch] Discovered \(sdkTools.count) tools")

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
            webFetchLogger.info("[WebFetch] Connected with \(tools.count) tools")
            print("[WebFetch] Connected with \(tools.count) tools")

            if !tools.isEmpty {
                let toolNames = tools.prefix(5).map { $0.originalName }.joined(separator: ", ")
                let suffix = tools.count > 5 ? ", ..." : ""
                webFetchLogger.debug("[WebFetch] Tools: \(toolNames)\(suffix)")
            }

        } catch {
            let errorMessage = error.localizedDescription
            webFetchLogger.error("[WebFetch] Connection failed: \(errorMessage)")
            print("[WebFetch] Connection failed: \(errorMessage)")
            state = .error(errorMessage)
            client = nil
            httpTransport = nil
            throw error
        }
    }

    func disconnect() async {
        webFetchLogger.info("[WebFetch] Disconnecting...")

        if let client = client {
            await client.disconnect()
        }

        client = nil
        httpTransport = nil
        tools = []
        state = .disconnected

        webFetchLogger.info("[WebFetch] Disconnected")
        print("[WebFetch] Disconnected")
    }

    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        // Check for cancellation before starting
        if Task.isCancelled {
            webFetchLogger.info("[WebFetch] Tool '\(call.toolName)' cancelled before execution")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: 0
            )
        }

        guard state.isConnected, let client = client else {
            webFetchLogger.warning("[WebFetch] Cannot execute tool '\(call.toolName)': not connected")
            throw ConnectorError.notConnected
        }

        // Find the tool to get original name
        let toolOriginalName: String
        if let tool = tools.first(where: { $0.name == call.toolName }) {
            toolOriginalName = tool.originalName
        } else if let tool = tools.first(where: { $0.originalName == call.toolName }) {
            toolOriginalName = tool.originalName
        } else {
            webFetchLogger.error("[WebFetch] Tool not found: '\(call.toolName)'")
            throw ConnectorError.toolNotFound(call.toolName)
        }

        webFetchLogger.debug("[WebFetch] Executing tool '\(toolOriginalName)'...")
        let startTime = Date()

        do {
            // Convert arguments to SDK Value type using shared helper
            let sdkArguments = convertArgumentsToSDKValues(call.arguments)

            // Execute with cancellation-aware timeout using shared helper
            let (content, isError) = try await withCancellableMCPTimeout(ConnectorConstants.toolExecutionTimeout) {
                try await client.callTool(name: toolOriginalName, arguments: sdkArguments)
            }

            // Check for cancellation after tool returns
            if Task.isCancelled {
                let duration = Date().timeIntervalSince(startTime)
                webFetchLogger.info("[WebFetch] Tool '\(toolOriginalName)' cancelled after completion (result discarded)")
                return ToolResult.failure(
                    callID: call.id,
                    toolName: call.toolName,
                    error: ToolError(message: "Execution cancelled"),
                    duration: duration
                )
            }

            let duration = Date().timeIntervalSince(startTime)
            webFetchLogger.info("[WebFetch] Tool '\(toolOriginalName)' completed in \(String(format: "%.2f", duration))s")

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
            webFetchLogger.info("[WebFetch] Tool '\(toolOriginalName)' cancelled after \(String(format: "%.2f", duration))s")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: duration
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            webFetchLogger.error("[WebFetch] Tool '\(toolOriginalName)' failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: error.localizedDescription),
                duration: duration
            )
        }
    }
}
