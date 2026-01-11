// MARK: - Anthropic Provider
// Claude integration via Anthropic API

import Foundation

/// Anthropic Claude provider implementation
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
    
    func generate(instruction: String, context: Context) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .anthropic)
        }
        
        let startTime = Date()
        let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        try handleStatusCode(httpResponse.statusCode, data: data)
        
        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = result.content.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        return Generation(
            instructionId: UUID(),
            provider: .anthropic,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.input_tokens ?? 0,
                completionTokens: result.usage?.output_tokens ?? 0
            ),
            latencyMs: latencyMs
        )
    }
    
    func generateStream(instruction: String, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .anthropic))
                        return
                    }

                    let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)
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

                    // Parse SSE stream - Anthropic format
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

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .anthropic)
        }

        let startTime = Date()
        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = result.content.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .anthropic,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.input_tokens ?? 0,
                completionTokens: result.usage?.output_tokens ?? 0
            ),
            latencyMs: latencyMs
        )
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

        let startTime = Date()
        let request = try buildChatRequest(apiKey: apiKey, messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = result.content.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .anthropic,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.input_tokens ?? 0,
                completionTokens: result.usage?.output_tokens ?? 0
            ),
            latencyMs: latencyMs
        )
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

