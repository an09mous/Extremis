// MARK: - Tool Enabled Chat Service
// Orchestrates LLM generation with tool execution loop

import Foundation

/// Service that manages LLM chat with tool execution capabilities
/// Handles the multi-turn loop: LLM → tool calls → execute → feed back → LLM...
@MainActor
final class ToolEnabledChatService {

    // MARK: - Singleton

    static let shared = ToolEnabledChatService()

    // MARK: - Dependencies

    private let connectorRegistry: ConnectorRegistry
    private let toolExecutor: ToolExecutor

    // MARK: - Configuration

    /// Maximum number of tool execution rounds before forcing completion
    /// Prevents infinite loops if LLM keeps requesting tools
    private let maxToolRounds: Int = 10

    // MARK: - Initialization

    init(
        connectorRegistry: ConnectorRegistry = .shared,
        toolExecutor: ToolExecutor = .shared
    ) {
        self.connectorRegistry = connectorRegistry
        self.toolExecutor = toolExecutor
    }

    // MARK: - Public Methods

    /// Generate a response with tool support
    /// Returns an async stream of generation events (content chunks and tool status updates)
    func generateWithTools(
        provider: LLMProvider,
        messages: [ChatMessage],
        onToolCallsStarted: @escaping ([ChatToolCall]) -> Void,
        onToolCallUpdated: @escaping (String, ToolCallState, String?, TimeInterval?) -> Void
    ) async throws -> String {
        // Get available tools from all enabled connectors
        let availableTools = connectorRegistry.toolDefinitions

        // If no tools are available, fall back to regular generation
        if availableTools.isEmpty {
            return try await generateWithoutTools(provider: provider, messages: messages)
        }

        // Multi-turn tool execution loop
        // Track complete history of tool rounds for proper conversation context
        var toolRounds: [ToolExecutionRound] = []
        var rounds = 0
        var finalContent: String = ""

        while rounds < maxToolRounds {
            rounds += 1
            print("🔧 Tool round \(rounds) starting...")

            // Call LLM with tools and full tool execution history
            let generation = try await provider.generateChatWithTools(
                messages: messages,
                tools: availableTools,
                toolRounds: toolRounds
            )

            // Accumulate any text content
            if let content = generation.content {
                finalContent += content
            }

            // If no tool calls, we're done
            if generation.isComplete {
                print("🔧 Generation complete after \(rounds) round(s)")
                break
            }

            // Convert LLM tool calls to our internal format
            let toolCalls = resolveToolCalls(
                llmCalls: generation.toolCalls,
                availableTools: availableTools
            )

            if toolCalls.isEmpty {
                print("⚠️ LLM returned tool calls but none could be resolved")
                break
            }

            // Create UI models for display
            let chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
            onToolCallsStarted(chatToolCalls)

            // Execute tools
            let results = await executeToolsWithUpdates(
                toolCalls: toolCalls,
                onToolCallUpdated: onToolCallUpdated
            )

            // Add this round to history (pairs tool calls with their results)
            toolRounds.append(ToolExecutionRound(
                toolCalls: generation.toolCalls,
                results: results
            ))

            print("🔧 Round \(rounds) complete: \(results.count) tool results")
        }

        if rounds >= maxToolRounds {
            print("⚠️ Reached maximum tool rounds (\(maxToolRounds))")
        }

        return finalContent
    }

    /// Stream-based generation with tools (for UI that needs incremental updates)
    /// Note: Tool execution is not streamed - only the final text response can be
    func generateWithToolsStream(
        provider: LLMProvider,
        messages: [ChatMessage],
        onToolCallsStarted: @escaping ([ChatToolCall]) -> Void,
        onToolCallUpdated: @escaping (String, ToolCallState, String?, TimeInterval?) -> Void
    ) -> AsyncThrowingStream<ToolEnabledGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Track resolved tool calls for persistence - declared outside do block for catch access
                var resolvedToolRounds: [(toolCalls: [ToolCall], results: [ToolResult])] = []

