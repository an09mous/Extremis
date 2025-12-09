// MARK: - Clipboard Capture Utility
// Uses CGEvent to capture content BEFORE cursor via Cmd+Shift+Up, Cmd+C

import Foundation
import AppKit
import CoreGraphics

/// Utility for capturing visible content from any application using keyboard simulation
final class ClipboardCapture {

    static let shared = ClipboardCapture()

    private init() {}

    /// Capture content BEFORE the cursor position using Cmd+Shift+Up, Cmd+C
    /// This preserves the original cursor position by using Right Arrow after copy
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
            print("\n⚡ Simulating Cmd+Shift+Up (select before cursor), Cmd+C, Right Arrow...")
        }

        // Simulate Cmd+Shift+Up (Select all content BEFORE cursor)
        // Key code for Up Arrow is 0x7E
        simulateKeyPress(keyCode: 0x7E, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.3)

        // Simulate Cmd+C (Copy) - Key code for 'C' is 0x08
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.3)

        // Release all modifiers by sending key-up events for Shift and Command
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        // Simulate Right Arrow to deselect and move to END of selection (original cursor position)
        // Key code for Right Arrow is 0x7C
        simulateKeyPress(keyCode: 0x7C, withCommand: false, withShift: false)

        // Small delay to let clipboard update
        Thread.sleep(forTimeInterval: 0.15)
        
        // Read clipboard content
        let copiedContent = pasteboard.string(forType: .string)
        
        if verbose {
            print("\n📋 STEP 2: Captured content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                // Print full content for debugging
                print(content)
                print(String(repeating: "-", count: 50))
            } else {
                print("  ❌ NO CONTENT CAPTURED")
                print("  Possible reasons:")
                print("    - App doesn't support Cmd+A selection")
                print("    - Focus was not on selectable content")
                print("    - Accessibility permission issue")
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
    /// This preserves the original cursor position by using Left Arrow after copy
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
            print("\n⚡ Simulating Cmd+Shift+Down (select after cursor), Cmd+C, Left Arrow...")
        }

        // Simulate Cmd+Shift+Down (Select all content AFTER cursor)
        // Key code for Down Arrow is 0x7D
        simulateKeyPress(keyCode: 0x7D, withCommand: true, withShift: true)
        Thread.sleep(forTimeInterval: 0.3)

        // Simulate Cmd+C (Copy) - Key code for 'C' is 0x08
        simulateKeyPress(keyCode: 0x08, withCommand: true, withShift: false)
        Thread.sleep(forTimeInterval: 0.3)

        // Release all modifiers
        releaseModifiers()
        Thread.sleep(forTimeInterval: 0.1)

        // Simulate Left Arrow to deselect and move to START of selection (original cursor position)
        // Key code for Left Arrow is 0x7B
        simulateKeyPress(keyCode: 0x7B, withCommand: false, withShift: false)

        // Small delay to let clipboard update
        Thread.sleep(forTimeInterval: 0.15)

        // Read clipboard content
        let copiedContent = pasteboard.string(forType: .string)

        if verbose {
            print("\n📋 STEP 2: Captured succeeding content")
            print(String(repeating: "-", count: 50))
            if let content = copiedContent {
                print("  Length: \(content.count) characters")
                print(String(repeating: "-", count: 50))
                print(content)
                print(String(repeating: "-", count: 50))
            } else {
                print("  ❌ NO CONTENT CAPTURED (cursor may be at end of document)")
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

