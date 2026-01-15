// MARK: - Selection Detector
// Selection detection using clipboard-based approach for reliability across all apps

import Foundation
import AppKit

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

        static let empty = SelectionResult(
            hasSelection: false,
            selectedText: nil,
            source: nil
        )
    }

    // MARK: - Public API

    /// Detect if user has text selected using clipboard-based approach (Cmd+C)
    /// This is reliable across all apps including Electron apps (VS Code, Slack, etc.)
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

        // Use clipboard-based detection (reliable for all apps)
        return detectSelectionViaClipboard(source: source, verbose: verbose)
    }

    /// Detect selection by using clipboard (Cmd+C) - reliable for all apps
    /// This saves clipboard, copies, checks, and restores
    ///
    /// Note: This method includes heuristics to detect IDE "copy line" behavior where
    /// Cmd+C with no selection copies the entire current line (VS Code, JetBrains, etc.)
    private static func detectSelectionViaClipboard(source: ContextSource, verbose: Bool) -> SelectionResult {
        let pasteboard = NSPasteboard.general

        // Save current clipboard state
        let savedTypes = pasteboard.types ?? []
        var savedData: [(NSPasteboard.PasteboardType, Data)] = []
        for type in savedTypes {
            if let data = pasteboard.data(forType: type) {
                savedData.append((type, data))
            }
        }

        // Clear clipboard
        pasteboard.clearContents()

        // Send Cmd+C to copy selection
        sendCopy()

        // Delay for clipboard to update
        // Browsers (especially Chromium-based) need more time to process Cmd+C
        Thread.sleep(forTimeInterval: 0.03) // 30ms

        // Check if clipboard now has text
        let copiedText = pasteboard.string(forType: .string)
        let hasNonEmptyText = copiedText != nil && !copiedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Determine if this is a real selection or IDE "copy line" behavior
        var hasSelection = false
        if hasNonEmptyText, let text = copiedText {
            // Check for IDE "copy line" behavior using heuristics
            if isIDECopyLineBehavior(text) {
                hasSelection = false
            } else {
                hasSelection = true
            }
        }

        // Restore original clipboard
        pasteboard.clearContents()
        if !savedData.isEmpty {
            for (type, data) in savedData {
                pasteboard.setData(data, forType: type)
            }
        }

        return SelectionResult(
            hasSelection: hasSelection,
            selectedText: hasSelection ? copiedText : nil,
            source: source
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

    /// Send Cmd+C keystroke to frontmost application
    private static func sendCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)

        // Key down Cmd+C
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) { // 0x08 = 'c'
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Delay between key down and key up
        Thread.sleep(forTimeInterval: 0.005) // 5ms

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

