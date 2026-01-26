// MARK: - Prompt Template Loader
// Loads and caches prompt templates from bundle resources

import Foundation

/// Defines the available prompt templates
enum PromptTemplate: String, CaseIterable {
    /// System prompt - base instructions for all interactions
    case system = "system"

    // Intent injection templates (appended to user messages based on MessageIntent)
    /// Rules for instructions about selected text (transform, explain, question, etc.)
    case intentInstruct = "intent_instruct"
    /// Rules for summarizing selected text
    case intentSummarize = "intent_summarize"
    /// Standard chat/follow-up message format
    case intentChat = "intent_chat"

    // Session summarization templates (for memory management)
    /// First-time session summarization
    case sessionSummarizationInitial = "session_summarization_initial"
    /// Hierarchical update of existing summary with new messages
    case sessionSummarizationUpdate = "session_summarization_update"

    // Tool execution templates
    /// Prompt for summarizing tool results when max rounds is reached
    case toolSummarization = "tool_summarization"

    /// The filename for this template (without extension)
    var filename: String { rawValue }
}

/// Error types for template loading
enum PromptTemplateError: Error, LocalizedError {
    case templateNotFound(PromptTemplate)
    case loadingFailed(PromptTemplate, underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .templateNotFound(let template):
            return "Prompt template '\(template.filename)' not found in bundle"
        case .loadingFailed(let template, let error):
            return "Failed to load template '\(template.filename)': \(error.localizedDescription)"
        }
    }
}

/// Loads and caches prompt templates from the app bundle
@MainActor
final class PromptTemplateLoader {
    
    // MARK: - Singleton
    
    static let shared = PromptTemplateLoader()
    
    // MARK: - Properties
    
    /// Cache for loaded templates
    private var templateCache: [PromptTemplate: String] = [:]

    /// Bundle to load resources from
    private let bundle: Bundle
    
    // MARK: - Initialization
    
    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }
    
    // MARK: - Public Methods
    
    /// Load a template by its type
    /// - Parameter template: The template type to load
    /// - Returns: The template content as a string
    /// - Throws: PromptTemplateError if template cannot be loaded
    func load(_ template: PromptTemplate) throws -> String {
        // Check cache first
        if let cached = templateCache[template] {
            return cached
        }

        // Load from bundle
        let content = try loadFromBundle(template)
        templateCache[template] = content
        return content
    }
    
    /// Preload all templates into cache
    /// Call this at app startup for better performance
    func preloadAll() {
        for template in PromptTemplate.allCases {
            _ = try? load(template)
        }
    }
    
    /// Clear the template cache
    func clearCache() {
        templateCache.removeAll()
    }
    
    // MARK: - Private Methods

    private func loadFromBundle(_ template: PromptTemplate) throws -> String {
        // Try with subdirectory first (traditional .app bundle structure)
        // Then try without subdirectory (Swift Package Manager flattens resources)
        let url = bundle.url(
            forResource: template.filename,
            withExtension: "hbs",
            subdirectory: "PromptTemplates"
        ) ?? bundle.url(
            forResource: template.filename,
            withExtension: "hbs"
        )

        guard let templateURL = url else {
            throw PromptTemplateError.templateNotFound(template)
        }

        do {
            return try String(contentsOf: templateURL, encoding: .utf8)
        } catch {
            throw PromptTemplateError.loadingFailed(template, underlying: error)
        }
    }
}

