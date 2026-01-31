// MARK: - Gemini Provider
// Google Gemini integration via Generative Language API

import Foundation

/// Google Gemini provider implementation
@MainActor
final class GeminiProvider: LLMProvider {

    // MARK: - Properties

    let providerType: LLMProviderType = .gemini
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private var apiKey: String?
    private let session: URLSession
    private(set) var currentModel: LLMModel

    var isConfigured: Bool { apiKey != nil && !apiKey!.isEmpty }

    /// Enable/disable debug logging (set to false in production)
    var debugLogging: Bool = true

    // MARK: - Initialization

    init(model: LLMModel? = nil) {
        self.currentModel = model ?? LLMProviderType.gemini.defaultModel
        self.session = URLSession.shared

        // Try to load API key from keychain
        self.apiKey = try? KeychainHelper.shared.retrieveAPIKey(for: .gemini)

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
    }

    /// Generate from a raw prompt (already built, no additional processing)
    func generateRaw(prompt: String) async throws -> Generation {
        guard let apiKey = apiKey else {
            throw LLMProviderError.notConfigured(provider: .gemini)
        }

        let request = try buildRequest(apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = result.candidates?.first?.content.parts.first?.text ?? ""

        return Generation(content: content)
    }

    /// Stream from a raw prompt (already built, no additional processing)
    func generateRawStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
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

                    // Stream JSON objects as they complete
                    for try await text in self.streamJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(text)
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
            throw LLMProviderError.notConfigured(provider: .gemini)
        }

        let request = try buildChatRequest(apiKey: apiKey, messages: messages)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        try handleStatusCode(httpResponse.statusCode, data: data)

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = result.candidates?.first?.content.parts.first?.text ?? ""

