// MARK: - Context Orchestrator
// Coordinates context extraction from the active application

import Foundation
import AppKit

/// Orchestrates context extraction from the active application
/// Uses the extractor registry to find the appropriate extractor
final class ContextOrchestrator {

    // MARK: - Properties

    /// Shared instance
    static let shared = ContextOrchestrator(
        extractorRegistry: ContextExtractorRegistry.shared
    )

    /// Extractor registry
    private let extractorRegistry: ContextExtractorRegistryProtocol

    /// Permission manager
    private let permissionManager: PermissionManager

    // MARK: - Initialization

    init(
        extractorRegistry: ContextExtractorRegistryProtocol,
        permissionManager: PermissionManager = .shared
    ) {
        self.extractorRegistry = extractorRegistry
        self.permissionManager = permissionManager
    }
    
    // MARK: - Public Methods
    
    /// Capture context from the currently active application
    /// - Returns: Captured context
    /// - Throws: ContextExtractionError on failure
    func captureContext() async throws -> Context {
        // Check accessibility permission
        guard permissionManager.isAccessibilityEnabled() else {
            throw ContextExtractionError.accessibilityPermissionDenied
        }
        
        // Get frontmost application info
        let source = try getCurrentContextSource()
        
        // Find appropriate extractor
        let extractor = extractorRegistry.extractor(for: source)
        
        print("📋 Using extractor: \(extractor.displayName) for \(source.applicationName)")
        
        // Extract context
        return try await extractor.extract()
    }
    
    /// Get the current context source (frontmost app info)
    /// - Returns: Context source information
    /// - Throws: ContextExtractionError if unable to determine
    func getCurrentContextSource() throws -> ContextSource {
        guard let app = permissionManager.getFrontmostApplication() else {
            throw ContextExtractionError.unknown("Could not determine frontmost application")
        }
        
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"
        
        // Try to get window title and URL (for browsers)
        let windowTitle = getWindowTitle(for: app)
        let url = getBrowserURL(for: app)
        
        return ContextSource(
            applicationName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: url
        )
    }
    
    // MARK: - Private Methods
    
    /// Get the window title of the frontmost window
    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        // Use Accessibility API to get window title
        guard let pid = app.processIdentifier as pid_t? else { return nil }
        
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        
        guard result == .success, let window = windowValue else { return nil }
        
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        
        guard titleResult == .success, let title = titleValue as? String else { return nil }
        
        return title
    }
    
    /// Get the URL from a browser window using BrowserBridge
    private func getBrowserURL(for app: NSRunningApplication) -> URL? {
        // Use BrowserBridge to get current tab info
        if let tab = BrowserBridge.shared.getCurrentTab(from: app) {
            return tab.url
        }
        return nil
    }

    /// Check if an application is a browser
    static func isBrowser(bundleId: String?, appName: String?) -> Bool {
        // Check by bundle ID
        if let bundleId = bundleId {
            let browserBundleIds: Set<String> = [
                "com.apple.Safari",
                "com.google.Chrome",
                "org.mozilla.firefox",
                "com.microsoft.edgemac",
                "com.brave.Browser",
                "com.operasoftware.Opera",
                "company.thebrowser.Browser",  // Arc
            ]
            if browserBundleIds.contains(bundleId) {
                return true
            }
        }

        // Check by app name (for apps like "Comet" or unknown browsers)
        if let name = appName?.lowercased() {
            let browserNames = ["chrome", "safari", "firefox", "edge", "brave", "arc", "comet", "browser", "opera"]
            if browserNames.contains(where: { name.contains($0) }) {
                return true
            }
        }

        return false
    }
}

