// MARK: - Shell Connector
// Built-in connector for executing macOS shell commands

import Foundation

/// Built-in connector for executing macOS shell commands
/// Provides a single tool (shell_execute) that runs commands with sandboxing based on risk level
@MainActor
final class ShellConnector: Connector, ObservableObject {

    // MARK: - Connector Protocol

    nonisolated var id: String { "shell" }

    var name: String { "System Commands" }

    @Published private(set) var state: ConnectorState = .disconnected

    @Published private(set) var tools: [ConnectorTool] = []

    var isEnabled: Bool {
        UserDefaults.standard.shellConnectorEnabled
    }

    // MARK: - Private Properties

    private let executor = ShellCommandExecutor.shared

    // MARK: - Tool Definition

    /// The shell_execute tool schema
    private var shellExecuteTool: ConnectorTool {
        let inputSchema = JSONSchema(
            type: "object",
            properties: [
                "command": JSONSchemaProperty.string(
                    description: "The shell command to execute (e.g., 'df -h', 'ls -la', 'uptime')"
                )
            ],
            required: ["command"],
            description: "Execute a macOS shell command and return the output"
        )

        return ConnectorTool(
            originalName: "execute",
            description: "Execute a macOS shell command. Safe commands run in a sandbox. " +
                        "Available for system info (df, uptime, sw_vers), file operations (ls, cat), " +
                        "and more. Privileged commands (sudo) are blocked.",
            inputSchema: inputSchema,
            connectorID: id,
            connectorName: name
        )
    }

    // MARK: - Initialization

    init() {
        // Tool list is built on connect
    }

    // MARK: - Connector Methods

    func connect() async throws {
        guard isEnabled else {
            state = .disconnected
            return
        }

        state = .connecting

        // Build tool list
        tools = [shellExecuteTool]

        state = .connected
        print("[ShellConnector] Connected with \(tools.count) tool(s)")
    }

    func disconnect() async {
        state = .disconnected
        tools = []
        print("[ShellConnector] Disconnected")
    }

    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        guard state.isConnected else {
            throw ConnectorError.notConnected
        }

        // Verify this is our tool
        guard call.originalToolName == "execute" else {
            throw ConnectorError.toolNotFound(call.toolName)
        }

        // Extract command from arguments
        guard let commandValue = call.arguments["command"],
              case .string(let command) = commandValue else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Missing or invalid 'command' argument"),
                duration: 0
            )
        }

        let startTime = Date()

        // Validate command
        let validation = executor.validateCommand(command)
        guard validation.isValid else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: validation.summary),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Check risk level
        let riskLevel = executor.classifyCommand(command)
        guard riskLevel.isAllowed else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(
                    message: "Command blocked: \(riskLevel.displayDescription) commands are not allowed",
                    isRetryable: false
                ),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Execute the command
        do {
            let result = try await executor.execute(command)

            // Build output message
            var output = result.combinedOutput
            if output.isEmpty {
                output = "(no output)"
            }

            // Add execution metadata
            let metadata = [
                "Exit code: \(result.exitCode)",
                "Duration: \(String(format: "%.2f", result.duration))s",
                result.wasSandboxed ? "Sandboxed: yes" : "Sandboxed: no"
            ].joined(separator: " | ")

            let fullOutput = "\(output)\n\n---\n\(metadata)"

            return ToolResult.success(
                callID: call.id,
                toolName: call.toolName,
                content: ToolContent.text(fullOutput),
                duration: result.duration
            )

        } catch let error as ShellExecutionError {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(
                    message: error.localizedDescription,
                    isRetryable: error == .timeout
                ),
                duration: Date().timeIntervalSince(startTime)
            )

        } catch {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: error.localizedDescription),
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Helper Methods

    /// Get the risk level for a command (for UI display)
    func getRiskLevel(for command: String) -> CommandRiskLevel {
        executor.classifyCommand(command)
    }

    /// Check if a command would be allowed
    func isCommandAllowed(_ command: String) -> Bool {
        let validation = executor.validateCommand(command)
        let riskLevel = executor.classifyCommand(command)
        return validation.isValid && riskLevel.isAllowed
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    /// Whether the shell connector is enabled
    /// Defaults to true (enabled by default per user requirement)
    var shellConnectorEnabled: Bool {
        get {
            // Return true if key doesn't exist (default enabled)
            if object(forKey: "shellConnectorEnabled") == nil {
                return true
            }
            return bool(forKey: "shellConnectorEnabled")
        }
        set {
            set(newValue, forKey: "shellConnectorEnabled")
        }
    }

    /// Whether sudo mode is enabled (bypasses all tool approval)
    /// Defaults to false for security
    var sudoModeEnabled: Bool {
        get { bool(forKey: "sudoModeEnabled") }
        set { set(newValue, forKey: "sudoModeEnabled") }
    }
}

// MARK: - ShellExecutionError Equatable

extension ShellExecutionError: Equatable {
    static func == (lhs: ShellExecutionError, rhs: ShellExecutionError) -> Bool {
        switch (lhs, rhs) {
        case (.commandEmpty, .commandEmpty):
            return true
        case (.timeout, .timeout):
            return true
        case (.commandBlocked(let l), .commandBlocked(let r)):
            return l == r
        case (.validationFailed(let l), .validationFailed(let r)):
            return l == r
        case (.executionFailed(let l), .executionFailed(let r)):
            return l == r
        case (.sandboxFailed(let l), .sandboxFailed(let r)):
            return l == r
        default:
            return false
        }
    }
}
