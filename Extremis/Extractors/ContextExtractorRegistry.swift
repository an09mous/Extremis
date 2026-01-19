// MARK: - Context Extractor Registry
// Manages available context extractors

import Foundation

/// Registry for managing context extractors
/// Provides the appropriate extractor based on the active application
@MainActor
final class ContextExtractorRegistry: @preconcurrency ContextExtractorRegistryProtocol {
    
    // MARK: - Properties
    
    /// Registered extractors (app-specific)
    private(set) var extractors: [ContextExtractor] = []
    
    /// Generic fallback extractor
    let fallbackExtractor: ContextExtractor = GenericExtractor()
    
    /// Shared instance
    static let shared = ContextExtractorRegistry()
    
    // MARK: - Initialization
    
    init() {
        // Register default extractors
        registerDefaultExtractors()
    }
    
    // MARK: - ContextExtractorRegistryProtocol
    
    func register(_ extractor: ContextExtractor) {
        // Avoid duplicates
        guard !extractors.contains(where: { $0.identifier == extractor.identifier }) else {
            return
        }
        extractors.append(extractor)
    }
    
    func extractor(for source: ContextSource) -> ContextExtractor {
        print("🔍 ExtractorRegistry: Finding extractor for:")
        print("   App: \(source.applicationName)")
        print("   BundleID: \(source.bundleIdentifier)")
        print("   WindowTitle: \(source.windowTitle ?? "nil")")
        print("   URL: \(source.url?.absoluteString ?? "nil")")

        // Find first matching extractor
        for extractor in extractors {
            let canExtract = extractor.canExtract(from: source)
            print("   → \(extractor.displayName): canExtract = \(canExtract)")
            if canExtract {
                print("✅ SELECTED EXTRACTOR: \(extractor.displayName)")
                return extractor
            }
        }

        // Fall back to generic extractor
        print("✅ SELECTED EXTRACTOR: \(fallbackExtractor.displayName) (fallback)")
        return fallbackExtractor
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultExtractors() {
        // Register app-specific extractors
        register(SlackExtractor())

        // Register generic browser extractor (handles all browser pages including Gmail, GitHub)
        register(BrowserExtractor())
    }
    
    // MARK: - Convenience Methods
    
    /// Get extractor by identifier
    func extractor(withIdentifier identifier: String) -> ContextExtractor? {
        if identifier == fallbackExtractor.identifier {
            return fallbackExtractor
        }
        return extractors.first { $0.identifier == identifier }
    }
    
    /// List all available extractors including fallback
    var allExtractors: [ContextExtractor] {
        extractors + [fallbackExtractor]
    }
}

