// MARK: - Extremis Error Contracts
// Typed errors for each domain, enabling precise error handling.

import Foundation

// MARK: - Context Extraction Errors

enum ContextExtractionError: LocalizedError {
    case accessibilityPermissionDenied
    case noFocusedElement
    case unsupportedApplication(bundleId: String)
    case browserAccessDenied(browser: String)
    case domExtractionFailed(selector: String)
    case timeout
    case unknown(underlying: Error)
    
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
        case .unknown(let error):
            return "Context extraction failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - LLM Provider Errors

enum LLMProviderError: LocalizedError {
    case notConfigured(provider: LLMProviderType)
    case invalidAPIKey
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case contextTooLong(maxTokens: Int)
    case networkError(underlying: Error)
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case cancelled
    case unknown(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "\(provider.rawValue) is not configured. Please add your API key in Preferences."
        case .invalidAPIKey:
            return "Invalid API key. Please check your API key in Preferences."
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded. Please try again in \(Int(seconds)) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .contextTooLong(let maxTokens):
            return "Context is too long (max \(maxTokens) tokens). Try with less context."
        case .networkError:
            return "Network error. Please check your internet connection."
        case .invalidResponse:
            return "Received invalid response from AI provider."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .cancelled:
            return "Generation was cancelled."
        case .unknown(let error):
            return "AI generation failed: \(error.localizedDescription)"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded, .networkError, .serverError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Text Insertion Errors

enum TextInsertionError: LocalizedError {
    case accessibilityPermissionDenied
    case targetElementNotFound
    case applicationNotResponding(appName: String)
    case clipboardOperationFailed
    case unknown(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission required for text insertion."
        case .targetElementNotFound:
            return "Could not find the original text field to insert into."
        case .applicationNotResponding(let appName):
            return "\(appName) is not responding. Please try again."
        case .clipboardOperationFailed:
            return "Clipboard operation failed."
        case .unknown(let error):
            return "Text insertion failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preferences Errors

enum PreferencesError: LocalizedError {
    case invalidHotkey
    case hotkeyConflict(existingApp: String?)
    case keychainAccessDenied
    case keychainWriteFailed
    case unknown(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidHotkey:
            return "Invalid hotkey combination."
        case .hotkeyConflict(let app):
            if let appName = app {
                return "This hotkey conflicts with \(appName). Please choose another."
            }
            return "This hotkey conflicts with another application."
        case .keychainAccessDenied:
            return "Could not access Keychain. Please check permissions."
        case .keychainWriteFailed:
            return "Could not save to Keychain."
        case .unknown(let error):
            return "Preferences error: \(error.localizedDescription)"
        }
    }
}

