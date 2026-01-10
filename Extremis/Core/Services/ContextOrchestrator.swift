// MARK: - Context Orchestrator
// Provides utility methods for context-related operations

import Foundation
import AppKit

/// Utility class for context-related operations
/// Note: Context capture is now handled by SelectionDetector directly
enum ContextOrchestrator {

    // MARK: - Static Utilities

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
