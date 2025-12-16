// MARK: - Selection Detector
// Selection detection using clipboard-based approach for reliability across all apps

import Foundation
import AppKit
import ApplicationServices

/// Selection detection utility for determining user intent
/// This is the entry point for Magic Mode to decide: summarize vs autocomplete
enum SelectionDetector {

    // MARK: - Types

    /// Result of selection detection
    struct SelectionResult {
        /// Whether user has text selected
        let hasSelection: Bool
        /// The selected text (nil if no selection)
        let selectedText: String?
        /// Source application info
        let source: ContextSource?
        /// The focused AXUIElement (for later operations)
        let focusedElement: AXUIElement?

        static let empty = SelectionResult(
            hasSelection: false,
            selectedText: nil,
            source: nil,
            focusedElement: nil
        )
    }

    // MARK: - Public API

    /// Detect if user has text selected using clipboard-based approach
    /// This is more reliable than AX API for Electron apps
    /// - Returns: SelectionResult containing selection state and text
    static func detectSelection() -> SelectionResult {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("[SelectionDetector] No frontmost application")
            return .empty
        }

        print("[SelectionDetector] Checking app: \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "?"))")

        let source = ContextSource(
            applicationName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )

        // First try AX API (fast path)
        if let axResult = tryAXSelection(app: app, source: source) {
            return axResult
        }

        // Fallback to clipboard-based detection (reliable for all apps)
        print("[SelectionDetector] AX API failed, trying clipboard-based detection...")
        return detectSelectionViaClipboard(source: source)
    }

    /// Try to detect selection via Accessibility API (fast but unreliable for some apps)
    private static func tryAXSelection(app: NSRunningApplication, source: ContextSource) -> SelectionResult? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused element with retry logic
        var focusedElementRef: CFTypeRef?
        var focusResult: AXError = .failure

        // Retry a few times if we get no value - can happen during hotkey transition
        for attempt in 1...3 {
            focusResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElementRef
            )

            if focusResult == .success {
                break
            }

            if attempt < 3 {
                Thread.sleep(forTimeInterval: 0.02) // 20ms retry delay
            }
        }

        guard focusResult == .success, let focusedElement = focusedElementRef else {
            print("[SelectionDetector] AX: Could not get focused element: \(focusResult.rawValue)")
            return nil
        }

        // Get selected text
        var selectedTextRef: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        // Check if we have non-empty selected text
        if textResult == .success,
           let text = selectedTextRef as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[SelectionDetector] AX: ✅ Found selection: \(text.prefix(50))...")
            return SelectionResult(
                hasSelection: true,
                selectedText: text,
                source: source,
                focusedElement: (focusedElement as! AXUIElement)
            )
        }

        print("[SelectionDetector] AX: No selection via focused element")
        return nil
    }

    /// Detect selection by using clipboard (Cmd+C) - reliable for all apps
    /// This saves clipboard, copies, checks, and restores
    private static func detectSelectionViaClipboard(source: ContextSource) -> SelectionResult {
        print("[SelectionDetector] Clipboard: Starting clipboard-based detection...")

        let pasteboard = NSPasteboard.general

        // Save current clipboard state
        let savedTypes = pasteboard.types ?? []
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        for type in savedTypes {
            if let data = pasteboard.data(forType: type) {
                savedData.append((type, data))
            }
        }
        print("[SelectionDetector] Clipboard: Saved \(savedData.count) clipboard items")

        // Clear clipboard
        pasteboard.clearContents()

        // Send Cmd+C to copy selection
        sendCopy()

        // Small delay for clipboard to update
        Thread.sleep(forTimeInterval: 0.05) // 50ms

        // Check if clipboard now has text
        let copiedText = pasteboard.string(forType: .string)
        let hasSelection = copiedText != nil && !copiedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasSelection {
            print("[SelectionDetector] Clipboard: ✅ Found selection: \(copiedText!.prefix(50))...")
        } else {
            print("[SelectionDetector] Clipboard: ❌ No selection found")
        }

        // Restore original clipboard
        pasteboard.clearContents()
        if !savedData.isEmpty {
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }
        print("[SelectionDetector] Clipboard: Restored original clipboard")

        return SelectionResult(
            hasSelection: hasSelection,
            selectedText: hasSelection ? copiedText : nil,
            source: source,
            focusedElement: nil
        )
    }

    /// Send Cmd+C keystroke
    private static func sendCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)

        // Key down Cmd+C
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) { // 0x08 = 'c'
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay
        Thread.sleep(forTimeInterval: 0.01)

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

