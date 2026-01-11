// MARK: - OpenAI Provider
// ChatGPT integration via OpenAI API

import Foundation

/// OpenAI ChatGPT provider implementation
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
    
    func generate(instruction: String, context: Context) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .openai)
        }
        
        let startTime = Date()
        let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        try handleStatusCode(httpResponse.statusCode, data: data)
        
        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        return Generation(
            instructionId: UUID(), // Will be set by caller
            provider: .openai,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.prompt_tokens ?? 0,
                completionTokens: result.usage?.completion_tokens ?? 0
            ),
            latencyMs: latencyMs
        )
    }
    
    func generateStream(instruction: String, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .openai))
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
                        // Collect error response
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        // Check for cancellation
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        // Parse the SSE line and extract content
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
            throw LLMProviderError.notConfigured(provider: .openai)
        }

        let startTime = Date()
        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .openai,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.prompt_tokens ?? 0,
                completionTokens: result.usage?.completion_tokens ?? 0
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

        let startTime = Date()
        let request = try buildChatRequest(apiKey: apiKey, messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = result.choices.first?.message.content ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .openai,
            content: content,
            tokenUsage: TokenUsage(
                promptTokens: result.usage?.prompt_tokens ?? 0,
                completionTokens: result.usage?.completion_tokens ?? 0
            ),
            latencyMs: latencyMs
        )
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

        let formattedMessages = PromptBuilder.shared.formatChatMessages(messages: messages)
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

        let formattedMessages = PromptBuilder.shared.formatChatMessages(messages: messages)
        let body: [String: Any] = [
            "model": currentModel.id,
            "messages": formattedMessages,
            "max_tokens": 2048,
            "stream": true
        ]
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

