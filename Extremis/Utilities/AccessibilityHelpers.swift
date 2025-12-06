// MARK: - Accessibility Helpers
// Utilities for working with macOS Accessibility APIs

import Foundation
import AppKit
import ApplicationServices

/// Utilities for working with macOS Accessibility APIs
enum AccessibilityHelpers {
    
    // MARK: - Element Queries
    
    /// Get the focused UI element from an application
    /// - Parameter app: The application to query
    /// - Returns: The focused AXUIElement, or nil if not found
    static func getFocusedElement(from app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success else { return nil }
        return (focusedElement as! AXUIElement)
    }
    
    /// Get the focused window from an application
    /// - Parameter app: The application to query
    /// - Returns: The focused window AXUIElement, or nil if not found
    static func getFocusedWindow(from app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        
        guard result == .success else { return nil }
        return (windowValue as! AXUIElement)
    }
    
    // MARK: - Attribute Getters
    
    /// Get a string attribute from an element
    /// - Parameters:
    ///   - element: The AXUIElement to query
    ///   - attribute: The attribute name
    /// - Returns: The attribute value as String, or nil
    static func getString(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
    
    /// Get the selected text from an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: The selected text, or nil
    static func getSelectedText(from element: AXUIElement) -> String? {
        return getString(from: element, attribute: kAXSelectedTextAttribute)
    }
    
    /// Get the value (full text) from an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: The element's value, or nil
    static func getValue(from element: AXUIElement) -> String? {
        return getString(from: element, attribute: kAXValueAttribute)
    }
    
    /// Get the role of an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: The element's role, or nil
    static func getRole(from element: AXUIElement) -> String? {
        return getString(from: element, attribute: kAXRoleAttribute)
    }
    
    /// Get the title of an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: The element's title, or nil
    static func getTitle(from element: AXUIElement) -> String? {
        return getString(from: element, attribute: kAXTitleAttribute)
    }
    
    /// Get the description of an element
    /// - Parameter element: The AXUIElement to query
    /// - Returns: The element's description, or nil
    static func getDescription(from element: AXUIElement) -> String? {
        return getString(from: element, attribute: kAXDescriptionAttribute)
    }
    
    // MARK: - Attribute Setters
    
    /// Set the value of an element
    /// - Parameters:
    ///   - element: The AXUIElement to modify
    ///   - value: The new value
    /// - Returns: true if successful
    @discardableResult
    static func setValue(_ value: String, on element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
        return result == .success
    }
    
    /// Set the selected text of an element
    /// - Parameters:
    ///   - element: The AXUIElement to modify
    ///   - text: The text to set as selected
    /// - Returns: true if successful
    @discardableResult
    static func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }
    
    // MARK: - Element Checks
    
    /// Check if an element is a text field or text area
    /// - Parameter element: The AXUIElement to check
    /// - Returns: true if the element accepts text input
    static func isTextInput(_ element: AXUIElement) -> Bool {
        guard let role = getRole(from: element) else { return false }
        let textRoles: [String] = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"  // Search field role
        ]
        return textRoles.contains(role)
    }
    
    /// Check if an element is editable
    /// - Parameter element: The AXUIElement to check
    /// - Returns: true if the element is editable
    static func isEditable(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            "AXEditable" as CFString,
            &value
        )
        guard result == .success else { return false }
        return (value as? Bool) ?? false
    }
}

