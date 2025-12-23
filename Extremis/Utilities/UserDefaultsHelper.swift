// MARK: - UserDefaults Helper
// Preferences storage using UserDefaults

import Foundation
import Combine

/// Preferences store implementation using UserDefaults
final class UserDefaultsHelper: PreferencesStore {
    
    // MARK: - Keys

    private enum Keys {
        static let preferences = "extremis.preferences"
        static let hasShownAccessibilityPrompt = "extremis.hasShownAccessibilityPrompt"
    }
    
    // MARK: - Properties
    
    /// UserDefaults instance
    private let defaults: UserDefaults
    
    /// Shared instance
    static let shared = UserDefaultsHelper()
    
    /// Current preferences (cached)
    private(set) var preferences: Preferences
    
    /// Publisher for preference changes
    private let preferencesSubject = PassthroughSubject<Preferences, Never>()
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.load(from: defaults) ?? .default
    }
    
    // MARK: - PreferencesStore Protocol
    
    func update(_ preferences: Preferences) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(preferences)
        defaults.set(data, forKey: Keys.preferences)
        
        self.preferences = preferences
        preferencesSubject.send(preferences)
    }
    
    func reset() {
        defaults.removeObject(forKey: Keys.preferences)
        preferences = .default
        preferencesSubject.send(preferences)
    }
    
    func observe(_ handler: @escaping (Preferences) -> Void) -> Any {
        return preferencesSubject.sink { preferences in
            handler(preferences)
        }
    }
    
    // MARK: - Private Methods
    
    private static func load(from defaults: UserDefaults) -> Preferences? {
        guard let data = defaults.data(forKey: Keys.preferences) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(Preferences.self, from: data)
    }
}

// MARK: - Convenience Extensions

extension UserDefaultsHelper {
    /// Get the active LLM provider type
    var activeProvider: LLMProviderType {
        preferences.activeProvider
    }
    
    /// Set the active LLM provider type
    func setActiveProvider(_ provider: LLMProviderType) throws {
        var updated = preferences
        updated.activeProvider = provider
        try update(updated)
    }
    
    /// Get the hotkey configuration
    var hotkeyConfiguration: HotkeyConfiguration {
        preferences.hotkey
    }
    
    /// Set the hotkey configuration
    func setHotkeyConfiguration(_ config: HotkeyConfiguration) throws {
        var updated = preferences
        updated.hotkey = config
        try update(updated)
    }
    
    /// Get launch at login setting
    var launchAtLogin: Bool {
        get { preferences.launchAtLogin }
        set {
            var updated = preferences
            updated.launchAtLogin = newValue
            try? update(updated)
        }
    }

    /// Get appearance settings
    var appearanceSettings: AppearanceSettings {
        get { preferences.appearance }
        set {
            var updated = preferences
            updated.appearance = newValue
            try? update(updated)
        }
    }

    // MARK: - Accessibility Prompt Tracking

    /// Whether the accessibility permission explanation has been shown
    var hasShownAccessibilityPrompt: Bool {
        get { defaults.bool(forKey: Keys.hasShownAccessibilityPrompt) }
        set { defaults.set(newValue, forKey: Keys.hasShownAccessibilityPrompt) }
    }
}

