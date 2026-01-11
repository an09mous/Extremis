// MARK: - Context Extractor Protocol
// Defines the contract for app-specific context extractors

import Foundation

/// Protocol for app-specific context extractors
/// Each supported app (Slack, Gmail, GitHub) implements this protocol
protocol ContextExtractor {
    /// Unique identifier for this extractor
    var identifier: String { get }
    
    /// Human-readable name
    var displayName: String { get }
    
    /// Bundle identifiers this extractor handles (for native apps)
    var supportedBundleIdentifiers: [String] { get }
    
    /// URL patterns this extractor handles (for browser-based apps)
    /// Uses simple prefix matching, e.g., "https://mail.google.com"
    var supportedURLPatterns: [String] { get }
    
    /// Check if this extractor can handle the given source
    /// - Parameter source: The context source to check
    /// - Returns: true if this extractor can extract from the source
    func canExtract(from source: ContextSource) -> Bool
    
    /// Extract context from the active application
    /// - Returns: Extracted context
    /// - Throws: ContextExtractionError if extraction fails
    func extract() async throws -> Context
}

// MARK: - Default Implementation

extension ContextExtractor {
    /// Default implementation checks bundle IDs and URL patterns
    func canExtract(from source: ContextSource) -> Bool {
        // Check bundle identifier
        if supportedBundleIdentifiers.contains(source.bundleIdentifier) {
            return true
        }

        // Check URL patterns for browser-based apps
        if let url = source.url {
            let urlString = url.absoluteString
            return supportedURLPatterns.contains { pattern in
                urlString.hasPrefix(pattern)
            }
        }

        return false
    }
}

// MARK: - Context Extractor Registry Protocol

/// Registry for managing available context extractors
protocol ContextExtractorRegistryProtocol {
    /// All registered extractors
    var extractors: [ContextExtractor] { get }
    
    /// Register a new extractor
    func register(_ extractor: ContextExtractor)
    
    /// Find appropriate extractor for given source
    /// Returns the generic extractor if no specific extractor matches
    func extractor(for source: ContextSource) -> ContextExtractor
    
    /// Generic fallback extractor
    var fallbackExtractor: ContextExtractor { get }
}

// MARK: - Context Extraction Error

/// Errors that can occur during context extraction
enum ContextExtractionError: LocalizedError, Equatable {
    case accessibilityPermissionDenied
    case noFocusedElement
    case unsupportedApplication(bundleId: String)
    case browserAccessDenied(browser: String)
    case domExtractionFailed(selector: String)
    case timeout
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission required. Please enable in System Settings > Privacy & Security > Accessibility."
        case .noFocusedElement:
            return "No text field is currently focused."
        case .unsupportedApplication(let bundleId):
            return "Application '\(bundleId)' is not fully supported. Using generic text extraction."
        case .browserAccessDenied(let browser):
            return "\(browser) denied script execution. Please allow Extremis to control \(browser)."
        case .domExtractionFailed(let selector):
            return "Could not find expected content (selector: \(selector))."
        case .timeout:
            return "Context extraction timed out."
        case .unknown(let message):
            return "Context extraction failed: \(message)"
        }
    }
    
    // Custom Equatable for unknown case
    static func == (lhs: ContextExtractionError, rhs: ContextExtractionError) -> Bool {
        switch (lhs, rhs) {
        case (.accessibilityPermissionDenied, .accessibilityPermissionDenied): return true
        case (.noFocusedElement, .noFocusedElement): return true
        case (.unsupportedApplication(let a), .unsupportedApplication(let b)): return a == b
        case (.browserAccessDenied(let a), .browserAccessDenied(let b)): return a == b
        case (.domExtractionFailed(let a), .domExtractionFailed(let b)): return a == b
        case (.timeout, .timeout): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

