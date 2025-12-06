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
    
    /// Get text from clipboard
    /// - Returns: Clipboard text, or nil if not available
    func getText() -> String? {
        return pasteboard.string(forType: .string)
    }
    
    /// Paste clipboard content using keyboard simulation
    /// - Throws: TextInsertionError if paste fails
    func paste() throws {
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            throw TextInsertionError.clipboardOperationFailed
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        
        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw TextInsertionError.clipboardOperationFailed
        }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Insert text at cursor position using clipboard
    /// Saves and restores original clipboard content
    /// - Parameter text: Text to insert
    /// - Throws: TextInsertionError if insertion fails
    func insertText(_ text: String) async throws {
        // Save current clipboard
        saveClipboard()
        
        defer {
            // Restore clipboard after a delay
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                restoreClipboard()
            }
        }
        
        // Copy text to clipboard
        copy(text)
        
        // Small delay to ensure clipboard is ready
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Paste
        try paste()
    }
    
    /// Check if clipboard contains text
    var hasText: Bool {
        pasteboard.string(forType: .string) != nil
    }
    
    /// Clear clipboard
    func clear() {
        pasteboard.clearContents()
    }
}