                do {
                    // Get available tools
                    let availableTools = self.connectorRegistry.toolDefinitions

                    // If no tools, use regular streaming
                    if availableTools.isEmpty {
                        for try await chunk in provider.generateChatStream(messages: messages) {
                            continuation.yield(.contentChunk(chunk))
                        }
                        // No tools used, emit empty completion
                        continuation.yield(.generationComplete(toolRounds: []))
                        continuation.finish()
                        return
                    }

                    // Extract historical tool rounds from persisted messages
                    // This ensures LLM has context of previous tool executions in the conversation
                    let historicalToolRounds = self.extractHistoricalToolRounds(from: messages)
                    if !historicalToolRounds.isEmpty {
                        print("🔧 Found \(historicalToolRounds.count) historical tool rounds from previous messages")
                    }

                    // Tool execution loop
                    // Start with historical rounds for proper conversation context
                    var toolRounds: [ToolExecutionRound] = historicalToolRounds
                    var rounds = 0

                    while rounds < self.maxToolRounds {
                        rounds += 1
                        print("🔧 Tool round \(rounds) starting...")

                        // Call LLM with tools using streaming API
                        var streamedToolCalls: [LLMToolCall] = []

                        for try await event in provider.generateChatWithToolsStream(
                            messages: messages,
                            tools: availableTools,
                            toolRounds: toolRounds
                        ) {
                            switch event {
                            case .textChunk(let text):
                                continuation.yield(.contentChunk(text))
                            case .complete(let toolCalls):
                                streamedToolCalls = toolCalls
                            }
                        }

                        // If no tool calls, we're done
                        if streamedToolCalls.isEmpty {
                            print("🔧 Round \(rounds): No tool calls, generation complete")
                            break
                        }

                        // Resolve and execute tool calls
                        let toolCalls = self.resolveToolCalls(
                            llmCalls: streamedToolCalls,
                            availableTools: availableTools
                        )

                        if toolCalls.isEmpty {
                            break
                        }

                        // Notify about tool calls starting
                        let chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
                        continuation.yield(.toolCallsStarted(chatToolCalls))
                        onToolCallsStarted(chatToolCalls)

                        // Track results for this round incrementally
                        var currentRoundToolCalls: [ToolCall] = []
                        var currentRoundResults: [ToolResult] = []

                        // Execute tools with progress updates
                        let results = await self.executeToolsWithUpdates(
                            toolCalls: toolCalls,
                            onToolCallUpdated: { id, state, summary, duration in
                                continuation.yield(.toolCallUpdated(id, state, summary, duration))
                                onToolCallUpdated(id, state, summary, duration)
                            },
                            onToolResultReady: { toolCall, result in
                                // Emit each result as it completes (for incremental persistence)
                                currentRoundToolCalls.append(toolCall)
                                currentRoundResults.append(result)
                                continuation.yield(.toolResultReady(toolCall: toolCall, result: result))
                            }
                        )

                        // Add this round to history (pairs tool calls with their results)
                        toolRounds.append(ToolExecutionRound(
                            toolCalls: streamedToolCalls,
                            results: results
                        ))

                        // Track resolved calls for persistence
                        resolvedToolRounds.append((toolCalls: toolCalls, results: results))

                        // Emit round completed event for persistence tracking
                        continuation.yield(.toolRoundCompleted(toolCalls: toolCalls, results: results))
                        print("🔧 Round \(rounds) complete: executed \(results.count) tools")
                    }

                    print("🔧 Generation finished after \(rounds) round(s), \(resolvedToolRounds.count) new tool rounds")

                    // Convert to persistence records and emit completion
                    let roundRecords = resolvedToolRounds.map { round in
                        ToolExecutionRoundRecord.from(toolCalls: round.toolCalls, results: round.results)
                    }
                    continuation.yield(.generationComplete(toolRounds: roundRecords))

                    continuation.finish()
                } catch {
                    // Emit partial results before finishing with error
                    // This ensures any completed tool rounds are persisted
                    if !resolvedToolRounds.isEmpty {
                        let partialRecords = resolvedToolRounds.map { round in
                            ToolExecutionRoundRecord.from(toolCalls: round.toolCalls, results: round.results)
                        }
                        continuation.yield(.generationInterrupted(error: error, partialToolRounds: partialRecords))
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Fall back to regular generation when no tools available
    private func generateWithoutTools(
        provider: LLMProvider,
        messages: [ChatMessage]
    ) async throws -> String {
        let generation = try await provider.generateChat(messages: messages)
        return generation.content
    }

    /// Resolve LLM tool calls to internal ToolCall format
    private func resolveToolCalls(
        llmCalls: [LLMToolCall],
        availableTools: [ConnectorTool]
    ) -> [ToolCall] {
        llmCalls.compactMap { llmCall in
            // Convert arguments from [String: Any] to [String: JSONValue]
            let jsonArgs = llmCall.arguments.mapValues { JSONValue.from($0) }

            return ToolCall.from(
                llmCallID: llmCall.id,
                toolName: llmCall.name,
                arguments: jsonArgs,
                availableTools: availableTools
            )
        }
    }

    /// Execute tools with progress updates
    /// Reports each tool result as it completes (not waiting for all)
    private func executeToolsWithUpdates(
        toolCalls: [ToolCall],
        onToolCallUpdated: @escaping (String, ToolCallState, String?, TimeInterval?) -> Void,
        onToolResultReady: ((ToolCall, ToolResult) -> Void)? = nil
    ) async -> [ToolResult] {
        // Mark all as executing
        for call in toolCalls {
            onToolCallUpdated(call.id, .executing, nil, nil)
        }

        // Execute sequentially to report each result immediately
        var results: [ToolResult] = []
        results.reserveCapacity(toolCalls.count)

        for call in toolCalls {
            // Check for cancellation before each tool
            if Task.isCancelled {
                // Mark remaining tools as cancelled
                let cancelledResult = ToolResult.failure(
                    callID: call.id,
                    toolName: call.toolName,
                    error: ToolError(message: "Execution cancelled"),
                    duration: 0
                )
                results.append(cancelledResult)
                onToolCallUpdated(call.id, .failed, "Cancelled", 0)
                continue
            }

            let result = await toolExecutor.execute(call)
            results.append(result)

            // Update UI immediately for this tool
            let state: ToolCallState = result.isSuccess ? .completed : .failed
            let summary = result.isSuccess ? result.content?.displaySummary : nil
            let errorMsg = result.error?.message

            onToolCallUpdated(
                result.callID,
                state,
                summary ?? errorMsg,
                result.duration
            )

            // Notify about this result immediately (for incremental persistence)
            onToolResultReady?(call, result)
        }

        return results
    }

    /// Extract historical tool rounds from persisted messages
    /// This reconstructs ToolExecutionRound from messages that have toolRounds
    private func extractHistoricalToolRounds(from messages: [ChatMessage]) -> [ToolExecutionRound] {
        var allRounds: [ToolExecutionRound] = []

        for message in messages {
            // Only assistant messages can have tool rounds
            guard message.role == .assistant,
                  let toolRounds = message.toolRounds,
                  !toolRounds.isEmpty else {
                continue
            }

            // Convert persisted records to ToolExecutionRound
            let rounds = toolRounds.toToolExecutionRounds()
            allRounds.append(contentsOf: rounds)
        }

        return allRounds
    }
}

// MARK: - Generation Events

/// Events emitted during tool-enabled generation
enum ToolEnabledGenerationEvent {
    /// Text content chunk from LLM
    case contentChunk(String)

    /// Tool calls are starting
    case toolCallsStarted([ChatToolCall])

    /// A tool call's state was updated
    case toolCallUpdated(String, ToolCallState, String?, TimeInterval?)

    /// A single tool result is ready (for incremental persistence)
    /// Emitted as soon as each tool completes, before the round is fully done
    case toolResultReady(toolCall: ToolCall, result: ToolResult)

    /// A tool execution round completed (for persistence)
    /// Contains the resolved ToolCalls and their results
    case toolRoundCompleted(toolCalls: [ToolCall], results: [ToolResult])

    /// Generation completed - provides all tool rounds for persistence
    case generationComplete(toolRounds: [ToolExecutionRoundRecord])

    /// Generation was interrupted - provides partial tool rounds that completed
    case generationInterrupted(error: Error, partialToolRounds: [ToolExecutionRoundRecord])
}
