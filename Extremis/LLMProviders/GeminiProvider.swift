// MARK: - Gemini Provider
// Google Gemini integration via Generative Language API

import Foundation

/// Google Gemini provider implementation
final class GeminiProvider: LLMProvider {

    // MARK: - Properties

    let providerType: LLMProviderType = .gemini
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private var apiKey: String?
    private let session: URLSession
    private(set) var currentModel: LLMModel

    var isConfigured: Bool { apiKey != nil && !apiKey!.isEmpty }

    // MARK: - Initialization

    init(model: LLMModel? = nil) {
        self.currentModel = model ?? LLMProviderType.gemini.defaultModel
        self.session = URLSession.shared

        // Try to load API key from keychain
        self.apiKey = try? KeychainHelper.shared.retrieveAPIKey(for: .gemini)

        // Log API key status
        if self.apiKey != nil {
            print("🔑 GeminiProvider: API key loaded from keychain")
        } else {
            print("⚠️ GeminiProvider: No API key found in keychain")
        }

        // Try to load saved model
        if let savedModelId = UserDefaults.standard.string(forKey: "gemini_model"),
           let savedModel = LLMProviderType.gemini.availableModels.first(where: { $0.id == savedModelId }) {
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
        UserDefaults.standard.set(model.id, forKey: "gemini_model")
        print("✅ Gemini model set to: \(model.name)")
    }
    
    func generate(instruction: String, context: Context) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .gemini)
        }
        
        let startTime = Date()
        let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)
        print("📋 PromptBuilder: context = \(context)")
        print("📋 PromptBuilder: prompt = \(prompt)")

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }
        
        try handleStatusCode(httpResponse.statusCode, data: data)
        
        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = result.candidates?.first?.content.parts.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Gemini doesn't return token counts in the same way
        return Generation(
            instructionId: UUID(),
            provider: .gemini,
            content: content,
            tokenUsage: result.usageMetadata.map {
                TokenUsage(
                    promptTokens: $0.promptTokenCount ?? 0,
                    completionTokens: $0.candidatesTokenCount ?? 0
                )
            },
            latencyMs: latencyMs
        )
    }
    
    func generateStream(instruction: String, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        print("❌ GeminiProvider: No API key configured")
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
                        return
                    }

                    let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)
                    print("🚀 GeminiProvider: Starting stream for instruction: \(instruction.prefix(50))...")
                    let request = try self.buildStreamRequest(apiKey: apiKey, prompt: prompt)

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ GeminiProvider: Invalid response type")
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    print("📥 GeminiProvider: HTTP status code: \(httpResponse.statusCode)")

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let errorString = String(data: errorData, encoding: .utf8) ?? "unknown"
                        print("❌ GeminiProvider: Error response: \(errorString)")
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Stream JSON objects as they complete
                    for try await text in self.streamJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            print("⏹️ GeminiProvider: Task cancelled")
                            continuation.finish()
                            return
                        }
                        continuation.yield(text)
                    }

                    print("✅ GeminiProvider: Stream finished")
                    continuation.finish()
                } catch {
                    print("❌ GeminiProvider: Error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .gemini)
        }

        let startTime = Date()
        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = result.candidates?.first?.content.parts.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .gemini,
            content: content,
            tokenUsage: result.usageMetadata.map {
                TokenUsage(
                    promptTokens: $0.promptTokenCount ?? 0,
                    completionTokens: $0.candidatesTokenCount ?? 0
                )
            },
            latencyMs: latencyMs
        )
    }

    /// Stream from a raw prompt (already built, no additional processing)
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        print("❌ GeminiProvider (raw): No API key configured")
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
                        return
                    }

                    print("🚀 GeminiProvider (raw): Starting stream for prompt (\(prompt.count) chars)")
                    let request = try self.buildStreamRequest(apiKey: apiKey, prompt: prompt)

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ GeminiProvider (raw): Invalid response type")
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    print("📥 GeminiProvider (raw): HTTP status code: \(httpResponse.statusCode)")

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let errorString = String(data: errorData, encoding: .utf8) ?? "unknown"
                        print("❌ GeminiProvider (raw): Error response: \(errorString)")
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Stream JSON objects as they complete
                    for try await text in self.streamJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            print("⏹️ GeminiProvider (raw): Task cancelled")
                            continuation.finish()
                            return
                        }
                        continuation.yield(text)
                    }

                    print("✅ GeminiProvider (raw): Stream finished")
                    continuation.finish()
                } catch {
                    print("❌ GeminiProvider (raw): Error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Chat Methods

    func generateChat(messages: [ChatMessage], context: Context?) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .gemini)
        }

        let startTime = Date()
        let request = try buildChatRequest(apiKey: apiKey, messages: messages, context: context)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = result.candidates?.first?.content.parts.first?.text ?? ""
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        return Generation(
            instructionId: UUID(),
            provider: .gemini,
            content: content,
            tokenUsage: result.usageMetadata.map {
                TokenUsage(
                    promptTokens: $0.promptTokenCount ?? 0,
                    completionTokens: $0.candidatesTokenCount ?? 0
                )
            },
            latencyMs: latencyMs
        )
    }

    func generateChatStream(messages: [ChatMessage], context: Context?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        print("❌ GeminiProvider: No API key configured")
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
                        return
                    }

                    print("🚀 GeminiProvider: Starting chat stream with \(messages.count) messages")
                    let request = try self.buildChatStreamRequest(apiKey: apiKey, messages: messages, context: context)

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ GeminiProvider: Invalid response type")
                        continuation.finish(throwing: LLMProviderError.invalidResponse)
                        return
                    }

                    print("📥 GeminiProvider: HTTP status code: \(httpResponse.statusCode)")

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let errorString = String(data: errorData, encoding: .utf8) ?? "unknown"
                        print("❌ GeminiProvider: Error response: \(errorString)")
                        try self.handleStatusCode(httpResponse.statusCode, data: errorData)
                    }

                    // Stream JSON objects as they complete
                    for try await text in self.streamJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            print("⏹️ GeminiProvider: Task cancelled")
                            continuation.finish()
                            return
                        }
                        continuation.yield(text)
                    }

                    print("✅ GeminiProvider: Stream finished")
                    continuation.finish()
                } catch {
                    print("❌ GeminiProvider: Error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Build a non-streaming request
    private func buildRequest(apiKey: String, prompt: String) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming request using streamGenerateContent endpoint
    private func buildStreamRequest(apiKey: String, prompt: String) throws -> URLRequest {
        // Gemini uses a different endpoint for streaming: streamGenerateContent instead of generateContent
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):streamGenerateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a non-streaming chat request with messages array
    /// Gemini uses a different format: contents array with role and parts
    private func buildChatRequest(apiKey: String, messages: [ChatMessage], context: Context?) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = formatMessagesForGemini(messages: messages, context: context)
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming chat request with messages array
    private func buildChatStreamRequest(apiKey: String, messages: [ChatMessage], context: Context?) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):streamGenerateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = formatMessagesForGemini(messages: messages, context: context)
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Format messages for Gemini API
    /// Gemini uses "user" and "model" roles, and system messages are prepended to first user message
    private func formatMessagesForGemini(messages: [ChatMessage], context: Context?) -> [[String: Any]] {
        var contents: [[String: Any]] = []

        // Build system prompt
        let systemPrompt = PromptBuilder.shared.buildChatSystemPrompt(context: context)
        var systemPrepended = false

        for message in messages {
            // Skip system messages - we'll prepend to first user message
            if message.role == .system {
                continue
            }

            // Map roles: user -> user, assistant -> model
            let geminiRole = message.role == .user ? "user" : "model"
            var content = message.content

            // Prepend system prompt to first user message
            if message.role == .user && !systemPrepended {
                content = systemPrompt + "\n\n" + content
                systemPrepended = true
            }

            contents.append([
                "role": geminiRole,
                "parts": [["text": content]]
            ])
        }

        return contents
    }

    /// Parse a single JSON chunk from Gemini streaming (for incremental parsing)
    private func parseGeminiChunk(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractTextFromCandidate(json)
    }

    /// Parse complete Gemini JSON response (can be array or single object)
    /// Gemini returns pretty-printed JSON, so we accumulate all bytes and parse at once
    private func parseGeminiResponse(_ data: Data) -> String? {
        // Try parsing as array first (streaming response wraps in array)
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Concatenate all text parts from all candidates
            var allText = ""
            for json in jsonArray {
                if let text = extractTextFromCandidate(json) {
                    allText += text
                }
            }
            return allText.isEmpty ? nil : allText
        }

        // Try parsing as single object
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return extractTextFromCandidate(json)
        }

        print("⚠️ GeminiProvider: Could not parse response as JSON")
        return nil
    }

    /// Extract text from a Gemini candidate JSON object
    private func extractTextFromCandidate(_ json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        // Concatenate all text parts
        var text = ""
        for part in parts {
            if let partText = part["text"] as? String {
                text += partText
            }
        }
        return text.isEmpty ? nil : text
    }

    /// Parse a line from Gemini streaming response (NDJSON format)
    /// Note: This is kept for potential future use but Gemini currently returns pretty-printed JSON
    private func parseStreamLine(_ line: String) -> String? {
        // Skip empty lines and array delimiters
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "[" || trimmed == "]" || trimmed == "," {
            return nil
        }

        // Remove leading comma if present (array element separator)
        var jsonString = trimmed
        if jsonString.hasPrefix(",") {
            jsonString = String(jsonString.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Parse JSON and extract text
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return extractTextFromCandidate(json)
    }

    private func handleStatusCode(_ code: Int, data: Data) throws {
        switch code {
        case 200...299: return
        case 400, 403: throw LLMProviderError.invalidAPIKey
        case 429:
            throw LLMProviderError.rateLimitExceeded(retryAfter: nil)
        default:
            let message = String(data: data, encoding: .utf8)
            throw LLMProviderError.serverError(statusCode: code, message: message)
        }
    }

    /// Stream JSON objects from Gemini's pretty-printed response
    /// Detects complete JSON objects by tracking brace depth and yields text from each
    private func streamJsonObjects(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                var braceDepth = 0
                var inString = false
                var escapeNext = false
                var objectStart: Int? = nil

                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        let char = Character(UnicodeScalar(byte))

                        // Track string boundaries to ignore braces inside strings
                        if escapeNext {
                            escapeNext = false
                            continue
                        }
                        if char == "\\" && inString {
                            escapeNext = true
                            continue
                        }
                        if char == "\"" {
                            inString = !inString
                            continue
                        }
                        if inString { continue }

                        // Track object boundaries
                        if char == "{" {
                            if braceDepth == 0 {
                                objectStart = buffer.count - 1
                            }
                            braceDepth += 1
                        } else if char == "}" {
                            braceDepth -= 1
                            if braceDepth == 0, let start = objectStart {
                                // Complete JSON object found
                                let objectData = buffer.subdata(in: start..<buffer.count)
                                if let text = self.parseGeminiChunk(objectData) {
                                    continuation.yield(text)
                                }
                                objectStart = nil
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Response Models

private struct GeminiResponse: Codable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?
    
    struct Candidate: Codable {
        let content: Content
    }
    
    struct Content: Codable {
        let parts: [Part]
    }
    
    struct Part: Codable {
        let text: String
    }
    
    struct UsageMetadata: Codable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}

