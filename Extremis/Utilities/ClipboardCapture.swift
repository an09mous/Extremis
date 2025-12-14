// MARK: - Clipboard Capture Utility
// Uses CGEvent to capture content around cursor via Cmd+Shift+Up/Down, Cmd+C

import Foundation
import AppKit
import CoreGraphics

/// Utility for capturing visible content from any application using keyboard simulation
final class ClipboardCapture {

    static let shared = ClipboardCapture()

    private init() {}

    // MARK: - Individual Captures

    // Space marker - universal, works in all editors
    private let marker = " "

    /// Capture content BEFORE the cursor position using marker-based approach
    /// Flow: Type marker → Cmd+Shift+Up → Cmd+C → Right → Backspace → Strip marker from text
    /// - Parameter verbose: Whether to print detailed logs
    /// - Returns: The captured text content, or nil if capture failed
    func captureVisibleContent(verbose: Bool = true) -> String? {
        if verbose {
            print("\n" + String(repeating: "=", count: 70))
            print("📋 CLIPBOARD CAPTURE (Marker-based - Before Cursor)")
            print(String(repeating: "=", count: 70))
        }

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedClipboard = saveClipboard(pasteboard)

        if verbose {
            print("\n📋 STEP 1: Saved original clipboard (\(savedClipboard.count) types)")
        }

        // Clear clipboard
        pasteboard.clearContents()

        // Release any held modifiers from hotkey (important for Cmd+Shift+Space hotkey)
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        if verbose {
            print("\n⚡ Step 2: Typing space marker...")
        }

        // Type the marker character at cursor position
        typeText(marker)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 3: Cmd+Shift+Up (select before cursor including marker)...")
        }

        // Simulate Cmd+Shift+Up (Select all content BEFORE cursor, including marker)
        simulateKeyPress(keyCode: 0x7E, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 4: Cmd+C (copy selection)...")
        }

