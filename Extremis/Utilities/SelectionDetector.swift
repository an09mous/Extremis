// MARK: - Selection Detector
// Selection detection using clipboard-based approach for reliability across all apps

import Foundation
import AppKit
import ApplicationServices

/// Selection detection utility for determining user intent
/// Used to detect text selection for Quick Mode vs Chat Mode routing
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
    /// - Parameter verbose: If false, suppresses all logging (for no-op scenarios like Magic Mode without selection)
    /// - Returns: SelectionResult containing selection state and text
    static func detectSelection(verbose: Bool = true) -> SelectionResult {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            if verbose { print("[SelectionDetector] No frontmost application") }
            return .empty
        }

        if verbose {
            print("[SelectionDetector] Checking app: \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "?"))")
        }

        let source = ContextSource(
            applicationName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )

        // First try AX API (fast path)
        if let axResult = tryAXSelection(app: app, source: source, verbose: verbose) {
            return axResult
        }

        // Fallback to clipboard-based detection (reliable for all apps)
        if verbose { print("[SelectionDetector] AX API failed, trying clipboard-based detection...") }
        return detectSelectionViaClipboard(source: source, verbose: verbose)
    }

    /// Try to detect selection via Accessibility API (fast but unreliable for some apps)
    private static func tryAXSelection(app: NSRunningApplication, source: ContextSource, verbose: Bool) -> SelectionResult? {
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
            if verbose { print("[SelectionDetector] AX: Could not get focused element: \(focusResult.rawValue)") }
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
            if verbose { print("[SelectionDetector] AX: ✅ Found selection: \(text.prefix(50))...") }
            return SelectionResult(
                hasSelection: true,
                selectedText: text,
                source: source,
                focusedElement: (focusedElement as! AXUIElement)
            )
        }

        if verbose { print("[SelectionDetector] AX: No selection via focused element") }
        return nil
    }

    /// Detect selection by using clipboard (Cmd+C) - reliable for all apps
    /// This saves clipboard, copies, checks, and restores
    ///
    /// Note: This method includes heuristics to detect IDE "copy line" behavior where
    /// Cmd+C with no selection copies the entire current line (VS Code, JetBrains, etc.)
    private static func detectSelectionViaClipboard(source: ContextSource, verbose: Bool) -> SelectionResult {
        if verbose { print("[SelectionDetector] Clipboard: Starting clipboard-based detection...") }

        let pasteboard = NSPasteboard.general

        // Save current clipboard state
        let savedTypes = pasteboard.types ?? []
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        for type in savedTypes {
            if let data = pasteboard.data(forType: type) {
                savedData.append((type, data))
            }
        }
        if verbose { print("[SelectionDetector] Clipboard: Saved \(savedData.count) clipboard items") }

        // Clear clipboard
        pasteboard.clearContents()

        // Send Cmd+C to copy selection
        sendCopy()

        // Small delay for clipboard to update
        Thread.sleep(forTimeInterval: 0.05) // 50ms

        // Check if clipboard now has text
        let copiedText = pasteboard.string(forType: .string)
        let hasNonEmptyText = copiedText != nil && !copiedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Determine if this is a real selection or IDE "copy line" behavior
        var hasSelection = false
        if hasNonEmptyText, let text = copiedText {
            // Check for IDE "copy line" behavior using heuristics
            if isIDECopyLineBehavior(text) {
                if verbose {
                    print("[SelectionDetector] Clipboard: ⚠️ Detected IDE 'copy line' behavior (single line + trailing newline)")
                    print("[SelectionDetector] Clipboard: ❌ Treating as no selection")
                }
                hasSelection = false
            } else {
                if verbose { print("[SelectionDetector] Clipboard: ✅ Found selection: \(text.prefix(50))...") }
                hasSelection = true
            }
        } else {
            if verbose { print("[SelectionDetector] Clipboard: ❌ No selection found") }
        }

        // Restore original clipboard
        pasteboard.clearContents()
        if !savedData.isEmpty {
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }
        if verbose { print("[SelectionDetector] Clipboard: Restored original clipboard") }

        return SelectionResult(
            hasSelection: hasSelection,
            selectedText: hasSelection ? copiedText : nil,
            source: source,
            focusedElement: nil
        )
    }

    // MARK: - IDE Copy Line Detection

    /// Detects if the copied text is likely from IDE "copy line" behavior rather than a real selection.
    ///
    /// ## Background
    /// Many IDEs (VS Code, JetBrains IDEs, Sublime Text, etc.) have a feature where pressing
    /// Cmd+C (or Ctrl+C) with NO text selected will copy the ENTIRE current line, including
    /// the trailing newline character. This is a convenience feature for quickly copying lines.
    ///
    /// ## Problem
    /// When Extremis uses Cmd+C to detect if text is selected, IDEs will return content even
    /// when the user hasn't actually selected anything. This causes false positives where
    /// Extremis thinks there's a selection when there isn't.
    ///
    /// ## Heuristic
    /// IDE "copy line" behavior has a distinctive pattern:
    /// 1. The text ends with a newline character (`\n`)
    /// 2. There are no OTHER newline characters in the text (it's a single line)
    ///
    /// Example: `"const x = 5;\n"` → single line with trailing `\n` → likely "copy line"
    /// Example: `"hello world"` → no trailing `\n` → real selection
    /// Example: `"line1\nline2"` → multiple lines → real selection
    ///
    /// ## Trade-off
    /// This heuristic may incorrectly classify as "no selection" when the user has
    /// intentionally selected exactly one line INCLUDING its trailing newline character.
    /// This is a rare edge case and acceptable trade-off to avoid false positives in IDEs.
    ///
    /// - Parameter text: The text copied from clipboard via Cmd+C
    /// - Returns: `true` if the text pattern matches IDE "copy line" behavior
    private static func isIDECopyLineBehavior(_ text: String) -> Bool {
        // Check if text ends with a newline character
        guard text.hasSuffix("\n") else {
            // No trailing newline → definitely a real selection
            // (IDE "copy line" always includes the trailing newline)
            return false
        }

        // Remove the trailing newline and check if there are any OTHER newlines
        // If the remaining text has no newlines, it was a single line → likely "copy line"
        let textWithoutTrailingNewline = String(text.dropLast())
        let hasInternalNewlines = textWithoutTrailingNewline.contains("\n")

        if hasInternalNewlines {
            // Multiple lines copied → real selection (user selected across lines)
            return false
        }

        // Single line with trailing newline → likely IDE "copy line" behavior
        // Pattern: "some text here\n" where there's no \n before the final one
        return true
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

