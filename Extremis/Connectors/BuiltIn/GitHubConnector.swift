// MARK: - GitHub Connector
// Built-in connector for GitHub via Copilot MCP server

import Foundation
import MCP
import Logging

/// Logger for GitHub connector operations
private let githubLogger = Logger(label: "mcp.connector.github")

/// Built-in connector for GitHub using GitHub's hosted MCP server
/// Provides access to repositories, issues, pull requests, and code via Copilot MCP
@MainActor
final class GitHubConnector: Connector, ObservableObject {

    // MARK: - Constants

    private enum Constants {
        static let mcpEndpoint = URL(string: "https://api.githubcopilot.com/mcp/")!
    }

    // MARK: - Connector Protocol

    nonisolated var id: String { "github" }

    var name: String { "GitHub" }

    @Published private(set) var state: ConnectorState = .disconnected

    @Published private(set) var tools: [ConnectorTool] = []

    var isEnabled: Bool {
        UserDefaults.standard.githubConnectorEnabled
    }

    // MARK: - Private Properties

    private let secretsStorage: ConnectorSecretsStorage
    private var client: Client?
    private var httpTransport: HTTPTransport?

    // MARK: - Initialization

    init(secretsStorage: ConnectorSecretsStorage = .shared) {
        self.secretsStorage = secretsStorage
    }

    // MARK: - Connector Methods

    func connect() async throws {
        guard isEnabled else {
            state = .disconnected
            return
        }

        guard state != .connecting else {
            githubLogger.debug("[GitHub] Already connecting, skipping")
            return
        }

        // Load token from Keychain
        guard let secrets = try? secretsStorage.loadSecrets(forBuiltIn: .github),
              let token = secrets.additionalSecrets["GITHUB_PERSONAL_ACCESS_TOKEN"],
              !token.isEmpty else {
            githubLogger.warning("[GitHub] Cannot connect: no token configured")
            state = .error("Token required")
            throw ConnectorError.authenticationRequired
        }

        githubLogger.info("[GitHub] Starting connection...")
        print("[GitHub] Starting connection...")
        state = .connecting
        tools = []

        do {
            // Create HTTP transport with auth header
            let transportConfig = HTTPTransport.Configuration(
                url: Constants.mcpEndpoint,
                headers: ["Authorization": "Bearer \(token)"],
                streaming: true
            )

            let transport = HTTPTransport(
                config: transportConfig,
                logger: Logger(label: "mcp.transport.github")
            )
            httpTransport = transport

            // Create MCP client
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let mcpClient = Client(name: "Extremis", version: appVersion)
            client = mcpClient

            // Connect to MCP server
            githubLogger.debug("[GitHub] Connecting to MCP server (http)...")
            print("[GitHub] Connecting to Copilot MCP server...")

            let initResult = try await withMCPTimeout(ConnectorConstants.connectionTimeout) {
                try await mcpClient.connect(transport: transport)
            }

            // Log server info
            let serverInfo = initResult.serverInfo
            githubLogger.info("[GitHub] Server: \(serverInfo.name) v\(serverInfo.version)")
            print("[GitHub] Server: \(serverInfo.name) v\(serverInfo.version)")

            // Discover tools
            githubLogger.debug("[GitHub] Discovering tools...")
            print("[GitHub] Discovering tools...")

            let (sdkTools, _) = try await withMCPTimeout(ConnectorConstants.toolDiscoveryTimeout) {
                try await mcpClient.listTools()
            }
            print("[GitHub] Discovered \(sdkTools.count) tools")

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
            githubLogger.info("[GitHub] Connected with \(tools.count) tools")
            print("[GitHub] Connected with \(tools.count) tools")

            if !tools.isEmpty {
                let toolNames = tools.prefix(5).map { $0.originalName }.joined(separator: ", ")
                let suffix = tools.count > 5 ? ", ..." : ""
                githubLogger.debug("[GitHub] Tools: \(toolNames)\(suffix)")
            }

        } catch {
            let errorMessage = error.localizedDescription
            githubLogger.error("[GitHub] Connection failed: \(errorMessage)")
            print("[GitHub] Connection failed: \(errorMessage)")
            state = .error(errorMessage)
            client = nil
            httpTransport = nil
            throw error
        }
    }

    func disconnect() async {
        githubLogger.info("[GitHub] Disconnecting...")

        if let client = client {
            await client.disconnect()
        }

        client = nil
        httpTransport = nil
        tools = []
        state = .disconnected

        githubLogger.info("[GitHub] Disconnected")
        print("[GitHub] Disconnected")
    }

    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        // Check for cancellation before starting
        if Task.isCancelled {
            githubLogger.info("[GitHub] Tool '\(call.toolName)' cancelled before execution")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: 0
            )
        }

        guard state.isConnected, let client = client else {
            githubLogger.warning("[GitHub] Cannot execute tool '\(call.toolName)': not connected")
            throw ConnectorError.notConnected
        }

        // Find the tool to get original name
        let toolOriginalName: String
        if let tool = tools.first(where: { $0.name == call.toolName }) {
            toolOriginalName = tool.originalName
        } else if let tool = tools.first(where: { $0.originalName == call.toolName }) {
            toolOriginalName = tool.originalName
        } else {
            githubLogger.error("[GitHub] Tool not found: '\(call.toolName)'")
            throw ConnectorError.toolNotFound(call.toolName)
        }

        githubLogger.debug("[GitHub] Executing tool '\(toolOriginalName)'...")
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
                githubLogger.info("[GitHub] Tool '\(toolOriginalName)' cancelled after completion (result discarded)")
                return ToolResult.failure(
                    callID: call.id,
                    toolName: call.toolName,
                    error: ToolError(message: "Execution cancelled"),
                    duration: duration
                )
            }

            let duration = Date().timeIntervalSince(startTime)
            githubLogger.info("[GitHub] Tool '\(toolOriginalName)' completed in \(String(format: "%.2f", duration))s")

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
            githubLogger.info("[GitHub] Tool '\(toolOriginalName)' cancelled after \(String(format: "%.2f", duration))s")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: duration
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            githubLogger.error("[GitHub] Tool '\(toolOriginalName)' failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: error.localizedDescription),
                duration: duration
            )
        }
    }
}
