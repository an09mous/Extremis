// MARK: - Text Inserter Service
// Inserts generated text back into the source application

import Foundation
import AppKit
import ApplicationServices

/// Service for inserting text back into the source application
final class TextInserterService: TextInserter {
    
    // MARK: - Properties
    
    /// Clipboard manager for text operations
    private let clipboardManager: ClipboardManager
    
    /// Permission manager for checking access
    private let permissionManager: PermissionManager
    
    /// Shared instance
    static let shared = TextInserterService()
    
    // MARK: - Initialization
    
    init(
        clipboardManager: ClipboardManager = .shared,
        permissionManager: PermissionManager = .shared
    ) {
        self.clipboardManager = clipboardManager
        self.permissionManager = permissionManager
    }
    
    // MARK: - TextInserter Protocol

    /// Apps that need clipboard-based insertion (Electron apps and browsers)
    private static let clipboardOnlyApps: Set<String> = [
        // Electron apps
        "com.tinyspeck.slackmacgap",  // Slack
        "com.microsoft.VSCode",        // VS Code
        "com.hnc.Discord",             // Discord
        "com.spotify.client",          // Spotify
        "com.figma.Desktop",           // Figma
        "notion.id",                   // Notion
        "net.whatsapp.WhatsApp",       // WhatsApp
        "desktop.WhatsApp",            // WhatsApp (alternative bundle ID)
        // Browsers (AX doesn't work reliably with web content)
        "com.apple.Safari",            // Safari
        "com.google.Chrome",           // Chrome
        "org.mozilla.firefox",         // Firefox
        "com.microsoft.edgemac",       // Edge
        "com.brave.Browser",           // Brave
        "company.thebrowser.Browser",  // Arc
        "com.operasoftware.Opera",     // Opera
        "com.vivaldi.Vivaldi",         // Vivaldi
    ]

    func insert(text: String, into source: ContextSource) async throws {
        // Check accessibility permission
        guard permissionManager.isAccessibilityEnabled() else {
            throw TextInsertionError.accessibilityPermissionDenied
        }

        print("🔧 TextInserter: Inserting into \(source.applicationName) (\(source.bundleIdentifier))")

        // Find and activate the target application
        guard let app = findApplication(bundleId: source.bundleIdentifier) else {
            print("⚠️ TextInserter: App not found, using clipboard fallback")
            try await clipboardManager.insertText(text)
            return
        }

        // Bring the app to front
        app.activate(options: [.activateIgnoringOtherApps])

        // For browsers and Electron apps, skip AX insertion and go straight to clipboard
        let needsClipboard = Self.clipboardOnlyApps.contains(source.bundleIdentifier)

        if needsClipboard {
            print("🔧 TextInserter: Browser/Electron app detected, using clipboard paste")
            // Longer delay to ensure app is focused and ready
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            try await insertViaClipboard(text: text)
            return
        }

        // Standard delay for native apps
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Try direct AX insertion for native apps
        if try await insertViaAccessibility(text: text, app: app) {
            print("✅ TextInserter: Inserted via Accessibility API")
            return
        }

        print("⚠️ TextInserter: AX insertion failed, using clipboard fallback")
        // Fallback to clipboard-based insertion
        try await insertViaClipboard(text: text)
    }

    /// Insert text via clipboard (Cmd+V)
    private func insertViaClipboard(text: String) async throws {
        // Save current clipboard
        clipboardManager.saveClipboard()

        // Copy text to clipboard
        clipboardManager.copy(text)

        // Small delay to ensure clipboard is ready
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Paste using CGEvent (more reliable than ClipboardManager.paste())
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for V (virtual key 0x09)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            throw TextInsertionError.clipboardOperationFailed
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and up
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms

        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw TextInsertionError.clipboardOperationFailed
        }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)

        print("✅ TextInserter: Pasted via Cmd+V")

        // Restore clipboard after a delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            clipboardManager.restoreClipboard()
            print("✅ TextInserter: Clipboard restored")
        }
    }
    
    // MARK: - Private Methods
    
    /// Find running application by bundle ID
    private func findApplication(bundleId: String) -> NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleId
        }
    }
    
    /// Try to insert text using Accessibility API
    private func insertViaAccessibility(text: String, app: NSRunningApplication) async throws -> Bool {
        guard let focusedElement = AccessibilityHelpers.getFocusedElement(from: app) else {
            return false
        }
        
        // Check if element is editable
        guard AccessibilityHelpers.isTextInput(focusedElement) else {
            return false
        }
        
        // Try to replace selected text first
        if AccessibilityHelpers.setSelectedText(text, on: focusedElement) {
            return true
        }
        
        // Try to set value directly (append mode)
        if let currentValue = AccessibilityHelpers.getValue(from: focusedElement) {
            let newValue = currentValue + text
            return AccessibilityHelpers.setValue(newValue, on: focusedElement)
        }
        
        return false
    }
}

// MARK: - Text Insertion Options

extension TextInserterService {
    
    /// Insert modes
    enum InsertMode {
        case replace      // Replace selected text
        case append       // Append to current content
        case clipboard    // Use clipboard paste
    }
    
    /// Insert with specific mode
    func insert(text: String, into source: ContextSource, mode: InsertMode) async throws {
        switch mode {
        case .replace, .append:
            try await insert(text: text, into: source)
        case .clipboard:
            try await clipboardManager.insertText(text)
        }
    }
}

