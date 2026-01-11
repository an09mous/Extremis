// MARK: - Text Inserter Protocol
// Defines the contract for inserting generated text back into applications

import Foundation

/// Protocol for inserting generated text back into the source application
protocol TextInserter {
    /// Insert text at the current cursor position in the source app
    /// - Parameters:
    ///   - text: Text to insert
    ///   - source: Original context source (for app targeting)
    /// - Throws: TextInsertionError on failure
    func insert(text: String, into source: ContextSource) async throws
}

// MARK: - Text Insertion Error

/// Errors that can occur during text insertion
enum TextInsertionError: LocalizedError, Equatable {
    case accessibilityPermissionDenied
    case targetElementNotFound
    case applicationNotResponding(appName: String)
    case clipboardOperationFailed
    case unknown(String)
    
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
        case .unknown(let message):
            return "Text insertion failed: \(message)"
        }
    }
    
    // Custom Equatable
    static func == (lhs: TextInsertionError, rhs: TextInsertionError) -> Bool {
        switch (lhs, rhs) {
        case (.accessibilityPermissionDenied, .accessibilityPermissionDenied): return true
        case (.targetElementNotFound, .targetElementNotFound): return true
        case (.applicationNotResponding(let a), .applicationNotResponding(let b)): return a == b
        case (.clipboardOperationFailed, .clipboardOperationFailed): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Secure Storage Protocol

/// Protocol for secure credential storage (API keys)
protocol SecureStorage {
    /// Store a value securely
    /// - Parameters:
    ///   - key: The key to store under
    ///   - value: The value to store
    /// - Throws: PreferencesError on failure
    func store(key: String, value: String) throws
    
    /// Retrieve a stored value
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored value, or nil if not found
    /// - Throws: PreferencesError on failure
    func retrieve(key: String) throws -> String?
    
    /// Delete a stored value
    /// - Parameter key: The key to delete
    /// - Throws: PreferencesError on failure
    func delete(key: String) throws
    
    /// Check if a key exists
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists
    func exists(key: String) -> Bool
}

// MARK: - Preferences Store Protocol

/// Protocol for managing user preferences
protocol PreferencesStore {
    /// Current preferences
    var preferences: Preferences { get }
    
    /// Update preferences
    /// - Parameter preferences: New preferences to save
    /// - Throws: PreferencesError on failure
    func update(_ preferences: Preferences) throws
    
    /// Reset to defaults
    func reset()
    
    /// Observe preference changes
    /// - Parameter handler: Closure called when preferences change
    /// - Returns: Token to cancel observation
    func observe(_ handler: @escaping (Preferences) -> Void) -> Any
}

// MARK: - Preferences Error

/// Errors that can occur with preferences
enum PreferencesError: LocalizedError, Equatable {
    case invalidHotkey
    case hotkeyConflict(existingApp: String?)
    case keychainAccessDenied
    case keychainWriteFailed
    case unknown(String)
    
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
        case .unknown(let message):
            return "Preferences error: \(message)"
        }
    }
    
    // Custom Equatable
    static func == (lhs: PreferencesError, rhs: PreferencesError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidHotkey, .invalidHotkey): return true
        case (.hotkeyConflict(let a), .hotkeyConflict(let b)): return a == b
        case (.keychainAccessDenied, .keychainAccessDenied): return true
        case (.keychainWriteFailed, .keychainWriteFailed): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}


