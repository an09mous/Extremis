// MARK: - Extremis Protocol Contracts
// These protocols define the contracts between components.
// Implementation details are separate from these interfaces.

import Foundation

// MARK: - Context Extraction

/// Protocol for app-specific context extractors.
/// Each supported app (Slack, Gmail, GitHub) implements this protocol.
protocol ContextExtractor {
    /// Unique identifier for this extractor
    var identifier: String { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Bundle identifiers this extractor handles
    var supportedBundleIdentifiers: [String] { get }
    
    /// URL patterns this extractor handles (for browser-based apps)
    var supportedURLPatterns: [String] { get }
    
    /// Check if this extractor can handle the given source
    func canExtract(from source: ContextSource) -> Bool
    
    /// Extract context from the active application
    /// - Returns: Extracted context or throws if extraction fails
    func extract() async throws -> Context
}

/// Registry for managing available context extractors
protocol ContextExtractorRegistry {
    /// All registered extractors
    var extractors: [ContextExtractor] { get }
    
    /// Register a new extractor
    func register(_ extractor: ContextExtractor)
    
    /// Find appropriate extractor for given source
    func extractor(for source: ContextSource) -> ContextExtractor
    
    /// Generic fallback extractor
    var fallbackExtractor: ContextExtractor { get }
}

// MARK: - LLM Providers

/// Protocol for LLM service providers (OpenAI, Anthropic, Gemini)
protocol LLMProvider {
    /// Provider type identifier
    var providerType: LLMProviderType { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Whether API key is configured
    var isConfigured: Bool { get }
    
    /// Configure the provider with an API key
    func configure(apiKey: String) throws
    
    /// Generate a response (non-streaming)
    /// - Parameters:
    ///   - instruction: User's instruction text
    ///   - context: Captured context
    /// - Returns: Generated response
    func generate(instruction: String, context: Context) async throws -> Generation
    
    /// Generate a response with streaming
    /// - Parameters:
    ///   - instruction: User's instruction text
    ///   - context: Captured context
    /// - Returns: Async stream of text chunks
    func generateStream(
        instruction: String,
        context: Context
    ) -> AsyncThrowingStream<String, Error>
}

/// Registry for managing LLM providers
protocol LLMProviderRegistry {
    /// All available providers
    var providers: [LLMProvider] { get }
    
    /// Currently active provider
    var activeProvider: LLMProvider? { get }
    
    /// Set the active provider
    func setActive(_ providerType: LLMProviderType) throws
    
    /// Get provider by type
    func provider(for type: LLMProviderType) -> LLMProvider?
}

// MARK: - Text Insertion

/// Protocol for inserting generated text back into source application
protocol TextInserter {
    /// Insert text at the current cursor position in the source app
    /// - Parameters:
    ///   - text: Text to insert
    ///   - source: Original context source (for app targeting)
    /// - Returns: Success or throws on failure
    func insert(text: String, into source: ContextSource) async throws
}

// MARK: - Preferences

/// Protocol for managing user preferences
protocol PreferencesStore {
    /// Current preferences
    var preferences: Preferences { get }
    
    /// Update preferences
    func update(_ preferences: Preferences) throws
    
    /// Reset to defaults
    func reset()
    
    /// Observe preference changes
    func observe(_ handler: @escaping (Preferences) -> Void) -> Any
}

// MARK: - Secure Storage

/// Protocol for secure credential storage (API keys)
protocol SecureStorage {
    /// Store a value securely
    func store(key: String, value: String) throws
    
    /// Retrieve a stored value
    func retrieve(key: String) throws -> String?
    
    /// Delete a stored value
    func delete(key: String) throws
    
    /// Check if a key exists
    func exists(key: String) -> Bool
}

// MARK: - Conversation Store (Phase 2 Ready)

/// Protocol for conversation persistence (in-memory for Phase 1)
protocol ConversationStore {
    /// Save a conversation
    func save(_ conversation: Conversation) async throws
    
    /// Load a conversation by ID
    func load(id: UUID) async throws -> Conversation?
    
    /// Get recent conversations
    func recent(limit: Int) async throws -> [Conversation]
    
    /// Delete a conversation
    func delete(id: UUID) async throws
    
    /// Clear all conversations
    func clearAll() async throws
}

