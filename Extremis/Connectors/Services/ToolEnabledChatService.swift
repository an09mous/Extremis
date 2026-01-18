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
                do {
                    // Get available tools
                    let availableTools = self.connectorRegistry.toolDefinitions

                    // If no tools, use regular streaming
                    if availableTools.isEmpty {
                        for try await chunk in provider.generateChatStream(messages: messages) {
                            continuation.yield(.contentChunk(chunk))
                        }
                        continuation.finish()
                        return
                    }

                    // Tool execution loop
                    // Track complete history of tool rounds for proper conversation context
                    var toolRounds: [ToolExecutionRound] = []
                    var rounds = 0

                    while rounds < self.maxToolRounds {
                        rounds += 1

                        // Call LLM with tools and full tool execution history
                        let generation = try await provider.generateChatWithTools(
                            messages: messages,
                            tools: availableTools,
                            toolRounds: toolRounds
                        )

                        // Yield any text content
                        if let content = generation.content, !content.isEmpty {
                            continuation.yield(.contentChunk(content))
                        }

                        // If no tool calls, we're done
                        if generation.isComplete {
                            break
                        }

                        // Resolve and execute tool calls
                        let toolCalls = self.resolveToolCalls(
                            llmCalls: generation.toolCalls,
                            availableTools: availableTools
                        )

                        if toolCalls.isEmpty {
                            break
                        }

                        // Notify about tool calls starting
                        let chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
                        continuation.yield(.toolCallsStarted(chatToolCalls))
                        onToolCallsStarted(chatToolCalls)

                        // Execute tools with progress updates
                        let results = await self.executeToolsWithUpdates(
                            toolCalls: toolCalls,
                            onToolCallUpdated: { id, state, summary, duration in
                                continuation.yield(.toolCallUpdated(id, state, summary, duration))
                                onToolCallUpdated(id, state, summary, duration)
                            }
                        )

                        // Add this round to history (pairs tool calls with their results)
                        toolRounds.append(ToolExecutionRound(
                            toolCalls: generation.toolCalls,
                            results: results
                        ))
                    }

                    continuation.finish()
                } catch {
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
    private func executeToolsWithUpdates(
        toolCalls: [ToolCall],
        onToolCallUpdated: @escaping (String, ToolCallState, String?, TimeInterval?) -> Void
    ) async -> [ToolResult] {
        // Mark all as executing
        for call in toolCalls {
            onToolCallUpdated(call.id, .executing, nil, nil)
        }

        // Execute in parallel
        let batchResult = await toolExecutor.executeBatch(toolCalls)

        // Update UI with results
        for result in batchResult.results {
            let state: ToolCallState = result.isSuccess ? .completed : .failed
            let summary = result.isSuccess ? result.content?.displaySummary : nil
            let errorMsg = result.error?.message

            onToolCallUpdated(
                result.callID,
                state,
                summary ?? errorMsg,
                result.duration
            )
        }

        return batchResult.results
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
}
