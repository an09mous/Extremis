// MARK: - Ollama Provider
// Local LLM integration via Ollama using OpenAI-compatible API

import Foundation
import Combine

/// Ollama local LLM provider implementation
@MainActor
final class OllamaProvider: LLMProvider, ObservableObject {

    // MARK: - Properties

    let providerType: LLMProviderType = .ollama
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private let session: URLSession
    @Published private(set) var currentModel: LLMModel
    private var baseURL: String
    @Published private(set) var serverConnected: Bool = false

    /// Cached list of available models from Ollama server
    private(set) var availableModelsFromServer: [LLMModel] = []

    /// Ollama doesn't require API key, just server connectivity
    var isConfigured: Bool { serverConnected }

    // MARK: - Initialization

    init(model: LLMModel? = nil, baseURL: String = "http://127.0.0.1:11434") {
        // Start with a placeholder model - actual model will be set after fetching from server
        self.currentModel = model ?? LLMModel(id: "pending", name: "Loading...", description: "")
        self.baseURL = baseURL
        self.session = URLSession.shared

        // Load saved base URL if exists
        if let savedURL = UserDefaults.standard.string(forKey: "ollama_base_url"), !savedURL.isEmpty {
            self.baseURL = savedURL
        }

        // Note: Connection check and model restoration is done by AppDelegate.checkOllamaAndRefreshMenu() at startup
    }

    // MARK: - LLMProvider Protocol

    func configure(apiKey: String) throws {
        // Ollama doesn't use API keys - this method updates base URL instead
        if !apiKey.isEmpty {
            self.baseURL = apiKey
            UserDefaults.standard.set(apiKey, forKey: "ollama_base_url")
        }
        Task {
            await checkConnection()
        }
    }

    /// Update base URL directly (used by UI)
    func updateBaseURL(_ url: String) {
        self.baseURL = url
    }

    func setModel(_ model: LLMModel) {
        self.currentModel = model
        UserDefaults.standard.set(model.id, forKey: "ollama_model")
        print("✅ Ollama model set to: \(model.name)")
    }

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard serverConnected else {
            throw LLMProviderError.notConfigured(provider: .ollama)
        }

        let request = try buildRequest(prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""

        return Generation(content: content)
    }

