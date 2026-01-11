// MARK: - Clipboard Manager
// Manages clipboard operations for text insertion

import Foundation
import AppKit

/// Manages clipboard operations for text insertion
final class ClipboardManager {
    
    // MARK: - Properties
    
    /// Shared instance
    static let shared = ClipboardManager()
    
    /// System pasteboard
    private let pasteboard = NSPasteboard.general
    
    /// Saved clipboard content for restoration
    private var savedContent: [NSPasteboard.PasteboardType: Data]?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Save current clipboard content
    func saveClipboard() {
        savedContent = [:]
        
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedContent?[type] = data
            }
        }
    }
    
    /// Restore previously saved clipboard content
    func restoreClipboard() {
        guard let saved = savedContent else { return }
        
        pasteboard.clearContents()
        
        for (type, data) in saved {
            pasteboard.setData(data, forType: type)
        }
        
        savedContent = nil
    }
    
    /// Copy text to clipboard
    /// - Parameter text: Text to copy
    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

