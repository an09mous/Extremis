// MARK: - Launch at Login Service
// Manages macOS Login Items registration using SMAppService

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    // MARK: - Public Interface

    /// Check if launch at login is currently enabled
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS (shouldn't happen given our target)
            return UserDefaultsHelper.shared.launchAtLogin
        }
    }

    /// Enable or disable launch at login
    /// - Parameter enabled: Whether to enable launch at login
    /// - Returns: True if the operation succeeded
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    print("✅ Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("✅ Launch at login disabled")
                }

                // Also update UserDefaults for consistency
                UserDefaultsHelper.shared.launchAtLogin = enabled
                return true
            } catch {
                print("❌ Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
                return false
            }
        } else {
            // Fallback - just save preference
            UserDefaultsHelper.shared.launchAtLogin = enabled
            return true
        }
    }
}
