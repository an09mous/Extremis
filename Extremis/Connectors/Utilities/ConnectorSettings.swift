// MARK: - Connector Settings
// UserDefaults extensions for built-in connector settings

import Foundation

// MARK: - Built-in Connector Settings

extension UserDefaults {

    // MARK: - Shell Connector

    /// Whether the shell connector is enabled
    /// Defaults to true (enabled by default per user requirement)
    var shellConnectorEnabled: Bool {
        get {
            // Return true if key doesn't exist (default enabled)
            if object(forKey: "shellConnectorEnabled") == nil {
                return true
            }
            return bool(forKey: "shellConnectorEnabled")
        }
        set {
            set(newValue, forKey: "shellConnectorEnabled")
        }
    }

    // MARK: - GitHub Connector

    /// Whether the GitHub connector is enabled
    /// Defaults to false (requires token configuration)
    var githubConnectorEnabled: Bool {
        get {
            // Return false if key doesn't exist (disabled by default - requires token)
            if object(forKey: "githubConnectorEnabled") == nil {
                return false
            }
            return bool(forKey: "githubConnectorEnabled")
        }
        set {
            set(newValue, forKey: "githubConnectorEnabled")
        }
    }

    // MARK: - Security Settings

    /// Whether sudo mode is enabled (bypasses all tool approval)
    /// Defaults to false for security
    var sudoModeEnabled: Bool {
        get { bool(forKey: "sudoModeEnabled") }
        set { set(newValue, forKey: "sudoModeEnabled") }
    }
}
