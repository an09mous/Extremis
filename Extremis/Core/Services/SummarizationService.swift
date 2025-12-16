// MARK: - Summarization Service
// Orchestrates text summarization using LLM providers

import Foundation

/// Service for generating text summaries
final class SummarizationService {
    
    // MARK: - Properties
    
    /// Shared instance
    static let shared = SummarizationService()
    
    /// LLM Provider Registry
    private let providerRegistry: LLMProviderRegistry
    
    /// Prompt builder
    private let promptBuilder: PromptBuilder
    
    // MARK: - Initialization
    
    init(
        providerRegistry: LLMProviderRegistry = .shared,
        promptBuilder: PromptBuilder = .shared
    ) {
        self.providerRegistry = providerRegistry
        self.promptBuilder = promptBuilder
    }
    
    // MARK: - Public API
    
    /// Summarize text and return result
    /// - Parameter request: Summary request with text and options
    /// - Returns: Summary result
    /// - Throws: LLMProviderError on failure
    func summarize(request: SummaryRequest) async throws -> SummaryResult {
        guard let provider = providerRegistry.activeProvider else {
            throw LLMProviderError.notConfigured(provider: .ollama)
        }

        print("[SummarizationService] Starting summarization with \(provider.displayName)")
        print("[SummarizationService] Text length: \(request.text.count) chars, format: \(request.format.rawValue)")

        // Build the prompt (complete prompt, not to be wrapped again)
        let prompt = promptBuilder.buildSummarizationPrompt(request: request)

        // Use generateRaw to avoid double-wrapping the prompt
        let generation = try await provider.generateRaw(prompt: prompt)

        print("[SummarizationService] Summary generated: \(generation.content.prefix(100))...")

        return SummaryResult(
            summary: generation.content,
            originalText: request.text,
            format: request.format,
            length: request.length,
            source: request.source
        )
    }
    
    /// Summarize text with streaming response
    /// - Parameter request: Summary request with text and options
    /// - Returns: AsyncThrowingStream of summary text chunks
    func summarizeStream(request: SummaryRequest) -> AsyncThrowingStream<String, Error> {
        guard let provider = providerRegistry.activeProvider else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMProviderError.notConfigured(provider: .ollama))
            }
        }

        print("[SummarizationService] Starting streaming summarization with \(provider.displayName) (\(provider.currentModel.id))")

        // Build the prompt (complete prompt, not to be wrapped again)
        let prompt = promptBuilder.buildSummarizationPrompt(request: request)

        // Use generateRawStream to avoid double-wrapping the prompt
        return provider.generateRawStream(prompt: prompt)
    }
    
    // MARK: - Convenience Methods
    
    /// Quick summarize with default options
    /// - Parameters:
    ///   - text: Text to summarize
    ///   - source: Source context
    /// - Returns: Summary result
    func quickSummarize(text: String, source: ContextSource) async throws -> SummaryResult {
        let request = SummaryRequest(text: text, source: source)
        return try await summarize(request: request)
    }
    
    /// Quick summarize with streaming
    /// - Parameters:
    ///   - text: Text to summarize
    ///   - source: Source context
    /// - Returns: AsyncThrowingStream of summary text chunks
    func quickSummarizeStream(text: String, source: ContextSource) -> AsyncThrowingStream<String, Error> {
        let request = SummaryRequest(text: text, source: source)
        return summarizeStream(request: request)
    }
}

