// MARK: - Anthropic Provider
// Claude integration via Anthropic API

import Foundation

/// Anthropic Claude provider implementation
@MainActor
final class AnthropicProvider: LLMProvider {

    // MARK: - Properties

    let providerType: LLMProviderType = .anthropic
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private var apiKey: String?
    private let session: URLSession
    private(set) var currentModel: LLMModel

    var isConfigured: Bool { apiKey != nil && !apiKey!.isEmpty }

    // MARK: - Initialization

    init(model: LLMModel? = nil) {
        self.currentModel = model ?? LLMProviderType.anthropic.defaultModel
        self.session = URLSession.shared

        // Try to load API key from keychain
        self.apiKey = try? KeychainHelper.shared.retrieveAPIKey(for: .anthropic)

        // Try to load saved model
        if let savedModelId = UserDefaults.standard.string(forKey: "anthropic_model"),
           let savedModel = LLMProviderType.anthropic.availableModels.first(where: { $0.id == savedModelId }) {
            self.currentModel = savedModel
        }
    }

    // MARK: - LLMProvider Protocol

    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw LLMProviderError.invalidAPIKey
        }
        self.apiKey = apiKey
    }

    func setModel(_ model: LLMModel) {
        self.currentModel = model
        UserDefaults.standard.set(model.id, forKey: "anthropic_model")
        print("✅ Anthropic model set to: \(model.name)")
    }

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .anthropic)
        }

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = result.content.first?.text ?? ""

        return Generation(content: content)
    }

    /// Stream from a raw prompt (already built, no additional processing)
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .anthropic))
                        return
                    }

                    let request = try self.buildStreamRequest(apiKey: apiKey, prompt: prompt)

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
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .anthropic)
        }

        let request = try buildChatRequest(apiKey: apiKey, messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = result.content.first?.text ?? ""

        return Generation(content: content)
    }

    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .anthropic))
                        return
                    }

                    let request = try self.buildChatStreamRequest(apiKey: apiKey, messages: messages)
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
        tools: [ConnectorTool]
    ) async throws -> ToolEnabledGeneration {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .anthropic)
        }

        let request = try buildToolRequest(apiKey: apiKey, messages: messages, tools: tools)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        return try parseToolResponse(data)
    }

    func generateChatWithToolsStream(
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        throw LLMProviderError.notConfigured(provider: .anthropic)
                    }

                    let request = try self.buildToolStreamRequest(
                        apiKey: apiKey,
                        messages: messages,
                        tools: tools
                    )

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMProviderError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Parse SSE stream - Anthropic format
                    var toolCalls: [LLMToolCall] = []
                    var currentToolId: String?
                    var currentToolName: String?
                    var currentToolInput: String = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        // Parse Anthropic SSE line
                        if let result = self.parseToolStreamSSELine(line) {
                            switch result {
                            case .text(let text):
                                continuation.yield(.textChunk(text))
                            case .toolUseStart(let id, let name):
                                currentToolId = id
                                currentToolName = name
                                currentToolInput = ""
                            case .toolInputDelta(let delta):
                                currentToolInput += delta
                            case .toolUseEnd:
                                if let id = currentToolId, let name = currentToolName {
                                    var arguments: [String: Any] = [:]
                                    if let data = currentToolInput.data(using: .utf8),
                                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        arguments = dict
                                    }
                                    toolCalls.append(LLMToolCall(id: id, name: name, arguments: arguments))
                                }
                                currentToolId = nil
                                currentToolName = nil
                                currentToolInput = ""
                            case .done:
                                break
                            }
                        }
                    }

                    continuation.yield(.complete(toolCalls: toolCalls))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Build a non-streaming request
    private func buildRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming request with stream: true
    private func buildStreamRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]],
            "stream": true  // Enable SSE streaming
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a non-streaming chat request with messages array
    /// Anthropic uses a separate system parameter instead of a system message in the array
    private func buildChatRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use formatChatMessages() which handles context formatting
        let allMessages = PromptBuilder.shared.formatChatMessages(messages: messages)

        // Extract system prompt for Anthropic's separate system parameter
        let systemPrompt = allMessages.first { $0["role"] == "system" }?["content"] ?? ""

        // Filter to non-system messages (already formatted with context)
        let anthropicMessages = allMessages.filter { $0["role"] != "system" }

        let body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": anthropicMessages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming chat request with messages array
    private func buildChatStreamRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use formatChatMessages() which handles context formatting
        let allMessages = PromptBuilder.shared.formatChatMessages(messages: messages)

        // Extract system prompt for Anthropic's separate system parameter
        let systemPrompt = allMessages.first { $0["role"] == "system" }?["content"] ?? ""

        // Filter to non-system messages (already formatted with context)
        let anthropicMessages = allMessages.filter { $0["role"] != "system" }

        let body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": anthropicMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse a Server-Sent Events (SSE) line from Anthropic streaming response
    /// Anthropic format:
    ///   event: content_block_delta
    ///   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
    ///
    /// We only care about content_block_delta events with text_delta
    private func parseSSELine(_ line: String) -> String? {
        // Skip empty lines, event lines, and non-data lines
        guard line.hasPrefix("data: ") else { return nil }

        // Remove "data: " prefix
        let jsonString = String(line.dropFirst(6))

        // Parse JSON and extract text delta
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String,
              deltaType == "text_delta",
              let text = delta["text"] as? String else {
            return nil
        }

        return text
    }

    private func handleStatusCode(_ code: Int, data: Data) throws {
        switch code {
        case 200...299: return
        case 401: throw LLMProviderError.invalidAPIKey
        case 429:
            throw LLMProviderError.rateLimitExceeded(retryAfter: nil)
        default:
            let message = String(data: data, encoding: .utf8)
            throw LLMProviderError.serverError(statusCode: code, message: message)
        }
    }

    // MARK: - Tool Request Building

    /// Build a request with tools
    private func buildToolRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format messages with inline tool round expansion
        let (systemPrompt, anthropicMessages) = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": anthropicMessages
        ]

        // Add tools if available
        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toAnthropic(tools: tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Format messages with tool rounds expanded inline in correct chronological order
    /// - Parameter messages: Chat messages (may contain tool rounds in assistant messages)
    /// - Returns: Tuple of (system prompt, formatted messages array) for Anthropic API
    private func formatMessagesWithToolRounds(messages: [ChatMessage]) -> (systemPrompt: String, messages: [[String: Any]]) {
        var result: [[String: Any]] = []
        let systemPrompt = PromptBuilder.shared.buildSystemPrompt()

        // Process messages in chronological order
        for message in messages {
            switch message.role {
            case .user:
                let formattedContent = PromptBuilder.shared.formatUserMessageWithContext(
                    message.content,
                    context: message.context,
                    intent: message.intent
                )
                result.append(["role": "user", "content": formattedContent])

            case .assistant:
                if let toolRounds = message.toolRounds, !toolRounds.isEmpty {
                    // Expand tool rounds inline for Anthropic format
                    // Each round: assistantResponse (optional) → tool_use → tool_result
                    for record in toolRounds {
                        // Add partial text BEFORE tool_use (if any)
                        if let response = record.assistantResponse, !response.isEmpty {
                            result.append(["role": "assistant", "content": response])
                        }

                        let toolUseBlocks: [[String: Any]] = record.toolCalls.map { call in
                            var args: [String: Any] = [:]
                            if let data = call.argumentsJSON.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                args = dict
                            }
                            return [
                                "type": "tool_use",
                                "id": call.id,
                                "name": call.toolName,
                                "input": args
                            ]
                        }
                        result.append(["role": "assistant", "content": toolUseBlocks])

                        let toolResultBlocks: [[String: Any]] = record.results.map { resultRecord in
                            [
                                "type": "tool_result",
                                "tool_use_id": resultRecord.callID,
                                "content": resultRecord.content,
                                "is_error": !resultRecord.isSuccess
                            ] as [String: Any]
                        }
                        result.append(["role": "user", "content": toolResultBlocks])
                    }

                    // Add final response AFTER all tool rounds (the LLM's response when no more tools were called)
                    if !message.content.isEmpty {
                        result.append(["role": "assistant", "content": message.content])
                    }
                } else {
                    result.append(["role": "assistant", "content": message.content])
                }

            case .system:
                // Anthropic uses separate system parameter, skip inline system messages
                break
            }
        }

        return (systemPrompt, result)
    }

    /// Parse a tool-enabled response
    private func parseToolResponse(_ data: Data) throws -> ToolEnabledGeneration {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw LLMProviderError.invalidResponse
        }

        // Extract text content and tool use blocks
        var textContent: String?
        var toolCalls: [LLMToolCall] = []

        for block in content {
            guard let type = block["type"] as? String else { continue }

            switch type {
            case "text":
                if let text = block["text"] as? String {
                    textContent = text
                }
            case "tool_use":
                if let id = block["id"] as? String,
                   let name = block["name"] as? String,
                   let input = block["input"] as? [String: Any] {
                    toolCalls.append(LLMToolCall(id: id, name: name, arguments: input))
                }
            default:
                continue
            }
        }

        return ToolEnabledGeneration(content: textContent, toolCalls: toolCalls)
    }

    /// Build a streaming request with tools
    private func buildToolStreamRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use shared method for correct chronological message ordering
        let (systemPrompt, anthropicMessages) = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "model": currentModel.id,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": anthropicMessages,
            "stream": true
        ]

        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toAnthropic(tools: tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Result from parsing an Anthropic tool stream SSE line
    private enum ToolStreamSSEResult {
        case text(String)
        case toolUseStart(id: String, name: String)
        case toolInputDelta(String)
        case toolUseEnd
        case done
    }

    /// Parse an SSE line from Anthropic streaming tool response
    private func parseToolStreamSSELine(_ line: String) -> ToolStreamSSEResult? {
        guard line.hasPrefix("data: ") else { return nil }

        let jsonString = String(line.dropFirst(6))

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String {
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    return .text(text)
                } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                    return .toolInputDelta(partial)
                }
            }
        case "content_block_start":
            if let contentBlock = json["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String,
               blockType == "tool_use",
               let id = contentBlock["id"] as? String,
               let name = contentBlock["name"] as? String {
                return .toolUseStart(id: id, name: name)
            }
        case "content_block_stop":
            return .toolUseEnd
        case "message_stop":
            return .done
        default:
            break
        }

        return nil
    }
}

// MARK: - Response Models

private struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    let usage: Usage?
    
    struct ContentBlock: Codable {
        let text: String
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