        // Simulate Cmd+C (Copy)
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.05)

        // Release all modifiers
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 5: Right arrow (deselect, cursor at marker)...")
        }

        // Right arrow to deselect and position cursor at end of selection (after marker)
        simulateKeyPress(keyCode: 0x7C, withCommand: false, withShift: false)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 6: Backspace (delete marker)...")
        }

        // Backspace to delete the marker
        simulateKeyPress(keyCode: 0x33, withCommand: false, withShift: false) // 0x33 = Backspace
        Thread.sleep(forTimeInterval: 0.05)

        // Read clipboard content
        var copiedContent = pasteboard.string(forType: .string)

        // Strip the marker from the end of copied text
        if let content = copiedContent, content.hasSuffix(marker) {
            copiedContent = String(content.dropLast(marker.count))
        }

        if verbose {
            print("\n📋 RESULT: Captured preceding content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent, !content.isEmpty {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                let preview = content.count > 200 ? String(content.suffix(200)) + "..." : content
                print(preview)
                print(String(repeating: "-", count: 50))
            } else {
                print("  (empty - cursor was at start)")
            }
        }

        // Restore original clipboard
        restoreClipboard(pasteboard, from: savedClipboard)

        if verbose {
            print("\n✅ Restored original clipboard")
            print(String(repeating: "=", count: 70) + "\n")
        }

        return copiedContent?.isEmpty == true ? nil : copiedContent
    }

    /// Capture content AFTER the cursor position using marker-based approach
    /// Flow: Type marker → Left → Cmd+Shift+Down → Cmd+C → Left → Delete → Strip marker from text
    /// - Parameter verbose: Whether to print detailed logs
    /// - Returns: The captured text content, or nil if capture failed
    func captureSucceedingContent(verbose: Bool = true) -> String? {
        if verbose {
            print("\n" + String(repeating: "=", count: 70))
            print("📋 CLIPBOARD CAPTURE (Marker-based - After Cursor)")
            print(String(repeating: "=", count: 70))
        }

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedClipboard = saveClipboard(pasteboard)

        if verbose {
            print("\n📋 STEP 1: Saved original clipboard (\(savedClipboard.count) types)")
        }

        // Clear clipboard
        pasteboard.clearContents()

        // Release any held modifiers from hotkey (important for Cmd+Shift+Space hotkey)
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        if verbose {
            print("\n⚡ Step 2: Typing space marker...")
        }

        // Type the marker character at cursor position
        typeText(marker)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 3: Left arrow (move cursor before marker)...")
        }

        // Move cursor before the marker
        simulateKeyPress(keyCode: 0x7B, withCommand: false, withShift: false) // 0x7B = Left Arrow
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 4: Cmd+Shift+Down (select after cursor including marker)...")
        }

        // Simulate Cmd+Shift+Down (Select all content AFTER cursor, including marker)
        simulateKeyPress(keyCode: 0x7D, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 5: Cmd+C (copy selection)...")
        }

        // Simulate Cmd+C (Copy)
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.05)

        // Release all modifiers
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 6: Left arrow (deselect, cursor at original position)...")
        }

        // Left arrow to deselect and position cursor at start of selection (original position)
        simulateKeyPress(keyCode: 0x7B, withCommand: false, withShift: false)
        Thread.sleep(forTimeInterval: 0.05)

        if verbose {
            print("⚡ Step 7: Delete (forward delete marker)...")
        }

        // Forward delete (fn+Backspace) to delete the marker which is now after cursor
        simulateKeyPress(keyCode: 0x75, withCommand: false, withShift: false) // 0x75 = Forward Delete
        Thread.sleep(forTimeInterval: 0.05)

        // Read clipboard content
        var copiedContent = pasteboard.string(forType: .string)

        // Strip the marker from the beginning of copied text
        if let content = copiedContent, content.hasPrefix(marker) {
            copiedContent = String(content.dropFirst(marker.count))
        }

        if verbose {
            print("\n📋 RESULT: Captured succeeding content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent, !content.isEmpty {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                let preview = content.count > 200 ? String(content.prefix(200)) + "..." : content
                print(preview)
                print(String(repeating: "-", count: 50))
            } else {
                print("  (empty - cursor was at end)")
            }
        }

        // Restore original clipboard
        restoreClipboard(pasteboard, from: savedClipboard)

        if verbose {
            print("\n✅ Restored original clipboard")
            print(String(repeating: "=", count: 70) + "\n")
        }

        return copiedContent?.isEmpty == true ? nil : copiedContent
    }

    // MARK: - Private Methods

    /// Release any stuck modifier keys by sending key-up events
    private func releaseModifiers() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Release Shift (key code 0x38 for left shift)
        if let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: 0x38, keyDown: false) {
            shiftUp.post(tap: .cghidEventTap)
        }

        // Release Command (key code 0x37 for left command)
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            cmdUp.post(tap: .cghidEventTap)
        }

        // Also post a flags-changed event with no flags to clear modifier state
        if let flagsEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            flagsEvent.flags = []
            flagsEvent.type = .flagsChanged
            flagsEvent.post(tap: .cghidEventTap)
        }
    }

    /// Simulate a key press using CGEvent
    /// - Parameters:
    ///   - keyCode: The virtual key code to simulate
    ///   - withCommand: Whether to include Command modifier
    ///   - withShift: Whether to include Shift modifier
    ///   - withOption: Whether to include Option/Alt modifier
    private func simulateKeyPress(keyCode: CGKeyCode, withCommand: Bool, withShift: Bool = false, withOption: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Build modifier flags
        var flags: CGEventFlags = []
        if withCommand {
            flags.insert(.maskCommand)
        }
        if withShift {
            flags.insert(.maskShift)
        }
        if withOption {
            flags.insert(.maskAlternate)
        }

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            if !flags.isEmpty {
                keyDown.flags = flags
            }
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay between down and up
        Thread.sleep(forTimeInterval: 0.05)

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            if !flags.isEmpty {
                keyUp.flags = flags
            }
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    /// Type a space by simulating actual space bar keypress (keycode 0x31)
    private func typeText(_ text: String) {
        // For space marker, use actual space bar keypress which works universally
        simulateKeyPress(keyCode: 0x31, withCommand: false, withShift: false) // 0x31 = Space
    }

    /// Save clipboard contents
    private func saveClipboard(_ pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var savedData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedData[type] = data
            }
        }
        return savedData
    }

    /// Restore clipboard contents
    private func restoreClipboard(_ pasteboard: NSPasteboard, from savedData: [NSPasteboard.PasteboardType: Data]) {
        pasteboard.clearContents()
        for (type, data) in savedData {
            pasteboard.setData(data, forType: type)
        }
    }
}

