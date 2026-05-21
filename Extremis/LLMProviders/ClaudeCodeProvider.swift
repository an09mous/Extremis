// MARK: - Claude Code Provider
// LLM provider that wraps the Claude Code CLI as a persistent subprocess
// Uses --input-format stream-json for bidirectional NDJSON communication
// No API key required — leverages the user's existing Claude Code subscription auth

import Foundation
import Combine

/// Claude Code CLI provider implementation
@MainActor
final class ClaudeCodeProvider: LLMProvider, ObservableObject {

    // MARK: - Properties

    let providerType: LLMProviderType = .claudeCode
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    @Published private(set) var currentModel: LLMModel
    @Published private(set) var cliAvailable: Bool = false

    /// Whether the provider is ready to use
    var isConfigured: Bool { cliAvailable }

    /// Path to the claude CLI binary (default: "claude", resolved via PATH)
    private var cliBinaryPath: String

    /// User-configured tool approvals
    @Published var allowedTools: [CLIToolInfo] = []

    /// The persistent process manager
    private(set) var processManager = ClaudeCodeProcessManager()

    /// Whether a generation is in progress
    var isProcessRunning: Bool {
        processManager.processState == .generating
    }

    // MARK: - Initialization

    init() {
        // Load saved model or use default
        let models = LLMProviderType.claudeCode.availableModels
        let savedModelId = UserDefaults.standard.string(forKey: "claudecode_model")
        self.currentModel = models.first { $0.id == savedModelId } ?? models.first ?? LLMModel(
            id: "sonnet", name: "Sonnet", description: "Recommended daily model"
        )

        // Load saved binary path
        self.cliBinaryPath = UserDefaults.standard.string(forKey: "claudecode_binary_path") ?? "claude"

        // Load saved allowed tools
        if let data = UserDefaults.standard.data(forKey: "claudecode_allowed_tools"),
           let toolNames = try? JSONDecoder().decode([String].self, from: data) {
            self.allowedTools = toolNames.map { CLIToolInfo(name: $0, isApproved: true) }
        }

        // Check CLI availability on init
        Task {
            await checkCLIAvailability()
        }
    }

    // MARK: - LLMProvider Protocol

    func configure(apiKey: String) throws {
        // Claude Code doesn't use API keys
        // Repurpose for custom binary path configuration
        if !apiKey.isEmpty {
            cliBinaryPath = apiKey
            UserDefaults.standard.set(apiKey, forKey: "claudecode_binary_path")
        }
        Task {
            await checkCLIAvailability()
        }
    }

    func setModel(_ model: LLMModel) {
        currentModel = model
        UserDefaults.standard.set(model.id, forKey: "claudecode_model")
        print("Claude Code model set to: \(model.name)")

        // Reset conversation when model changes — need new process with different model
        resetConversation()
    }

    // MARK: - Generation Methods

