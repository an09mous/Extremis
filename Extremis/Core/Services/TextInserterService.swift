// MARK: - Text Inserter Service
// Inserts generated text back into the source application

import Foundation
import AppKit
import ApplicationServices

/// Service for inserting text back into the source application
@MainActor
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

    func insert(text: String, into source: ContextSource) async throws {
        // Check accessibility permission (needed for keyboard simulation)
        guard permissionManager.isAccessibilityEnabled() else {
            throw TextInsertionError.accessibilityPermissionDenied
        }

        // Find and activate the target application
        guard let app = findApplication(bundleId: source.bundleIdentifier) else {
            try await insertViaClipboard(text: text)
            return
        }

        // Bring the app to front
        app.activate(options: [.activateIgnoringOtherApps])

        // Wait for app to be focused
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Use clipboard-based insertion (most reliable across all apps)
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
}