    /// Stream from a raw prompt (already built, no additional processing)
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard self.serverConnected else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .ollama))
                        return
                    }

                    let request = try self.buildStreamRequest(prompt: prompt)

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if let content = self.parseSSELine(line) {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Chat Methods

    func generateChat(messages: [ChatMessage]) async throws -> Generation {
        guard serverConnected else {
            throw LLMProviderError.notConfigured(provider: .ollama)
        }

        let request = try buildChatRequest(messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""

        return Generation(content: content)
    }

    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard self.serverConnected else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .ollama))
                        return
                    }

                    let request = try self.buildChatStreamRequest(messages: messages)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if let content = self.parseSSELine(line) {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool Support

    func generateChatWithTools(
        messages: [ChatMessage],
        tools: [ConnectorTool],
        toolRounds: [ToolExecutionRound]
    ) async throws -> ToolEnabledGeneration {
        guard serverConnected else {
            throw LLMProviderError.notConfigured(provider: .ollama)
        }

        let request = try buildToolRequest(messages: messages, tools: tools, toolRounds: toolRounds)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        return try parseToolResponse(data)
    }

    // MARK: - Connection & Model Discovery

    /// Check if Ollama server is running
    @discardableResult
    func checkConnection() async -> Bool {
        let urlString = "\(baseURL)/api/version"

        guard let url = URL(string: urlString) else {
            serverConnected = false
            return false
        }

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                serverConnected = true
                print("✅ Ollama server connected at \(baseURL)")
                // Fetch available models
                await fetchAvailableModels()
                return true
            }
        } catch {
            print("⚠️ Ollama server not available: \(error.localizedDescription)")
        }
        serverConnected = false
        // Clear the "Loading..." placeholder when server is unavailable
        if currentModel.id == "pending" {
            currentModel = LLMModel(id: "unavailable", name: "Unavailable", description: "Server not running")
        }
        return false
    }

    /// Fetch available models from Ollama server
    func fetchAvailableModels() async {
        do {
            let url = URL(string: "\(baseURL)/api/tags")!
            let (data, _) = try await session.data(from: url)
            let result = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)

            availableModelsFromServer = result.models.map { model in
                LLMModel(
                    id: model.name,
                    name: model.name,
                    description: model.details?.parameter_size ?? "Local model"
                )
            }

            // Restore saved model or set first available
            let savedModelId = UserDefaults.standard.string(forKey: "ollama_model")
            if let savedModelId = savedModelId,
               let savedModel = availableModelsFromServer.first(where: { $0.id == savedModelId }) {
                currentModel = savedModel
            } else if let firstModel = availableModelsFromServer.first {
                currentModel = firstModel
                UserDefaults.standard.set(firstModel.id, forKey: "ollama_model")
            }

            print("✅ Ollama models loaded: \(availableModelsFromServer.map { $0.id }), current: \(currentModel.id)")
        } catch {
            print("⚠️ Failed to fetch Ollama models: \(error.localizedDescription)")
            availableModelsFromServer = []
        }
    }

    // MARK: - Private Methods

    /// Build a non-streaming request
    private func buildRequest(prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming request with stream: true
    /// Ollama uses OpenAI-compatible API format
    private func buildStreamRequest(prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": [["role": "user", "content": prompt]],
            "stream": true  // Enable SSE streaming
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a non-streaming chat request with messages array
    private func buildChatRequest(messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formattedMessages = PromptBuilder.shared.formatChatMessages(messages: messages)
        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming chat request with messages array
    private func buildChatStreamRequest(messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formattedMessages = PromptBuilder.shared.formatChatMessages(messages: messages)
        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse a Server-Sent Events (SSE) line from Ollama streaming response
    /// Ollama uses OpenAI-compatible format:
    ///   data: {"id":"...","choices":[{"delta":{"content":"Hello"}}]}
    ///   data: [DONE]
    private func parseSSELine(_ line: String) -> String? {
        // Skip empty lines and non-data lines
        guard line.hasPrefix("data: ") else { return nil }

        // Remove "data: " prefix
        let jsonString = String(line.dropFirst(6))

        // Check for stream termination
        if jsonString == "[DONE]" {
            return nil
        }

        // Parse JSON and extract content delta
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }

        return content
    }

    private func handleStatusCode(_ code: Int, data: Data) throws {
        switch code {
        case 200...299: return
        case 404:
            throw LLMProviderError.unknown("Model '\(currentModel.id)' not found. Run: ollama pull \(currentModel.id)")
        default:
            let message = String(data: data, encoding: .utf8)
            throw LLMProviderError.serverError(statusCode: code, message: message)
        }
    }

    // MARK: - Tool Request Building

    /// Build a request with tools (OpenAI-compatible format)
    private func buildToolRequest(
        messages: [ChatMessage],
        tools: [ConnectorTool],
        toolRounds: [ToolExecutionRound]
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format chat messages - cast to [String: Any] for tool result compatibility
        var formattedMessages: [[String: Any]] = PromptBuilder.shared.formatChatMessages(messages: messages).map { $0 as [String: Any] }

        // Append all tool execution rounds to build complete conversation history
        // OpenAI-compatible format requires: user message -> assistant message with tool_calls -> tool messages (for each round)
        for round in toolRounds {
            // Add assistant message with tool_calls
            let toolCallsFormatted: [[String: Any]] = round.toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": (try? JSONSerialization.data(withJSONObject: call.arguments))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    ] as [String: Any]
                ]
            }
            formattedMessages.append([
                "role": "assistant",
                "tool_calls": toolCallsFormatted
            ])

            // Append tool results as tool role messages
            for result in round.results {
                formattedMessages.append(ToolSchemaConverter.formatOpenAIToolResult(callID: result.callID, result: result))
            }
        }

        var body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "stream": false
        ]

        // Add tools if available
        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toOpenAI(tools: tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse a tool-enabled response (OpenAI-compatible format)
    private func parseToolResponse(_ data: Data) throws -> ToolEnabledGeneration {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }

        // Extract text content
        let content = message["content"] as? String

        // Extract tool calls
        var toolCalls: [LLMToolCall] = []
        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in rawToolCalls {
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String else {
                    continue
                }

                // Parse arguments JSON string
                var arguments: [String: Any] = [:]
                if let argsString = function["arguments"] as? String,
                   let argsData = argsString.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                    arguments = argsDict
                }

                toolCalls.append(LLMToolCall(id: id, name: name, arguments: arguments))
            }
        }

        return ToolEnabledGeneration(content: content, toolCalls: toolCalls)
    }
}

// MARK: - Response Models

/// OpenAI-compatible response from Ollama
private struct OllamaResponse: Codable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }

    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
    }
}

/// Response from /api/tags endpoint
private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]

    struct OllamaModel: Codable {
        let name: String
        let model: String?
        let modified_at: String?
        let size: Int?
        let digest: String?
        let details: Details?

        struct Details: Codable {
            let parameter_size: String?
            let quantization_level: String?
        }
    }
}