    func generateRaw(prompt: String) async throws -> Generation {
        var accumulated = ""
        for try await chunk in generateRawStream(prompt: prompt) {
            accumulated += chunk
        }
        return Generation(content: accumulated)
    }

    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        streamResponse(prompt: prompt, images: nil)
    }

    /// Internal streaming method that supports optional image attachments
    private func streamResponse(prompt: String, images: [ImageAttachment]?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard self.isConfigured else {
                    continuation.finish(throwing: LLMProviderError.notConfigured(provider: .claudeCode))
                    return
                }

                // Ensure process is running
                do {
                    try await self.ensureProcessRunning()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                let stream = self.processManager.sendMessage(prompt, images: images)

                do {
                    for try await event in stream {
                        switch event {
                        case .textDelta(let text):
                            continuation.yield(text)
                        case .resultSuccess:
                            continuation.finish()
                            return
                        case .resultError(let error):
                            continuation.finish(throwing: LLMProviderError.unknown(error))
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateChat(messages: [ChatMessage]) async throws -> Generation {
        let content = buildMessageContent(from: messages)
        let images = extractLastUserImages(from: messages)
        var accumulated = ""
        for try await chunk in streamResponse(prompt: content, images: images) {
            accumulated += chunk
        }
        return Generation(content: accumulated)
    }

    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let content = buildMessageContent(from: messages)
        let images = extractLastUserImages(from: messages)
        return streamResponse(prompt: content, images: images)
    }

    func generateChatWithTools(
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) async throws -> ToolEnabledGeneration {
        // Claude Code handles its own tools — we just generate text
        let result = try await generateChat(messages: messages)
        return .text(result.content)
    }

    func generateChatWithToolsStream(
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        // Stream text and emit complete with no tool calls
        // CLI handles its own tools — Extremis only displays them
        let chatStream = generateChatStream(messages: messages)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in chatStream {
                        continuation.yield(.textChunk(chunk))
                    }
                    continuation.yield(.complete(toolCalls: []))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - CLI Management

    /// Check if the claude CLI is available on the system
    func checkCLIAvailability() async {
        let resolvedPath: String?
        if cliBinaryPath != "claude" {
            resolvedPath = cliBinaryPath
        } else {
            resolvedPath = await resolveClaudeBinaryPath()
        }

        if let resolved = resolvedPath {
            cliAvailable = true
            if cliBinaryPath == "claude" {
                cliBinaryPath = resolved
            }
            print("Claude Code CLI found at: \(resolved)")
        } else {
            cliAvailable = false
            print("Claude Code CLI not found")
        }
    }

    /// Called when provider is activated — start the persistent process
    func activateProcess() {
        Task {
            do {
                try await ensureProcessRunning()
            } catch {
                print("Failed to start Claude Code process: \(error)")
            }
        }
    }

    /// Called when provider is deactivated
    func deactivateProcess() {
        processManager.stop()
    }

    /// Cancel in-progress generation
    func cancelGeneration() {
        processManager.cancelGeneration()
    }

    /// Reset conversation — kills process so next message starts fresh session
    func resetConversation() {
        processManager.resetConversation()
    }

    /// Notify that the Extremis session has changed (user switched or created new session)
    /// Resets the CLI process so conversation context doesn't leak between sessions
    func notifySessionChanged() {
        processManager.resetConversation()
    }

    // MARK: - Tool Management

    /// Update the allowed tools list with discoveries from CLI
    func updateDiscoveredTools(_ toolNames: [String]) {
        let existingApprovals = Dictionary(uniqueKeysWithValues: allowedTools.map { ($0.name, $0.isApproved) })

        allowedTools = toolNames.map { name in
            CLIToolInfo(name: name, isApproved: existingApprovals[name] ?? false)
        }
    }

    /// Set approval state for a tool
    func setToolApproval(_ toolName: String, approved: Bool) {
        if let index = allowedTools.firstIndex(where: { $0.name == toolName }) {
            allowedTools[index].isApproved = approved
        }
        persistToolApprovals()
    }

    /// Persist tool approvals to UserDefaults
    func persistToolApprovals() {
        let approvedNames = allowedTools.filter(\.isApproved).map(\.name)
        if let data = try? JSONEncoder().encode(approvedNames) {
            UserDefaults.standard.set(data, forKey: "claudecode_allowed_tools")
        }
    }

    // MARK: - Private Helpers

    /// Ensure the persistent process is running, starting it if needed
    private func ensureProcessRunning() async throws {
        if processManager.isReady {
            return
        }

        let approvedToolNames = allowedTools.filter(\.isApproved).map(\.name)
        let systemPrompt = buildSystemPrompt()

        try await processManager.start(
            binaryPath: cliBinaryPath,
            model: currentModel.id,
            allowedTools: approvedToolNames,
            systemPrompt: systemPrompt
        )

        // Process is ready immediately after start() — no need to wait for system/init
        // With --input-format stream-json, init event arrives after first message
        guard processManager.isReady else {
            throw LLMProviderError.unknown("CLI process failed to start")
        }
    }

    /// Build the message content to send to the CLI process.
    /// First message to a fresh process: sends full conversation history so Claude has context.
    /// Subsequent messages: sends only the latest user message (CLI already has history).
    private func buildMessageContent(from messages: [ChatMessage]) -> String {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return ""
        }

        let lastContent = PromptBuilder.shared.formatUserMessageWithContext(
            lastUserMessage.content,
            context: lastUserMessage.context,
            intent: lastUserMessage.intent
        )

        // If the CLI process already has conversation context, just send the latest message
        if processManager.sessionId != nil {
            return lastContent
        }

        // Fresh process — build full conversation context for the first message
        let priorMessages = messages.filter { $0.id != lastUserMessage.id }
        guard !priorMessages.isEmpty else {
            return lastContent
        }

        var parts: [String] = []
        parts.append("[Conversation history from this session — use as context for your response]")
        for msg in priorMessages {
            let role = msg.role == .user ? "User" : "Assistant"
            parts.append("\(role): \(msg.content)")
        }
        parts.append("[End of conversation history]")
        parts.append("")
        parts.append(lastContent)

        return parts.joined(separator: "\n")
    }

    /// Extract image attachments from the last user message (if any)
    /// Only the latest user message's images are sent — prior images are already in CLI session context
    private func extractLastUserImages(from messages: [ChatMessage]) -> [ImageAttachment]? {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }),
              let images = lastUserMessage.imageAttachments, !images.isEmpty else {
            return nil
        }
        return images
    }

    private func buildSystemPrompt() -> String? {
        guard let template = try? PromptTemplateLoader.shared.load(.system) else {
            return nil
        }
        return template
    }

    private func resolveClaudeBinaryPath() async -> String? {
        await ClaudeCodeProcessManager.resolveClaudePath()
    }
}

// MARK: - CLI Tool Info

/// Represents a tool available in the Claude Code CLI
struct CLIToolInfo: Codable, Identifiable, Hashable {
    let name: String
    var isApproved: Bool

    var id: String { name }
}
