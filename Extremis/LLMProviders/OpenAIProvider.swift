// MARK: - OpenAI Provider
// ChatGPT integration via OpenAI API

import Foundation

/// OpenAI ChatGPT provider implementation
@MainActor
final class OpenAIProvider: LLMProvider {

    // MARK: - Properties

    let providerType: LLMProviderType = .openai
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private var apiKey: String?
    private let session: URLSession
    private(set) var currentModel: LLMModel

    var isConfigured: Bool { apiKey != nil && !apiKey!.isEmpty }

    // MARK: - Initialization

    init(model: LLMModel? = nil) {
        self.currentModel = model ?? LLMProviderType.openai.defaultModel
        self.session = URLSession.shared

        // Try to load API key from keychain
        self.apiKey = try? KeychainHelper.shared.retrieveAPIKey(for: .openai)

        // Try to load saved model
        if let savedModelId = UserDefaults.standard.string(forKey: "openai_model"),
           let savedModel = LLMProviderType.openai.availableModels.first(where: { $0.id == savedModelId }) {
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
        UserDefaults.standard.set(model.id, forKey: "openai_model")
        print("✅ OpenAI model set to: \(model.name)")
    }

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .openai)
        }

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""

        return Generation(content: content)
    }

    /// Stream from a raw prompt (already built, no additional processing)
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .openai))
                        return
                    }

                    let request = try self.buildStreamRequest(apiKey: apiKey, prompt: prompt)

                    // Use bytes(for:) for SSE streaming
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    // Check for HTTP errors before streaming
                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Parse SSE stream
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
            throw LLMProviderError.notConfigured(provider: .openai)
        }

        let request = try buildChatRequest(apiKey: apiKey, messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""

        return Generation(content: content)
    }

    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .openai))
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
            throw LLMProviderError.notConfigured(provider: .openai)
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
                        throw LLMProviderError.notConfigured(provider: .openai)
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

                    // Parse SSE stream - OpenAI format
                    // Use bytes.lines for proper UTF-8 decoding
                    var toolCallsAccumulator: [String: (name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if let result = self.parseToolStreamSSELine(
                            line,
                            toolCallsAccumulator: &toolCallsAccumulator
                        ) {
                            switch result {
                            case .text(let text):
                                continuation.yield(.textChunk(text))
                            case .done:
                                break
                            }
                        }
                    }

                    // Build final tool calls from accumulator
                    let finalToolCalls: [LLMToolCall] = toolCallsAccumulator.map { (id, data) in
                        var arguments: [String: Any] = [:]
                        if let argsData = data.arguments.data(using: .utf8),
                           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                            arguments = argsDict
                        }
                        return LLMToolCall(id: id, name: data.name, arguments: arguments)
                    }

                    continuation.yield(.complete(toolCalls: finalToolCalls))
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
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming request with stream: true
    private func buildStreamRequest(apiKey: String, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 2048,
            "stream": true  // Enable SSE streaming
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a non-streaming chat request with messages array
    private func buildChatRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formattedMessages = Self.formatMessagesForAPI(messages: messages)
        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming chat request with messages array
    private func buildChatStreamRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formattedMessages = Self.formatMessagesForAPI(messages: messages)
        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "max_tokens": 2048,
            "stream": true
        ]

        // Log request details for debugging
        print("📤 OpenAI Chat Request:")
        print("   Model: \(currentModel.id)")
        print("   Messages: \(formattedMessages.count)")
        for (i, msg) in formattedMessages.enumerated() {
            let role = msg["role"] as? String ?? "unknown"
            let content = (msg["content"] as? String)?.prefix(80) ?? "<no content>"
            print("   [\(i)] \(role): \(content)...")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse a Server-Sent Events (SSE) line from OpenAI streaming response
    /// Format: data: {"id":"...","choices":[{"delta":{"content":"Hello"}}]}
    /// Termination: data: [DONE]
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
        case 401: throw LLMProviderError.invalidAPIKey
        case 429:
            let retryAfter = parseRetryAfter(from: data)
            throw LLMProviderError.rateLimitExceeded(retryAfter: retryAfter)
        default:
            let message = String(data: data, encoding: .utf8)
            throw LLMProviderError.serverError(statusCode: code, message: message)
        }
    }
    
    private func parseRetryAfter(from data: Data) -> TimeInterval? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           let range = message.range(of: "try again in "),
           let seconds = Double(message[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." })) {
            return seconds
        }
        return nil
    }

    // MARK: - Tool Request Building

    /// Build a request with tools
    private func buildToolRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format messages with inline tool round expansion
        // Tool rounds are stored in ChatMessage.toolRounds (both historical and current-generation)
        let formattedMessages = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "max_tokens": 4096
        ]

        // Add tools if available
        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toOpenAI(tools: tools)
        }

        // Log request details for debugging
        print("📤 OpenAI Request (non-streaming):")
        print("   Model: \(currentModel.id)")
        print("   Messages: \(formattedMessages.count)")
        for (i, msg) in formattedMessages.enumerated() {
            let role = msg["role"] as? String ?? "unknown"
            if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
                let toolNames = toolCalls.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
                print("   [\(i)] \(role): tool_calls=[\(toolNames.joined(separator: ", "))]")
            } else if role == "tool" {
                let callID = msg["tool_call_id"] as? String ?? "?"
                print("   [\(i)] \(role): result for \(callID)")
            } else {
                let content = (msg["content"] as? String)?.prefix(80) ?? "<no content>"
                print("   [\(i)] \(role): \(content)...")
            }
        }
        if !tools.isEmpty {
            print("   Tools: \(tools.count) available")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Format messages with tool rounds expanded inline in correct chronological order
    /// - Parameter messages: Chat messages (may contain tool rounds in assistant messages)
    /// - Returns: Formatted messages array for OpenAI API
    private func formatMessagesWithToolRounds(messages: [ChatMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        // Add system prompt
        let systemPrompt = PromptBuilder.shared.buildSystemPrompt()
        result.append(["role": "system", "content": systemPrompt])

        // Process messages in chronological order
        for message in messages {
            switch message.role {
            case .user:
                // Format user message with context
                let formattedContent = PromptBuilder.shared.formatUserMessageWithContext(
                    message.content,
                    context: message.context,
                    intent: message.intent
                )
                result.append(Self.buildOpenAIUserMessage(
                    content: formattedContent,
                    attachments: message.attachments
                ))

            case .assistant:
                if let toolRounds = message.toolRounds, !toolRounds.isEmpty {
                    // Expand tool rounds inline
                    // Each round: assistantResponse (optional) → tool_calls → tool results
                    for record in toolRounds {
                        // Add partial text BEFORE tool_calls (if any)
                        if let response = record.assistantResponse, !response.isEmpty {
                            result.append(["role": "assistant", "content": response])
                        }

                        let toolCallsFormatted: [[String: Any]] = record.toolCalls.map { call in
                            var args: [String: Any] = [:]
                            if let data = call.argumentsJSON.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                args = dict
                            }
                            return [
                                "id": call.id,
                                "type": "function",
                                "function": [
                                    "name": call.toolName,
                                    "arguments": (try? JSONSerialization.data(withJSONObject: args))
                                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                ] as [String: Any]
                            ]
                        }
                        result.append(["role": "assistant", "tool_calls": toolCallsFormatted])

                        for resultRecord in record.results {
                            let content = resultRecord.isSuccess ? resultRecord.content : "Error: \(resultRecord.content)"
                            result.append([
                                "role": "tool",
                                "tool_call_id": resultRecord.callID,
                                "content": content
                            ])
                        }
                    }

                    // Add final response AFTER all tool rounds (the LLM's response when no more tools were called)
                    if !message.content.isEmpty {
                        result.append(["role": "assistant", "content": message.content])
                    }
                } else {
                    // Regular assistant message (no tools)
                    result.append(["role": "assistant", "content": message.content])
                }

            case .system:
                // Additional system messages (rare)
                result.append(["role": "system", "content": message.content])
            }
        }

        return result
    }

    /// Parse a tool-enabled response
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

    /// Build a streaming request with tools
    private func buildToolStreamRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use shared formatting with inline tool round expansion
        let formattedMessages = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "max_tokens": 4096,
            "stream": true
        ]

        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toOpenAI(tools: tools)
        }

        // Log request details for debugging
        print("📤 OpenAI Request:")
        print("   Model: \(currentModel.id)")
        print("   Messages: \(formattedMessages.count)")
        for (i, msg) in formattedMessages.enumerated() {
            let role = msg["role"] as? String ?? "unknown"
            if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
                let toolNames = toolCalls.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
                print("   [\(i)] \(role): tool_calls=[\(toolNames.joined(separator: ", "))]")
            } else if role == "tool" {
                let callID = msg["tool_call_id"] as? String ?? "?"
                print("   [\(i)] \(role): result for \(callID)")
            } else {
                let content = (msg["content"] as? String)?.prefix(80) ?? "<no content>"
                print("   [\(i)] \(role): \(content)...")
            }
        }
        if !tools.isEmpty {
            print("   Tools: \(tools.count) available")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Result from parsing a tool stream SSE line
    private enum ToolStreamSSEResult {
        case text(String)
        case done
    }

    /// Parse an SSE line from streaming tool response (OpenAI format)
    private func parseToolStreamSSELine(
        _ line: String,
        toolCallsAccumulator: inout [String: (name: String, arguments: String)]
    ) -> ToolStreamSSEResult? {
        guard line.hasPrefix("data: ") else { return nil }

        let jsonString = String(line.dropFirst(6))

        if jsonString == "[DONE]" {
            return .done
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return nil
        }

        // Check for text content
        if let content = delta["content"] as? String, !content.isEmpty {
            return .text(content)
        }

        // Check for tool calls
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for toolCall in toolCalls {
                guard let index = toolCall["index"] as? Int else { continue }
                let id = toolCall["id"] as? String ?? "tool_\(index)"

                if toolCallsAccumulator[id] == nil {
                    if let function = toolCall["function"] as? [String: Any],
                       let name = function["name"] as? String {
                        toolCallsAccumulator[id] = (name: name, arguments: "")
                    }
                }

                if let function = toolCall["function"] as? [String: Any],
                   let argsChunk = function["arguments"] as? String,
                   var existing = toolCallsAccumulator[id] {
                    existing.arguments += argsChunk
                    toolCallsAccumulator[id] = existing
                }
            }
        }

        return nil
    }
    // MARK: - Multimodal Helpers

    /// Build an OpenAI-format user message, optionally with image content blocks
    static func buildOpenAIUserMessage(content: String, attachments: [MessageAttachment]?) -> [String: Any] {
        guard let attachments = attachments, !attachments.isEmpty else {
            return ["role": "user", "content": content]
        }

        var contentParts: [[String: Any]] = [
            ["type": "text", "text": content]
        ]

        for attachment in attachments {
            if case .image(let img) = attachment {
                contentParts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(img.mediaType.rawValue);base64,\(img.base64Data)"
                    ]
                ])
            }
        }

        return ["role": "user", "content": contentParts] as [String: Any]
    }

    /// Format messages for non-tool chat paths (with multimodal support)
    static func formatMessagesForAPI(messages: [ChatMessage]) -> [[String: Any]] {
        let formatted = PromptBuilder.shared.formatChatMessagesWithAttachments(messages: messages)
        return formatted.map { msg in
            if msg.role == "user" {
                return buildOpenAIUserMessage(content: msg.content, attachments: msg.attachments)
            }
            return ["role": msg.role, "content": msg.content] as [String: Any]
        }
    }
}

// MARK: - Response Models

private struct OpenAIResponse: Codable {
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

