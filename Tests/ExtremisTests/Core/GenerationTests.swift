// MARK: - Generation Model Tests

import XCTest
@testable import Extremis

final class GenerationTests: XCTestCase {
    
    // MARK: - Creation Tests
    
    func testGenerationCreation() {
        let instructionId = UUID()
        let generation = Generation(
            instructionId: instructionId,
            provider: .openai,
            content: "Here is the generated response."
        )
        
        XCTAssertEqual(generation.instructionId, instructionId)
        XCTAssertEqual(generation.provider, .openai)
        XCTAssertEqual(generation.content, "Here is the generated response.")
        XCTAssertNotNil(generation.id)
    }
    
    func testGenerationWithTokenUsage() {
        let generation = Generation(
            instructionId: UUID(),
            provider: .anthropic,
            content: "Response",
            tokenUsage: TokenUsage(promptTokens: 100, completionTokens: 50),
            latencyMs: 1500
        )
        
        XCTAssertEqual(generation.tokenUsage?.promptTokens, 100)
        XCTAssertEqual(generation.tokenUsage?.completionTokens, 50)
        XCTAssertEqual(generation.tokenUsage?.totalTokens, 150)
        XCTAssertEqual(generation.latencyMs, 1500)
    }
    
    // MARK: - LLM Provider Type Tests
    
    func testAllProviderTypes() {
        let providers = LLMProviderType.allCases
        
        XCTAssertEqual(providers.count, 3)
        XCTAssertTrue(providers.contains(.openai))
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.gemini))
    }
    
    func testProviderDisplayNames() {
        XCTAssertEqual(LLMProviderType.openai.displayName, "ChatGPT (OpenAI)")
        XCTAssertEqual(LLMProviderType.anthropic.displayName, "Claude (Anthropic)")
        XCTAssertEqual(LLMProviderType.gemini.displayName, "Gemini (Google)")
    }
    
    func testProviderDefaultModels() {
        XCTAssertFalse(LLMProviderType.openai.defaultModel.isEmpty)
        XCTAssertFalse(LLMProviderType.anthropic.defaultModel.isEmpty)
        XCTAssertFalse(LLMProviderType.gemini.defaultModel.isEmpty)
    }
    
    func testProviderBaseURLs() {
        XCTAssertEqual(LLMProviderType.openai.baseURL.host, "api.openai.com")
        XCTAssertEqual(LLMProviderType.anthropic.baseURL.host, "api.anthropic.com")
        XCTAssertEqual(LLMProviderType.gemini.baseURL.host, "generativelanguage.googleapis.com")
    }
    
    // MARK: - Generation Status Tests
    
    func testGenerationStatusValues() {
        let statuses: [GenerationStatus] = [.pending, .generating, .completed, .failed, .cancelled]
        
        XCTAssertEqual(statuses.count, 5)
    }
    
    // MARK: - Codable Tests
    
    func testGenerationCodable() throws {
        let generation = Generation(
            instructionId: UUID(),
            provider: .gemini,
            content: "Test content",
            tokenUsage: TokenUsage(promptTokens: 10, completionTokens: 20)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(generation)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Generation.self, from: data)
        
        XCTAssertEqual(generation.id, decoded.id)
        XCTAssertEqual(generation.provider, decoded.provider)
        XCTAssertEqual(generation.content, decoded.content)
        XCTAssertEqual(generation.tokenUsage?.totalTokens, decoded.tokenUsage?.totalTokens)
    }
}

