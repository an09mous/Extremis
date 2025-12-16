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

