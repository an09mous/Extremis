// MARK: - Browser Bridge
// Utility for extracting content from browser tabs using AppleScript

import Foundation
import AppKit

/// Bridge for communicating with browsers via AppleScript
@MainActor
final class BrowserBridge {
    
    // MARK: - Types
    
    enum Browser: String, CaseIterable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case firefox = "org.mozilla.firefox"
        case edge = "com.microsoft.edgemac"
        case brave = "com.brave.Browser"
        case arc = "company.thebrowser.Browser"
        case comet = "com.electron.nicegram" // Comet browser
        case opera = "com.operasoftware.Opera"

        var name: String {
            switch self {
            case .safari: return "Safari"
            case .chrome: return "Google Chrome"
            case .firefox: return "Firefox"
            case .edge: return "Microsoft Edge"
            case .brave: return "Brave Browser"
            case .arc: return "Arc"
            case .comet: return "Comet"
            case .opera: return "Opera"
            }
        }

        var isChromiumBased: Bool {
            switch self {
            case .chrome, .edge, .brave, .arc, .comet, .opera:
                return true
            case .safari, .firefox:
                return false
            }
        }
    }
    
    struct BrowserTab {
        let url: URL?
        let title: String?
    }
    
    // MARK: - Properties
    
    static let shared = BrowserBridge()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get the current tab info from the frontmost browser
    func getCurrentTab(from app: NSRunningApplication) -> BrowserTab? {
        guard let bundleId = app.bundleIdentifier else { return nil }

        // Try known browser first
        if let browser = Browser(rawValue: bundleId) {
            print("🔗 BrowserBridge: Known browser: \(browser.name)")
            switch browser {
            case .safari:
                return getSafariTab()
            case .firefox:
                return getFirefoxTab()
            default:
                if browser.isChromiumBased {
                    return getChromiumTab(browser: browser)
                }
            }
        }

        // Fallback: Try to get tab using app name (for unknown browsers)
        if let appName = app.localizedName {
            print("🔗 BrowserBridge: Trying fallback with app name: \(appName)")
            return getChromiumTabByName(appName: appName)
        }

        return nil
    }

    /// Execute JavaScript in the current browser tab
    func executeJavaScript(_ script: String, in app: NSRunningApplication) -> String? {
        guard let bundleId = app.bundleIdentifier else { return nil }

        // Try known browser first
        if let browser = Browser(rawValue: bundleId) {
            print("🔗 BrowserBridge: Executing JS in known browser: \(browser.name)")
            switch browser {
            case .safari:
                return executeSafariJS(script)
            case .firefox:
                return nil // Firefox doesn't support JS via AppleScript
            default:
                if browser.isChromiumBased {
                    return executeChromiumJS(script, browser: browser)
                }
            }
        }

        // Fallback: Try Chromium-style JS execution with app name
        if let appName = app.localizedName {
            print("🔗 BrowserBridge: Trying JS execution fallback with app name: \(appName)")
            return executeChromiumJSByName(script, appName: appName)
        }

        return nil
    }
    
    // MARK: - Safari
    
    private func getSafariTab() -> BrowserTab? {
        let script = """
        tell application "Safari"
            set theURL to URL of current tab of front window
            set theTitle to name of current tab of front window
            return theURL & "|||" & theTitle
        end tell
        """
        
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        
        return BrowserTab(
            url: parts.first.flatMap { URL(string: $0) },
            title: parts.count > 1 ? parts[1] : nil
        )
    }
    
    private func executeSafariJS(_ script: String) -> String? {
        let escaped = script.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        tell application "Safari"
            do JavaScript "\(escaped)" in current tab of front window
        end tell
        """
        return runAppleScript(appleScript)
    }
    
    // MARK: - Chromium-based browsers
    
    private func getChromiumTab(browser: Browser) -> BrowserTab? {
        let script = """
        tell application "\(browser.name)"
            set theURL to URL of active tab of front window
            set theTitle to title of active tab of front window
            return theURL & "|||" & theTitle
        end tell
        """
        
        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        
        return BrowserTab(
            url: parts.first.flatMap { URL(string: $0) },
            title: parts.count > 1 ? parts[1] : nil
        )
    }
    
    private func executeChromiumJS(_ script: String, browser: Browser) -> String? {
        return executeChromiumJSByName(script, appName: browser.name)
    }

    // MARK: - Fallback methods for unknown browsers

    private func getChromiumTabByName(appName: String) -> BrowserTab? {
        let script = """
        tell application "\(appName)"
            set theURL to URL of active tab of front window
            set theTitle to title of active tab of front window
            return theURL & "|||" & theTitle
        end tell
        """

        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")

        return BrowserTab(
            url: parts.first.flatMap { URL(string: $0) },
            title: parts.count > 1 ? parts[1] : nil
        )
    }

    private func executeChromiumJSByName(_ script: String, appName: String) -> String? {
        let escaped = script.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        tell application "\(appName)"
            execute active tab of front window javascript "\(escaped)"
        end tell
        """
        return runAppleScript(appleScript)
    }

    // MARK: - Firefox

    private func getFirefoxTab() -> BrowserTab? {
        // Firefox has limited AppleScript support
        let script = """
        tell application "Firefox" to return name of front window
        """
        let title = runAppleScript(script)
        return BrowserTab(url: nil, title: title)
    }

    // MARK: - AppleScript Execution

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)

        if let error = error {
            print("⚠️ AppleScript error: \(error)")
            return nil
        }

        return result.stringValue
    }
}

