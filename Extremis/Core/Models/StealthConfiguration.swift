// MARK: - Stealth Configuration
// UserDefaults-backed settings for stealth mode

import Foundation
import Carbon.HIToolbox

/// UserDefaults extension for stealth mode settings
extension UserDefaults {

    /// Whether stealth mode is currently active (persisted across launches)
    var stealthModeEnabled: Bool {
        get { bool(forKey: "stealth_mode_enabled") }
        set { set(newValue, forKey: "stealth_mode_enabled") }
    }

    /// Key code for stealth toggle shortcut (default: S key)
    var stealthToggleKeycode: UInt32 {
        get {
            let val = integer(forKey: "stealth_toggle_keycode")
            return val == 0 ? UInt32(kVK_ANSI_S) : UInt32(val)
        }
        set { set(Int(newValue), forKey: "stealth_toggle_keycode") }
    }

    /// Modifier flags for stealth toggle shortcut (default: Option+Shift)
    var stealthToggleModifiers: UInt32 {
        get {
            let val = integer(forKey: "stealth_toggle_modifiers")
            return val == 0 ? UInt32(optionKey | shiftKey) : UInt32(val)
        }
        set { set(Int(newValue), forKey: "stealth_toggle_modifiers") }
    }

    /// Whether to disguise the process name in Activity Monitor
    var stealthProcessDisguise: Bool {
        get {
            // Default to true if never set
            if object(forKey: "stealth_process_disguise") == nil { return true }
            return bool(forKey: "stealth_process_disguise")
        }
        set { set(newValue, forKey: "stealth_process_disguise") }
    }

    /// Disguised process name (default: com.apple.hiservices-xpcservice)
    var stealthDisguiseName: String {
        get { string(forKey: "stealth_disguise_name") ?? "com.apple.hiservices-xpcservice" }
        set { set(newValue, forKey: "stealth_disguise_name") }
    }
}

/// Stealth-specific hotkey configuration helpers
struct StealthHotkeyConfig {
    /// Default stealth toggle hotkey: Option+Shift+S
    static var stealthToggle: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: UserDefaults.standard.stealthToggleKeycode,
            modifiers: UserDefaults.standard.stealthToggleModifiers
        )
    }

    /// Default preferences hotkey: Option+Shift+, (comma)
    static var preferences: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: UInt32(kVK_ANSI_Comma),
            modifiers: UInt32(optionKey | shiftKey)
        )
    }
}
