// MARK: - Browser Context Extractor
// Extracts context from browser pages using Accessibility APIs

import Foundation
import AppKit
import ApplicationServices

/// Extracts context from any browser page using Accessibility APIs
final class BrowserExtractor: ContextExtractor {

    // MARK: - ContextExtractor Protocol

    var identifier: String { "browser" }
    var displayName: String { "Browser Extractor" }
    var supportedBundleIdentifiers: [String] {
        BrowserBridge.Browser.allCases.map { $0.rawValue }
    }
    var supportedURLPatterns: [String] { [] }

    func canExtract(from source: ContextSource) -> Bool {
        // Match any browser by bundle ID
        if supportedBundleIdentifiers.contains(source.bundleIdentifier) {
            return true
        }

        // Also match by app name for browsers like "Comet"
        return ContextOrchestrator.isBrowser(
            bundleId: source.bundleIdentifier,
            appName: source.applicationName
        )
    }

    func extract() async throws -> Context {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ContextExtractionError.unknown("No frontmost application")
        }

        let pid = app.processIdentifier
        print("🌐 BrowserExtractor: App = \(app.localizedName ?? "unknown")")
        print("🌐 BrowserExtractor: BundleID = \(app.bundleIdentifier ?? "unknown")")
        print("🌐 BrowserExtractor: PID = \(pid)")

        // Extract using Accessibility APIs
        let appElement = AXUIElementCreateApplication(pid)

        // Get focused element info (the text field user is typing in)
        let focusedInfo = getFocusedElementInfo(appElement)
        print("🌐 BrowserExtractor: Focused element role = \(focusedInfo.role ?? "nil")")
        print("🌐 BrowserExtractor: Focused element value length = \(focusedInfo.value?.count ?? 0)")

        // Get selected text from focused element
        let selectedText = getSelectedText(appElement)
        print("🌐 BrowserExtractor: Selected text length = \(selectedText?.count ?? 0)")

        // Get window title
        let windowTitle = getWindowTitle(appElement)
        print("🌐 BrowserExtractor: Window title = \(windowTitle ?? "nil")")

        // Capture preceding text via clipboard
        print("🌐 BrowserExtractor: Capturing preceding text via clipboard...")
        let precedingText = ClipboardCapture.shared.captureVisibleContent(verbose: true) ?? ""
        print("🌐 BrowserExtractor: Clipboard captured \(precedingText.count) chars")

        let source = ContextSource(
            applicationName: app.localizedName ?? "Browser",
            bundleIdentifier: app.bundleIdentifier ?? "",
            windowTitle: windowTitle,
            url: nil
        )

        return Context(
            source: source,
            selectedText: selectedText,
            precedingText: precedingText,
            metadata: .generic(GenericMetadata(
                focusedElementRole: focusedInfo.role,
                focusedElementLabel: focusedInfo.label
            ))
        )
    }

    // MARK: - Accessibility Helpers

    private func getFocusedElementInfo(_ appElement: AXUIElement) -> (role: String?, label: String?, value: String?) {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return (nil, nil, nil)
        }

        let axElement = element as! AXUIElement

        // Get role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)

        // Get role description (more human-readable)
        var roleDesc: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleDescriptionAttribute as CFString, &roleDesc)

        // Get label/description
        var label: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &label)

        // Get value (text content)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value)

        return (
            role: (roleDesc as? String) ?? (role as? String),
            label: label as? String,
            value: value as? String
        )
    }

    private func getSelectedText(_ appElement: AXUIElement) -> String? {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return nil
        }

        var selectedText: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        if let text = selectedText as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    private func getWindowTitle(_ appElement: AXUIElement) -> String? {
        // Get focused window
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else {
            return nil
        }

        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)

        return title as? String
    }

    private func extractWebAreaContent(_ appElement: AXUIElement) -> String {
        // Find AXWebArea in the hierarchy
        guard let webArea = findWebArea(appElement) else {
            print("🌐 BrowserExtractor: Could not find AXWebArea")
            return ""
        }

        print("🌐 BrowserExtractor: Found AXWebArea, extracting content...")

        // Extract content from web area
        var contents: [String] = []
        extractContentFromElement(webArea, contents: &contents, depth: 0, maxDepth: 10)

        // Limit and join
        let limitedContents = contents.prefix(100)
        let result = limitedContents.joined(separator: "\n")

        // Truncate if too long
        if result.count > 4000 {
            return String(result.prefix(4000)) + "\n... [truncated]"
        }

        return result
    }

    private func findWebArea(_ element: AXUIElement) -> AXUIElement? {
        // Check if this element is AXWebArea
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let roleStr = role as? String, roleStr == "AXWebArea" {
            return element
        }

        // Search children
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        guard let childArray = children as? [AXUIElement] else {
            return nil
        }

        for child in childArray {
            if let webArea = findWebArea(child) {
                return webArea
            }
        }

        return nil
    }

    private func extractContentFromElement(_ element: AXUIElement, contents: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth, contents.count < 100 else { return }

        // Get role
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        // Get value/text
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let valueStr = value as? String

        // Get title
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let titleStr = title as? String

        // Extract based on role
        switch roleStr {
        case "AXHeading":
            if let text = valueStr ?? titleStr, !text.isEmpty {
                contents.append("## \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        case "AXStaticText":
            if let text = valueStr, !text.isEmpty, text.count > 2 {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count < 500 {
                    contents.append(trimmed)
                }
            }
        case "AXLink":
            if let text = titleStr ?? valueStr, !text.isEmpty {
                contents.append("[\(text.trimmingCharacters(in: .whitespacesAndNewlines))]")
            }
        case "AXTextField", "AXTextArea":
            if let text = valueStr, !text.isEmpty {
                contents.append("Input: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        case "AXButton":
            if let text = titleStr ?? valueStr, !text.isEmpty {
                contents.append("Button: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        default:
            break
        }

        // Recurse into children
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        guard let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            extractContentFromElement(child, contents: &contents, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
