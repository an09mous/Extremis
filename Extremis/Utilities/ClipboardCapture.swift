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

    /// Capture content BEFORE the cursor position using Cmd+Shift+Up, Cmd+C
    /// Only presses Right Arrow if content was actually copied (to preserve cursor position)
    /// - Parameter verbose: Whether to print detailed logs
    /// - Returns: The captured text content, or nil if capture failed
    func captureVisibleContent(verbose: Bool = true) -> String? {
        if verbose {
            print("\n" + String(repeating: "=", count: 70))
            print("📋 CLIPBOARD CAPTURE (CGEvent - Before Cursor)")
            print(String(repeating: "=", count: 70))
        }

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedClipboard = saveClipboard(pasteboard)

        if verbose {
            print("\n📋 STEP 1: Saved original clipboard (\(savedClipboard.count) types)")
            if let originalText = pasteboard.string(forType: .string) {
                print("  Original content preview: \(originalText.prefix(100))...")
            }
        }

        // Clear clipboard
        pasteboard.clearContents()

        if verbose {
            print("\n⚡ Simulating Cmd+Shift+Up (select before cursor), Cmd+C...")
        }

        // Simulate Cmd+Shift+Up (Select all content BEFORE cursor)
        simulateKeyPress(keyCode: 0x7E, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.3)

        // Simulate Cmd+C (Copy)
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.3)

        // Release all modifiers
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        // Read clipboard content
        let copiedContent = pasteboard.string(forType: .string)

        // Only press Right Arrow if something was actually copied
        // If clipboard is empty, cursor was at start - don't press arrow to avoid shifting
        if let content = copiedContent, !content.isEmpty {
            if verbose {
                print("⚡ Content copied, pressing Right Arrow to restore cursor position...")
            }
            simulateKeyPress(keyCode: 0x7C, withCommand: false, withShift: false)
            Thread.sleep(forTimeInterval: 0.15)
        } else {
            if verbose {
                print("   ✓ No content copied (cursor at start) - skipping arrow key")
            }
        }

        if verbose {
            print("\n📋 STEP 2: Captured content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent, !content.isEmpty {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                print(content)
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

        return copiedContent
    }

    /// Capture content AFTER the cursor position using Cmd+Shift+Down, Cmd+C
    /// Only presses Left Arrow if content was actually copied (to preserve cursor position)
    /// - Parameter verbose: Whether to print detailed logs
    /// - Returns: The captured text content, or nil if capture failed
    func captureSucceedingContent(verbose: Bool = true) -> String? {
        if verbose {
            print("\n" + String(repeating: "=", count: 70))
            print("📋 CLIPBOARD CAPTURE (CGEvent - After Cursor)")
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

        if verbose {
            print("\n⚡ Simulating Cmd+Shift+Down (select after cursor), Cmd+C...")
        }

        // Simulate Cmd+Shift+Down (Select all content AFTER cursor)
        simulateKeyPress(keyCode: 0x7D, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.3)

        // Simulate Cmd+C (Copy)
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.3)

        // Release all modifiers
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        // Read clipboard content
        let copiedContent = pasteboard.string(forType: .string)

        // Only press Left Arrow if something was actually copied
        // If clipboard is empty, cursor was at end - don't press arrow to avoid shifting
        if let content = copiedContent, !content.isEmpty {
            if verbose {
                print("⚡ Content copied, pressing Left Arrow to restore cursor position...")
            }
            simulateKeyPress(keyCode: 0x7B, withCommand: false, withShift: false)
            Thread.sleep(forTimeInterval: 0.15)
        } else {
            if verbose {
                print("   ✓ No content copied (cursor at end) - skipping arrow key")
            }
        }

        if verbose {
            print("\n📋 STEP 2: Captured succeeding content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent, !content.isEmpty {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                print(content)
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

        return copiedContent
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
    private func simulateKeyPress(keyCode: CGKeyCode, withCommand: Bool, withShift: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Build modifier flags
        var flags: CGEventFlags = []
        if withCommand {
            flags.insert(.maskCommand)
        }
        if withShift {
            flags.insert(.maskShift)
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

