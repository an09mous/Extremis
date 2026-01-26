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
    private let approvalManager: ToolApprovalManager

    // MARK: - Configuration

    /// Maximum number of tool execution rounds before forcing completion
    /// Prevents infinite loops if LLM keeps requesting tools
    private let maxToolRounds: Int = 50

    // MARK: - Initialization

    init(
        connectorRegistry: ConnectorRegistry = .shared,
        toolExecutor: ToolExecutor = .shared,
        approvalManager: ToolApprovalManager = .shared
    ) {
        self.connectorRegistry = connectorRegistry
        self.toolExecutor = toolExecutor
        self.approvalManager = approvalManager
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

        // If no tools are configured, fall back to regular generation
        if availableTools.isEmpty {
            return try await generateWithoutTools(provider: provider, messages: messages)
        }

        // Check if the model supports tools
        let modelSupportsTools = await provider.supportsTools
        if !modelSupportsTools {
            print("🔧 Model '\(provider.currentModel.name)' (\(provider.providerType.displayName)) doesn't support tools - falling back to regular chat (skipping \(availableTools.count) available tools)")
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

            // Build messages for this round
            // If we have tool rounds from previous iterations, create a synthetic assistant message
            // Note: message.content is empty - all text is carried in each round's assistantResponse
            var messagesForProvider = messages
            if !toolRounds.isEmpty {
                let roundRecords = toolRounds.map { round in
                    ToolExecutionRoundRecord(
                        toolCalls: round.toolCalls.map { ToolCallRecord.from($0, connectorID: "") },
                        results: round.results.map { ToolResultRecord.from($0) },
                        assistantResponse: round.assistantResponse
                    )
                }
                let syntheticMessage = ChatMessage.assistant("", toolRounds: roundRecords)
                messagesForProvider.append(syntheticMessage)
            }

            // Call LLM with tools
            let generation: ToolEnabledGeneration
            do {
                generation = try await provider.generateChatWithTools(
                    messages: messagesForProvider,
                    tools: availableTools
                )
            } catch let error as LLMProviderError where isToolCapabilityError(error) {
                // Tool capability error - fall back to regular chat
                print("🔧 Tool capability error for '\(provider.currentModel.name)': \(error.localizedDescription) - falling back to regular chat")
                return try await generateWithoutTools(provider: provider, messages: messages)
            }

            // Accumulate any text content
            var roundText = ""
            if let content = generation.content {
                finalContent += content
                roundText = content
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
            // Include the partial text response from this round
            toolRounds.append(ToolExecutionRound(
                toolCalls: generation.toolCalls,
                results: results,
                assistantResponse: roundText.isEmpty ? nil : roundText
            ))

            print("🔧 Round \(rounds) complete: \(results.count) tool results")
        }

        // If we hit the max rounds limit, make one final LLM call without tools to get a summary
        if rounds >= maxToolRounds && !toolRounds.isEmpty {
            print("⚠️ Reached maximum tool rounds (\(maxToolRounds)) - making final summarization call")

            // Build final messages with all tool rounds
            var finalMessages = messages
            let roundRecords = toolRounds.map { round in
                ToolExecutionRoundRecord(
                    toolCalls: round.toolCalls.map { ToolCallRecord.from($0, connectorID: "") },
                    results: round.results.map { ToolResultRecord.from($0) },
                    assistantResponse: round.assistantResponse
                )
            }
            let syntheticMessage = ChatMessage.assistant("", toolRounds: roundRecords)
            finalMessages.append(syntheticMessage)

            // Add a user message prompting for summary using template
            let summaryPrompt = buildToolSummarizationPrompt(
                toolCount: toolRounds.reduce(0) { $0 + $1.toolCalls.count },
                roundCount: toolRounds.count
            )
            finalMessages.append(ChatMessage.user(summaryPrompt, context: nil))

            // Make final call without tools to force a text response
            let summaryResponse = try await provider.generateChat(messages: finalMessages)
            finalContent += summaryResponse.content
        }

        return finalContent
    }

    /// Stream-based generation with tools (for UI that needs incremental updates)
    /// Note: Tool execution is not streamed - only the final text response can be
    /// - Parameters:
    ///   - provider: The LLM provider to use
    ///   - messages: The chat messages to send
    ///   - sessionApprovalMemory: Session-scoped approval memory for "remember for session" functionality
    ///   - sessionId: The chat session ID for isolating approval decisions
    ///   - onToolCallsStarted: Callback when tool calls start
    ///   - onToolCallUpdated: Callback when a tool call state changes
    func generateWithToolsStream(
        provider: LLMProvider,
        messages: [ChatMessage],
        sessionApprovalMemory: SessionApprovalMemory?,
        sessionId: UUID?,
        onToolCallsStarted: @escaping ([ChatToolCall]) -> Void,
        onToolCallUpdated: @escaping (String, ToolCallState, String?, TimeInterval?) -> Void
    ) -> AsyncThrowingStream<ToolEnabledGenerationEvent, Error> {
        // Use a class to share cancellation state between the stream and its internal Task
        // This is needed because Task {} doesn't inherit cancellation from the stream consumer
        final class CancellationState: @unchecked Sendable {
            var isCancelled = false
        }
        let cancellationState = CancellationState()

        return AsyncThrowingStream { continuation in
            // Set up termination handler to detect when stream consumer cancels
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    cancellationState.isCancelled = true
                    print("🛑 Stream terminated (cancelled) - marking internal state")
                }
            }

            Task {
                // Helper to check if we should stop (either Task cancelled OR stream cancelled)
                func shouldStop() -> Bool {
                    Task.isCancelled || cancellationState.isCancelled
                }

                // Track resolved tool calls for persistence - declared outside do block for catch access
                var resolvedToolRounds: [(toolCalls: [ToolCall], results: [ToolResult], assistantResponse: String?)] = []

                do {
                    // Get available tools
                    let availableTools = self.connectorRegistry.toolDefinitions

                    // If no tools configured, use regular streaming
                    if availableTools.isEmpty {
                        for try await chunk in provider.generateChatStream(messages: messages) {
                            continuation.yield(.contentChunk(chunk))
                        }
                        // No tools used, emit empty completion
                        continuation.yield(.generationComplete(toolRounds: [], finalContent: ""))
                        continuation.finish()
                        return
                    }

                    // Check if the model supports tools
                    let modelSupportsTools = await provider.supportsTools
                    if !modelSupportsTools {
                        print("🔧 Model '\(provider.currentModel.name)' (\(provider.providerType.displayName)) doesn't support tools - falling back to regular chat (skipping \(availableTools.count) available tools)")
                        for try await chunk in provider.generateChatStream(messages: messages) {
                            continuation.yield(.contentChunk(chunk))
                        }
                        continuation.yield(.generationComplete(toolRounds: [], finalContent: ""))
                        continuation.finish()
                        return
                    }

                    // Tool execution loop
                    // Current tool rounds are built as synthetic messages before each provider call
                    var toolRounds: [ToolExecutionRound] = []
                    var rounds = 0

                    // Track final text content (response after last tool execution, when no more tools are called)
                    var finalTextContent = ""

                    // Track if "Allow All Once" was used - skip approval for rest of this generation
                    var allowAllOnceActive = false

                    while rounds < self.maxToolRounds {
                        // CRITICAL: Check for cancellation at the START of each round
                        // This is the primary exit point - if stop was pressed, exit immediately
                        // Uses shouldStop() which checks both Task.isCancelled AND stream cancellation
                        if shouldStop() {
                            print("🛑 Generation cancelled - stopping tool loop at start of round \(rounds + 1)")
                            break
                        }

                        rounds += 1
                        print("🔧 Tool round \(rounds) starting...")

                        // Build messages for this round
                        // If we have tool rounds from previous iterations, create a synthetic assistant message
                        var messagesForProvider = messages
                        if !toolRounds.isEmpty {
                            // Convert current tool rounds to records for the synthetic message
                            // Note: message.content is empty - all text is carried in each round's assistantResponse
                            let roundRecords = toolRounds.map { round in
                                ToolExecutionRoundRecord(
                                    toolCalls: round.toolCalls.map { ToolCallRecord.from($0, connectorID: "") },
                                    results: round.results.map { ToolResultRecord.from($0) },
                                    assistantResponse: round.assistantResponse
                                )
                            }
                            let syntheticMessage = ChatMessage.assistant("", toolRounds: roundRecords)
                            messagesForProvider.append(syntheticMessage)
                        }

                        // Call LLM with tools using streaming API
                        var streamedToolCalls: [LLMToolCall] = []
                        var roundText = ""  // Track partial text for this round

                        for try await event in provider.generateChatWithToolsStream(
                            messages: messagesForProvider,
                            tools: availableTools
                        ) {
                            // Check cancellation during streaming
                            if shouldStop() {
                                print("🛑 Generation cancelled during LLM streaming")
                                break
                            }
                            switch event {
                            case .textChunk(let text):
                                continuation.yield(.contentChunk(text))
                                roundText += text  // Accumulate partial text
                            case .complete(let toolCalls):
                                streamedToolCalls = toolCalls
                            }
                        }

                        // Check for cancellation after LLM call completes
                        if shouldStop() {
                            print("🛑 Generation cancelled after LLM response - not processing tool calls")
                            break
                        }

                        // If no tool calls, we're done - capture the final text response
                        if streamedToolCalls.isEmpty {
                            print("🔧 Round \(rounds): No tool calls, generation complete")
                            finalTextContent = roundText
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

                        // Notify about tool calls starting (with pendingApproval state)
                        var chatToolCalls = toolCalls.map { ChatToolCall.from($0) }
                        // Mark all as pending approval initially (unless allowAllOnce is active)
                        if !allowAllOnceActive {
                            for i in chatToolCalls.indices {
                                chatToolCalls[i].markPendingApproval()
                            }
                        }
                        continuation.yield(.toolCallsStarted(chatToolCalls))
                        onToolCallsStarted(chatToolCalls)

                        // Determine approved/denied tools
                        let approvedToolCalls: [ToolCall]
                        let deniedToolCalls: [ToolCall]

                        if allowAllOnceActive {
                            // "Allow All Once" was used in a previous round - auto-approve all tools
                            print("🔓 Auto-approving \(toolCalls.count) tools (Allow All Once active)")
                            approvedToolCalls = toolCalls
                            deniedToolCalls = []

                            // Update UI state to approved
                            for toolCall in approvedToolCalls {
                                continuation.yield(.toolCallUpdated(toolCall.id, .approved, nil, nil))
                                onToolCallUpdated(toolCall.id, .approved, nil, nil)
                            }
                        } else {
                            // Check for cancellation before approval request
                            // This ensures we don't show approval UI if generation was already stopped
                            if shouldStop() {
                                print("🛑 Generation cancelled before tool approval - skipping")
                                continuation.finish()
                                return
                            }

                            // Request approval for tool calls (T3.7)
                            let approvalResult = await self.approvalManager.requestApproval(
                                for: toolCalls,
                                sessionMemory: sessionApprovalMemory,
                                sessionId: sessionId
                            )

                            // Check for cancellation after approval returns
                            // This handles the case where user stopped generation while approval UI was open
                            // Even if they clicked "approve", we should not execute tools
                            if shouldStop() {
                                print("🛑 Generation cancelled during/after approval - not executing tools")
                                // Mark all tools as cancelled
                                for toolCall in toolCalls {
                                    continuation.yield(.toolCallUpdated(toolCall.id, .cancelled, "Cancelled", nil))
                                    onToolCallUpdated(toolCall.id, .cancelled, "Cancelled", nil)
                                }
                                continuation.finish()
                                return
                            }

                            // Check if "Allow All Once" was used
                            if approvalResult.allowAllOnce {
                                print("🔓 Allow All Once activated - subsequent tool calls will be auto-approved")
                                allowAllOnceActive = true
                            }

                            // Filter to only approved tools
                            approvedToolCalls = toolCalls.filter { approvalResult.approvedIds.contains($0.id) }
                            deniedToolCalls = toolCalls.filter { !approvalResult.approvedIds.contains($0.id) }

                            // Update UI state for approved/denied tools (T3.9)
                            for toolCall in approvedToolCalls {
                                continuation.yield(.toolCallUpdated(toolCall.id, .approved, nil, nil))
                                onToolCallUpdated(toolCall.id, .approved, nil, nil)
                            }
                            for toolCall in deniedToolCalls {
                                continuation.yield(.toolCallUpdated(toolCall.id, .denied, "Denied by user", nil))
                                onToolCallUpdated(toolCall.id, .denied, "Denied by user", nil)
                            }
                        }

                        // If any tools were denied, stop generation (like Claude Code behavior)
                        // Don't continue the loop - user denied means stop ALL tools
                        if !deniedToolCalls.isEmpty {
                            print("🛑 Tool(s) denied by user - stopping ALL tool execution")

                            // Mark approved tools as cancelled (they won't execute due to denial)
                            for toolCall in approvedToolCalls {
                                continuation.yield(.toolCallUpdated(toolCall.id, .cancelled, "Cancelled (another tool was denied)", nil))
                                onToolCallUpdated(toolCall.id, .cancelled, "Cancelled (another tool was denied)", nil)
                            }

                            // Emit a message to the user explaining what happened
                            let deniedToolNames = deniedToolCalls.map { $0.toolName }.joined(separator: ", ")
                            let denialMessage = "Tool execution was denied for: \(deniedToolNames). All tool execution stopped."
                            continuation.yield(.contentChunk(denialMessage))

                            // Record the round with all tools (denied + cancelled approved)
                            var allResults: [ToolResult] = []
                            // Add denied results
                            allResults.append(contentsOf: deniedToolCalls.map { toolCall in
                                ToolResult.rejection(
                                    callID: toolCall.id,
                                    toolName: toolCall.toolName,
                                    reason: "User denied execution"
                                )
                            })
                            // Add cancelled results for approved tools that won't run
                            allResults.append(contentsOf: approvedToolCalls.map { toolCall in
                                ToolResult.failure(
                                    callID: toolCall.id,
                                    toolName: toolCall.toolName,
                                    error: ToolError(message: "Cancelled (another tool was denied)"),
                                    duration: 0
                                )
                            })

                            let deniedRound = ToolExecutionRound(
                                toolCalls: streamedToolCalls,
                                results: allResults,
                                assistantResponse: roundText.isEmpty ? nil : roundText
                            )
                            toolRounds.append(deniedRound)
                            resolvedToolRounds.append((toolCalls: toolCalls, results: allResults, assistantResponse: roundText.isEmpty ? nil : roundText))

                            // Emit round completed and stop
                            continuation.yield(.toolRoundCompleted(toolCalls: toolCalls, results: allResults))
                            break  // Exit the tool execution loop
                        }

                        // Execute approved tools with progress updates (T3.17)
                        var allResults: [ToolResult] = []
                        if !approvedToolCalls.isEmpty {
                            let executionResults = await self.executeToolsWithUpdates(
                                toolCalls: approvedToolCalls,
                                onToolCallUpdated: { id, state, summary, duration in
                                    continuation.yield(.toolCallUpdated(id, state, summary, duration))
                                    onToolCallUpdated(id, state, summary, duration)
                                },
                                onToolResultReady: { toolCall, result in
                                    // Emit each result as it completes (for incremental persistence)
                                    continuation.yield(.toolResultReady(toolCall: toolCall, result: result))
                                }
                            )
                            allResults.append(contentsOf: executionResults)
                        }

                        // CRITICAL: Check for cancellation after tool execution completes
                        // Even if MCP subprocess is still running, WE stop processing here
                        if shouldStop() {
                            print("🛑 Generation cancelled after tool execution - not continuing to next round")
                            // Don't add to history, don't continue loop - just exit
                            break
                        }

                        // Use execution results
                        let results = allResults

                        // Add this round to history (pairs tool calls with their results)
                        // Include any partial text streamed before tool calls
                        toolRounds.append(ToolExecutionRound(
                            toolCalls: streamedToolCalls,
                            results: results,
                            assistantResponse: roundText.isEmpty ? nil : roundText
                        ))

                        // Track resolved calls for persistence (with assistant response)
                        resolvedToolRounds.append((toolCalls: toolCalls, results: results, assistantResponse: roundText.isEmpty ? nil : roundText))

                        // Emit round completed event for persistence tracking
                        continuation.yield(.toolRoundCompleted(toolCalls: toolCalls, results: results))
                        print("🔧 Round \(rounds) complete: executed \(results.count) tools")
                    }

                    // If we hit the max rounds limit, make one final LLM call without tools to get a summary
                    if rounds >= self.maxToolRounds && !toolRounds.isEmpty && !shouldStop() {
                        print("⚠️ Reached maximum tool rounds (\(self.maxToolRounds)) - making final summarization call")

                        // Build final messages with all tool rounds
                        var finalMessages = messages
                        let finalRoundRecords = toolRounds.map { round in
                            ToolExecutionRoundRecord(
                                toolCalls: round.toolCalls.map { ToolCallRecord.from($0, connectorID: "") },
                                results: round.results.map { ToolResultRecord.from($0) },
                                assistantResponse: round.assistantResponse
                            )
                        }
                        let syntheticMessage = ChatMessage.assistant("", toolRounds: finalRoundRecords)
                        finalMessages.append(syntheticMessage)

                        // Add a user message prompting for summary using template
                        let summaryPrompt = self.buildToolSummarizationPrompt(
                            toolCount: toolRounds.reduce(0) { $0 + $1.toolCalls.count },
                            roundCount: toolRounds.count
                        )
                        finalMessages.append(ChatMessage.user(summaryPrompt, context: nil))

                        // Make final streaming call without tools to force a text response
                        // Accumulate the summary text as the final content
                        for try await chunk in provider.generateChatStream(messages: finalMessages) {
                            if shouldStop() { break }
                            continuation.yield(.contentChunk(chunk))
                            finalTextContent += chunk  // Capture summary as final content
                        }
                    }

                    print("🔧 Generation finished after \(rounds) round(s), \(resolvedToolRounds.count) new tool rounds")

                    // Convert to persistence records and emit completion
                    let roundRecords = resolvedToolRounds.map { round in
                        ToolExecutionRoundRecord.from(toolCalls: round.toolCalls, results: round.results, assistantResponse: round.assistantResponse)
                    }
                    continuation.yield(.generationComplete(toolRounds: roundRecords, finalContent: finalTextContent))

                    continuation.finish()
                } catch let error as LLMProviderError {
                    // Check if this is a tool capability error - if so, fall back to regular chat
                    if self.isToolCapabilityError(error) {
                        print("🔧 Tool capability error for '\(provider.currentModel.name)': \(error.localizedDescription) - falling back to regular chat")
                        do {
                            for try await chunk in provider.generateChatStream(messages: messages) {
                                continuation.yield(.contentChunk(chunk))
                            }
                            continuation.yield(.generationComplete(toolRounds: [], finalContent: ""))
                            continuation.finish()
                            return
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    // Emit partial results before finishing with error
                    // This ensures any completed tool rounds are persisted
                    if !resolvedToolRounds.isEmpty {
                        let partialRecords = resolvedToolRounds.map { round in
                            ToolExecutionRoundRecord.from(toolCalls: round.toolCalls, results: round.results, assistantResponse: round.assistantResponse)
                        }
                        continuation.yield(.generationInterrupted(error: error, partialToolRounds: partialRecords))
                    }
                    continuation.finish(throwing: error)
                } catch {
                    // Non-LLMProviderError - emit partial results and throw
                    if !resolvedToolRounds.isEmpty {
                        let partialRecords = resolvedToolRounds.map { round in
                            ToolExecutionRoundRecord.from(toolCalls: round.toolCalls, results: round.results, assistantResponse: round.assistantResponse)
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

            // Check for cancellation after execution - if cancelled, stop processing remaining tools
            if Task.isCancelled {
                onToolCallUpdated(call.id, .cancelled, "Cancelled", result.duration)
                // Mark any remaining tools as cancelled without executing
                let currentIndex = toolCalls.firstIndex(where: { $0.id == call.id }) ?? 0
                for remainingCall in toolCalls.suffix(from: currentIndex + 1) {
                    let cancelledResult = ToolResult.failure(
                        callID: remainingCall.id,
                        toolName: remainingCall.toolName,
                        error: ToolError(message: "Execution cancelled"),
                        duration: 0
                    )
                    results.append(cancelledResult)
                    onToolCallUpdated(remainingCall.id, .cancelled, "Cancelled", 0)
                }
                break
            }

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

    /// Build the summarization prompt from template
    /// - Parameters:
    ///   - toolCount: Total number of tool calls executed
    ///   - roundCount: Number of tool execution rounds
    /// - Returns: Formatted prompt string
    private func buildToolSummarizationPrompt(toolCount: Int, roundCount: Int) -> String {
        do {
            let template = try PromptTemplateLoader.shared.load(.toolSummarization)
            return template
                .replacingOccurrences(of: "{{TOOL_COUNT}}", with: String(toolCount))
                .replacingOccurrences(of: "{{ROUND_COUNT}}", with: String(roundCount))
        } catch {
            // Fallback if template fails to load
            print("⚠️ Failed to load tool summarization template: \(error)")
            return "You have executed \(toolCount) tool calls across \(roundCount) rounds. Based ONLY on the tool results you received, provide a response. If the tools returned errors or insufficient data, explain what information is missing. Do NOT make up information."
        }
    }

    /// Detect if an error indicates the model doesn't support tools
    /// Used to trigger graceful fallback to regular chat
    private func isToolCapabilityError(_ error: LLMProviderError) -> Bool {
        switch error {
        case .serverError(let statusCode, let message):
            // HTTP 400 with tool-related message indicates capability issue
            if statusCode == 400 {
                let lowercased = (message ?? "").lowercased()
                return lowercased.contains("tool") ||
                       lowercased.contains("function") ||
                       lowercased.contains("unsupported") ||
                       lowercased.contains("not support")
            }
            return false
        case .unknown(let message):
            let lowercased = message.lowercased()
            return lowercased.contains("tool") ||
                   lowercased.contains("function") ||
                   lowercased.contains("not support")
        default:
            return false
        }
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

    /// Generation completed - provides all tool rounds and final text content for persistence
    /// finalContent is the LLM's final text response after all tool execution (when no more tools are called)
    case generationComplete(toolRounds: [ToolExecutionRoundRecord], finalContent: String)

    /// Generation was interrupted - provides partial tool rounds that completed
    case generationInterrupted(error: Error, partialToolRounds: [ToolExecutionRoundRecord])
}
