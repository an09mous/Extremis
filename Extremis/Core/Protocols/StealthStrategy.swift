// MARK: - Stealth Strategy Protocol
// Modular protocol for stealth techniques applied to windows

import AppKit

/// Protocol for stealth techniques that can be applied to windows.
/// New techniques can be added as conformances without modifying StealthManager.
@MainActor
protocol StealthStrategy {
    /// Apply this stealth technique to a window
    func apply(to window: NSWindow)
    /// Remove this stealth technique from a window, restoring original state
    func remove(from window: NSWindow)
}

// MARK: - Sharing Type Strategy

/// Primary screen capture exclusion — sets sharingType = .none
struct SharingTypeStrategy: StealthStrategy {
    func apply(to window: NSWindow) {
        window.sharingType = .none
    }

    func remove(from window: NSWindow) {
        window.sharingType = .readWrite
    }
}

// MARK: - Collection Behavior Strategy

/// Hides windows from Mission Control, Expose, and App Switcher
final class CollectionBehaviorStrategy: StealthStrategy {
    /// Cached original behaviors per window (keyed by ObjectIdentifier)
    private var originalBehaviors: [ObjectIdentifier: NSWindow.CollectionBehavior] = [:]

    /// Stealth collection behavior flags
    private let stealthBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .transient,
        .stationary,
        .fullScreenAuxiliary
    ]

    func apply(to window: NSWindow) {
        let key = ObjectIdentifier(window)
        // Cache original behavior only if not already cached
        if originalBehaviors[key] == nil {
            originalBehaviors[key] = window.collectionBehavior
        }
        window.collectionBehavior = stealthBehavior
    }

    func remove(from window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let original = originalBehaviors.removeValue(forKey: key) {
            window.collectionBehavior = original
        }
    }
}
