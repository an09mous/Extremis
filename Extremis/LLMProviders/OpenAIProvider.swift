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
                    let generation = try await generate(instruction: instruction, context: context)
                    continuation.yield(generation.content)
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
                    let generation = try await generateRaw(prompt: prompt)
                    continuation.yield(generation.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

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