        return Generation(content: content)
    }

    func generateChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = self.apiKey else {
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
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

                    // Stream JSON objects as they complete
                    for try await text in self.streamJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(text)
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
            throw LLMProviderError.notConfigured(provider: .gemini)
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
                        continuation.finish(throwing: LLMProviderError.notConfigured(provider: .gemini))
                        return
                    }

                    let request = try self.buildToolStreamRequest(
                        apiKey: apiKey,
                        messages: messages,
                        tools: tools
                    )

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

                    // Accumulate tool calls as we stream
                    var toolCalls: [LLMToolCall] = []

                    // Stream JSON objects and parse for text content and function calls
                    for try await result in self.streamToolJsonObjects(from: bytes) {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        switch result {
                        case .text(let text):
                            if !text.isEmpty {
                                continuation.yield(.textChunk(text))
                            }
                        case .toolCall(let call):
                            toolCalls.append(call)
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
    private func buildChatRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = formatMessagesForGemini(messages: messages)
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
    private func buildChatStreamRequest(apiKey: String, messages: [ChatMessage]) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):streamGenerateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = formatMessagesForGemini(messages: messages)
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
    private func formatMessagesForGemini(messages: [ChatMessage]) -> [[String: Any]] {
        // Use formatChatMessages() which handles context formatting
        let allMessages = PromptBuilder.shared.formatChatMessages(messages: messages)

        var contents: [[String: Any]] = []
        var systemPrepended = false

        for message in allMessages {
            // Skip system messages - we'll prepend to first user message
            if message["role"] == "system" {
                continue
            }

            // Map roles: user -> user, assistant -> model
            let geminiRole = message["role"] == "user" ? "user" : "model"
            var content = message["content"] ?? ""

            // Prepend system prompt to first user message
            if message["role"] == "user" && !systemPrepended {
                let systemContent = allMessages.first { $0["role"] == "system" }?["content"] ?? ""
                content = systemContent + "\n\n" + content
                systemPrepended = true
            }

            contents.append([
                "role": geminiRole,
                "parts": [["text": content]]
            ])
        }

        logChatMessages(messages: messages, formattedCount: contents.count)
        return contents
    }

    /// Format messages with tool rounds expanded inline in correct chronological order
    /// - Parameters:
    ///   - messages: Chat messages (may contain historical tool rounds in assistant messages)
    ///   - currentToolRounds: Tool rounds from the current generation (appended at end)
    /// - Returns: Formatted contents array for Gemini API
    private func formatMessagesWithToolRounds(
        messages: [ChatMessage]
    ) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        let systemPrompt = PromptBuilder.shared.buildSystemPrompt()
        var systemPrepended = false

        // Process messages in chronological order
        for message in messages {
            switch message.role {
            case .user:
                var formattedContent = PromptBuilder.shared.formatUserMessageWithContext(
                    message.content,
                    context: message.context,
                    intent: message.intent
                )

                // Prepend system prompt to first user message
                if !systemPrepended {
                    formattedContent = systemPrompt + "\n\n" + formattedContent
                    systemPrepended = true
                }

                contents.append([
                    "role": "user",
                    "parts": [["text": formattedContent]]
                ])

            case .assistant:
                if let toolRounds = message.toolRounds, !toolRounds.isEmpty {
                    // Expand tool rounds inline for Gemini format
                    // Each round: assistantResponse (optional) → functionCall → functionResponse
                    for record in toolRounds {
                        // Add partial text BEFORE functionCall (if any)
                        if let response = record.assistantResponse, !response.isEmpty {
                            contents.append([
                                "role": "model",
                                "parts": [["text": response]]
                            ])
                        }

                        let functionCallParts: [[String: Any]] = record.toolCalls.map { call in
                            var args: [String: Any] = [:]
                            if let data = call.argumentsJSON.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                args = dict
                            }
                            return [
                                "functionCall": [
                                    "name": call.toolName,
                                    "args": args
                                ] as [String: Any]
                            ]
                        }
                        contents.append([
                            "role": "model",
                            "parts": functionCallParts
                        ])

                        let functionResponseParts: [[String: Any]] = record.results.map { resultRecord in
                            [
                                "functionResponse": [
                                    "name": resultRecord.toolName,
                                    "response": [
                                        "result": resultRecord.content
                                    ] as [String: Any]
                                ] as [String: Any]
                            ]
                        }
                        contents.append([
                            "role": "function",
                            "parts": functionResponseParts
                        ])
                    }

                    // Add final response AFTER all tool rounds (the LLM's response when no more tools were called)
                    if !message.content.isEmpty {
                        contents.append([
                            "role": "model",
                            "parts": [["text": message.content]]
                        ])
                    }
                } else {
                    contents.append([
                        "role": "model",
                        "parts": [["text": message.content]]
                    ])
                }

            case .system:
                // Gemini doesn't support system role - prepend to first user message (handled above)
                break
            }
        }

        return contents
    }

    /// Log chat messages (controlled by debugLogging flag)
    private func logChatMessages(messages: [ChatMessage], formattedCount: Int) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "-", count: 80))
        print("💬 GEMINI CHAT MESSAGES (\(messages.count) incoming, \(formattedCount) formatted):")
        print(String(repeating: "-", count: 80))
        for (index, message) in messages.enumerated() {
            let preview = message.content.prefix(100)
            let truncated = message.content.count > 100 ? "..." : ""
            print("  [\(index)] \(message.role.rawValue): \(preview)\(truncated)")
        }
        print(String(repeating: "-", count: 80) + "\n")
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
        case 400:
            // Parse Gemini error response for more useful error message
            let errorMessage = parseGeminiError(data) ?? String(data: data, encoding: .utf8) ?? "Bad request"
            throw LLMProviderError.serverError(statusCode: code, message: errorMessage)
        case 401:
            // 401 is the actual authentication error code
            throw LLMProviderError.invalidAPIKey
        case 403:
            // 403 is permission denied (API enabled, quota, etc.) - not invalid key
            let errorMessage = parseGeminiError(data) ?? String(data: data, encoding: .utf8) ?? "Permission denied"
            throw LLMProviderError.serverError(statusCode: code, message: errorMessage)
        case 429:
            throw LLMProviderError.rateLimitExceeded(retryAfter: nil)
        default:
            let message = parseGeminiError(data) ?? String(data: data, encoding: .utf8)
            throw LLMProviderError.serverError(statusCode: code, message: message)
        }
    }

    /// Parse Gemini API error response to extract human-readable message
    private func parseGeminiError(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    // MARK: - Tool Request Building

    /// Build a request with tools
    private func buildToolRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use shared method for correct chronological message ordering
        let contents = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        // Add tools if available
        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toGemini(tools: tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Build a streaming request with tools
    private func buildToolStreamRequest(
        apiKey: String,
        messages: [ChatMessage],
        tools: [ConnectorTool]
    ) throws -> URLRequest {
        // Use streamGenerateContent for streaming
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(currentModel.id):streamGenerateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use shared method for correct chronological message ordering
        let contents = formatMessagesWithToolRounds(messages: messages)

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        if !tools.isEmpty {
            body["tools"] = ToolSchemaConverter.toGemini(tools: tools)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Parse a tool-enabled response
    private func parseToolResponse(_ data: Data) throws -> ToolEnabledGeneration {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw LLMProviderError.invalidResponse
        }

        // Extract text content and function calls
        var textContent: String?
        var toolCalls: [LLMToolCall] = []

        for part in parts {
            if let text = part["text"] as? String {
                textContent = (textContent ?? "") + text
            } else if let functionCall = part["functionCall"] as? [String: Any],
                      let name = functionCall["name"] as? String {
                let args = functionCall["args"] as? [String: Any] ?? [:]
                // Gemini doesn't provide call IDs, generate one
                toolCalls.append(LLMToolCall(id: UUID().uuidString, name: name, arguments: args))
            }
        }

        return ToolEnabledGeneration(content: textContent, toolCalls: toolCalls)
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

    // MARK: - Tool Stream Parsing

    /// Result from parsing a tool stream JSON object
    private enum ToolStreamParseResult: Sendable {
        case text(String)
        case toolCall(LLMToolCall)
    }

    /// Stream JSON objects from Gemini's tool-enabled streaming response
    /// Parses both text content and function calls from parts
    private func streamToolJsonObjects(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<ToolStreamParseResult, Error> {
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
                                let results = self.parseToolStreamChunk(objectData)
                                for result in results {
                                    continuation.yield(result)
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

    /// Parse a single JSON chunk from Gemini streaming for both text and tool calls
    private func parseToolStreamChunk(_ data: Data) -> [ToolStreamParseResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return []
        }

        var results: [ToolStreamParseResult] = []

        for part in parts {
            if let text = part["text"] as? String, !text.isEmpty {
                results.append(.text(text))
            } else if let functionCall = part["functionCall"] as? [String: Any],
                      let name = functionCall["name"] as? String {
                let args = functionCall["args"] as? [String: Any] ?? [:]
                // Gemini doesn't provide call IDs, generate one
                let toolCall = LLMToolCall(id: UUID().uuidString, name: name, arguments: args)
                results.append(.toolCall(toolCall))
            }
        }

        return results
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

