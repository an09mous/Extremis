// MARK: - Launch at Login Service
// Manages macOS Login Items registration using SMAppService

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    // MARK: - Public Interface

    /// Check if the app can use launch at login
    /// SMAppService requires the app to be properly signed and installed
    var isAvailable: Bool {
        // Check if running from a proper app bundle (not .build/debug)
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasSuffix(".app")
    }

    /// Check if launch at login is currently enabled
    var isEnabled: Bool {
        guard isAvailable else {
            return UserDefaultsHelper.shared.launchAtLogin
        }

        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaultsHelper.shared.launchAtLogin
        }
    }

    /// Enable or disable launch at login
    /// - Parameter enabled: Whether to enable launch at login
    /// - Returns: True if the operation succeeded, nil if not available
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool? {
        // Save preference regardless (for when app is properly installed later)
        UserDefaultsHelper.shared.launchAtLogin = enabled

        guard isAvailable else {
            print("⚠️ Launch at login not available (app not installed in .app bundle)")
            return nil
        }

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    print("✅ Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("✅ Launch at login disabled")
                }
                return true
            } catch {
                print("❌ Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
                return false
            }
        } else {
            return true
        }
    }
}
