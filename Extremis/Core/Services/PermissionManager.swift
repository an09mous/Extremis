// MARK: - Permission Manager
// Handles macOS accessibility and other permissions

import Foundation
import AppKit
import ApplicationServices

/// Manages macOS permissions required by Extremis
final class PermissionManager {
    
    // MARK: - Types
    
    /// Permission status
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
    }
    
    // MARK: - Properties
    
    /// Singleton instance
    static let shared = PermissionManager()
    
    /// Current accessibility permission status
    var accessibilityStatus: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if accessibility permission is granted
    /// - Returns: true if accessibility is enabled
    func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permission
    /// Shows the system prompt to enable accessibility
    /// - Returns: true if permission is already granted
    @discardableResult
    func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Open System Preferences to Accessibility pane
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    /// Check all required permissions
    /// - Returns: Dictionary of permission names to their status
    func checkAllPermissions() -> [String: PermissionStatus] {
        return [
            "Accessibility": accessibilityStatus
        ]
    }
    
    /// Prompt for all missing permissions
    func requestMissingPermissions() {
        if !isAccessibilityEnabled() {
            requestAccessibility()
        }
    }
    
    // MARK: - Permission Helpers
    
    /// Get the frontmost application
    /// - Returns: The frontmost application, or nil if unavailable
    func getFrontmostApplication() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    /// Get the bundle identifier of the frontmost application
    /// - Returns: Bundle identifier, or "unknown" if unavailable
    func getFrontmostBundleIdentifier() -> String {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }
    
    /// Get the name of the frontmost application
    /// - Returns: Application name, or "Unknown" if unavailable
    func getFrontmostApplicationName() -> String {
        return NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }
}

// MARK: - Accessibility Status Extension

extension PermissionManager.PermissionStatus: CustomStringConvertible {
    var description: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        }
    }
    
    var symbol: String {
        switch self {
        case .granted: return "✅"
        case .denied: return "❌"
        case .notDetermined: return "⚠️"
        }
    }
}

