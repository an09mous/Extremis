// MARK: - Tool Executor
// Service for executing tool calls with parallel execution support

import Foundation

/// Service for executing tool calls from LLM responses
/// Supports parallel execution via TaskGroup for efficiency
@MainActor
final class ToolExecutor {

    // MARK: - Singleton

    static let shared = ToolExecutor()

    // MARK: - Dependencies

    private let registry: ConnectorRegistry

    // MARK: - Initialization

    init(registry: ConnectorRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - Execution

    /// Execute a single tool call
    /// - Parameter call: The tool call to execute
    /// - Returns: The result of the tool execution
    func execute(_ call: ToolCall) async -> ToolResult {
        let startTime = Date()

        // Check for cancellation before starting
        if Task.isCancelled {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
                duration: 0
            )
        }

        // Get the connector for this tool
        guard let connector = registry.connector(id: call.connectorID) else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Connector not found: \(call.connectorID)"),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Check if connector is connected
        guard connector.state.isConnected else {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(
                    message: "Connector '\(connector.name)' is not connected",
                    isRetryable: true
                ),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Execute with timeout using MainActor-safe approach
        do {
            let result = try await withTimeoutMainActor(
                ConnectorConstants.toolExecutionTimeout
            ) {
                try await connector.executeTool(call)
            }
            return result
        } catch let error as ToolError {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: error,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch is TimeoutError {
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(
                    message: "Tool execution timed out after \(Int(ConnectorConstants.toolExecutionTimeout)) seconds",
                    isRetryable: true
                ),
                duration: Date().timeIntervalSince(startTime)
            )
        } catch is CancellationError {
            // Task was cancelled - return cancelled result
            return ToolResult.failure(
                callID: call.id,
                toolName: call.toolName,
                error: ToolError(message: "Execution cancelled"),
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

    /// Execute multiple tool calls
    /// - Parameter calls: The tool calls to execute
    /// - Returns: Results for each tool call, in the same order as input
    /// Note: Executes sequentially on MainActor for Swift 6 concurrency safety
    func execute(toolCalls calls: [ToolCall]) async -> [ToolResult] {
        guard !calls.isEmpty else { return [] }

        // Execute all calls sequentially on MainActor
        var results: [ToolResult] = []
        results.reserveCapacity(calls.count)

        for call in calls {
            // Check for cancellation before each tool
            if Task.isCancelled {
                // Add cancelled results for remaining tools
                for remainingCall in calls.suffix(from: results.count) {
                    results.append(ToolResult.failure(
                        callID: remainingCall.id,
                        toolName: remainingCall.toolName,
                        error: ToolError(message: "Execution cancelled"),
                        duration: 0
                    ))
                }
                break
            }

            let result = await execute(call)
            results.append(result)
        }

        return results
    }

    // MARK: - Tool Lookup

    /// Find and create tool calls from LLM response
    /// - Parameters:
    ///   - toolCalls: Raw tool calls from LLM (name + arguments)
    ///   - availableTools: Tools available for lookup
    /// - Returns: Valid tool calls and any tools that couldn't be found
    func resolveToolCalls(
        from rawCalls: [(id: String, name: String, arguments: [String: JSONValue])],
        availableTools: [ConnectorTool]
    ) -> (valid: [ToolCall], notFound: [String]) {
        var validCalls: [ToolCall] = []
        var notFoundTools: [String] = []

        for raw in rawCalls {
            if let call = ToolCall.from(
                llmCallID: raw.id,
                toolName: raw.name,
                arguments: raw.arguments,
                availableTools: availableTools
            ) {
                validCalls.append(call)
            } else {
                notFoundTools.append(raw.name)
            }
        }

        return (validCalls, notFoundTools)
    }

    /// Get available tools for LLM
    var availableTools: [ConnectorTool] {
        registry.availableTools
    }

    /// Check if any tools are available
    var hasTools: Bool {
        !registry.availableTools.isEmpty
    }
}

// MARK: - Timeout Helper

/// Error thrown when an operation times out
struct TimeoutError: Error {
    let timeout: TimeInterval
}

/// MainActor-safe timeout wrapper
/// Uses Task cancellation instead of racing tasks
/// Also propagates parent task cancellation properly
@MainActor
func withTimeoutMainActor<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @MainActor () async throws -> T
) async throws -> T {
    // Check for cancellation before starting
    try Task.checkCancellation()

    // Create a task for the operation
    let task = Task { @MainActor in
        try await operation()
    }

    // Create a timeout task that will cancel the operation
    let timeoutTask = Task { @MainActor in
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        task.cancel()
    }

    // Use withTaskCancellationHandler to propagate parent cancellation
    return try await withTaskCancellationHandler {
        do {
            let result = try await task.value
            timeoutTask.cancel()
            return result
        } catch is CancellationError {
            timeoutTask.cancel()
            throw TimeoutError(timeout: timeout)
        } catch {
            timeoutTask.cancel()
            throw error
        }
    } onCancel: {
        // When parent task is cancelled, cancel the operation task
        task.cancel()
        timeoutTask.cancel()
    }
}

/// Result wrapper for timeout race
private enum TimeoutResult<T: Sendable>: Sendable {
    case success(T)
    case timeout
}

/// Execute an async operation with a timeout
/// - Parameters:
///   - timeout: Maximum time to wait in seconds
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: TimeoutError if the operation takes longer than timeout
func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: TimeoutResult<T>.self) { group in
        // Add the main operation
        group.addTask {
            let result = try await operation()
            return .success(result)
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return .timeout
        }

        // Get the first result (either success or timeout)
        guard let result = try await group.next() else {
            throw TimeoutError(timeout: timeout)
        }

        // Cancel the remaining task
        group.cancelAll()

        switch result {
        case .success(let value):
            return value
        case .timeout:
            throw TimeoutError(timeout: timeout)
        }
    }
}

// MARK: - Batch Execution Result

/// Result of executing multiple tool calls
struct BatchToolExecutionResult {
    /// All results in order
    let results: [ToolResult]

    /// Results that succeeded
    var successes: [ToolResult] {
        results.filter { $0.isSuccess }
    }

    /// Results that failed
    var failures: [ToolResult] {
        results.filter { $0.isError }
    }

    /// Whether all calls succeeded
    var allSucceeded: Bool {
        failures.isEmpty
    }

    /// Total execution time (max of individual durations since parallel)
    var totalDuration: TimeInterval {
        results.map { $0.duration }.max() ?? 0
    }

    /// Summary for logging
    var summary: String {
        let total = results.count
        let succeeded = successes.count
        let failed = failures.count
        return "\(succeeded)/\(total) succeeded, \(failed) failed in \(String(format: "%.2f", totalDuration))s"
    }
}

extension ToolExecutor {
    /// Execute tool calls and return a batch result
    func executeBatch(_ calls: [ToolCall]) async -> BatchToolExecutionResult {
        let results = await execute(toolCalls: calls)
        return BatchToolExecutionResult(results: results)
    }
}
