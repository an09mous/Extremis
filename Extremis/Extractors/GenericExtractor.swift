// MARK: - Generic Context Extractor
// Fallback extractor for unsupported applications

import Foundation
import AppKit
import ApplicationServices

/// Generic context extractor that works with any application
/// Uses Accessibility APIs to extract selected text and focused element info
final class GenericExtractor: ContextExtractor {
    
    // MARK: - ContextExtractor Protocol
    
    var identifier: String { "generic" }
    
    var displayName: String { "Generic Text Extractor" }
    
    var supportedBundleIdentifiers: [String] { [] }
    
    var supportedURLPatterns: [String] { [] }
    
    func canExtract(from source: ContextSource) -> Bool {
        // Generic extractor can always attempt extraction
        return true
    }
    
    func extract() async throws -> Context {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ContextExtractionError.unknown("No frontmost application")
        }

        let source = ContextSource(
            applicationName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )

        // Try to get selected text using Accessibility API
        let selectedText = try? getSelectedText(from: app)

        // Get focused element info
        let focusedInfo = getFocusedElementInfo(from: app)

        return Context(
            source: source,
            selectedText: selectedText,
            precedingText: nil,
            succeedingText: nil,
            metadata: .generic(GenericMetadata(
                focusedElementRole: focusedInfo.role,
                focusedElementLabel: focusedInfo.label
            ))
        )
    }
    
    // MARK: - Private Methods
    
    /// Get selected text using Accessibility API
    private func getSelectedText(from app: NSRunningApplication) throws -> String? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard focusResult == .success, let element = focusedElement else {
            return nil
        }
        
        // Try to get selected text
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        // Fallback: try to get value
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            &value
        )
        
        if valueResult == .success, let text = value as? String {
            return text
        }
        
        return nil
    }
    
    /// Get information about the focused element
    private func getFocusedElementInfo(from app: NSRunningApplication) -> (role: String?, label: String?) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard focusResult == .success, let element = focusedElement else {
            return (nil, nil)
        }
        
        // Get role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXRoleAttribute as CFString,
            &role
        )
        
        // Get label/description
        var label: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXDescriptionAttribute as CFString,
            &label
        )
        
        return (role as? String, label as? String)
    }
}

