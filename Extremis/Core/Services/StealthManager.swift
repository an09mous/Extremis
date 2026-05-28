// MARK: - Stealth Manager
// Central service that manages stealth mode state and coordinates stealth behavior across all windows

import AppKit
import Combine

/// Manages stealth mode state and coordinates stealth behavior across all windows
@MainActor
final class StealthManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StealthManager()

    // MARK: - Published State

    /// Current stealth mode state, observable by UI
    @Published private(set) var isStealthActive: Bool = false

    // MARK: - Properties

    /// Weak references to all registered windows
    private var managedWindows = NSHashTable<NSWindow>.weakObjects()

    /// Modular array of stealth techniques to apply
    private(set) var strategies: [StealthStrategy]

    /// Cached original process name for restore
    private let originalProcessName: String

    /// Callback to hide the menu bar icon (set by AppDelegate)
    var onMenuBarHide: (() -> Void)?

    /// Callback to show the menu bar icon (set by AppDelegate)
    var onMenuBarShow: (() -> Void)?

    /// Callback to show a toast message (set after StealthToastController is available)
    var onShowToast: ((String) -> Void)?

    // MARK: - Initialization

    private init() {
        self.originalProcessName = ProcessInfo.processInfo.processName
        self.strategies = [
            SharingTypeStrategy(),
            CollectionBehaviorStrategy()
        ]

        // Read persisted state (but don't apply yet — callbacks not wired)
        self.isStealthActive = UserDefaults.standard.stealthModeEnabled

        // Log platform version info
        logPlatformVersion()
    }

    /// Restore stealth from persisted state on app launch.
    /// Called by AppDelegate AFTER callbacks are wired but BEFORE UI is shown.
    /// Unlike activate(), this doesn't guard on isStealthActive and doesn't show toast.
    func restorePersistedState() {
        guard isStealthActive else { return }

        // Apply all strategies to any already-registered windows
        applyToAllWindows()

        // Apply window transparency
        currentOpacity = UserDefaults.standard.stealthOpacity
        applyOpacityToAllWindows()

        // Hide menu bar icon
        onMenuBarHide?()

        // Disguise process name
        if UserDefaults.standard.stealthProcessDisguise {
            ProcessInfo.processInfo.processName = UserDefaults.standard.stealthDisguiseName
        }

        print("[Stealth] Restored from persisted state — stealth active")
    }

    // MARK: - Public Methods

    /// Toggle stealth on/off
    func toggle() {
        if isStealthActive {
            deactivate()
        } else {
            activate()
        }
    }

    /// Enable stealth mode
    func activate() {
        guard !isStealthActive else { return }

        isStealthActive = true
        UserDefaults.standard.stealthModeEnabled = true

        // Apply all strategies to all managed windows
        applyToAllWindows()

        // Apply window transparency
        currentOpacity = UserDefaults.standard.stealthOpacity
        applyOpacityToAllWindows()

        // Hide menu bar icon
        onMenuBarHide?()

        // Disguise process name
        if UserDefaults.standard.stealthProcessDisguise {
            ProcessInfo.processInfo.processName = UserDefaults.standard.stealthDisguiseName
        }

        print("[Stealth] Activated — \(managedWindows.count) windows stealthed")
    }

    /// Disable stealth mode
    func deactivate() {
        guard isStealthActive else { return }

        isStealthActive = false
        UserDefaults.standard.stealthModeEnabled = false

        // Remove all strategies from all managed windows
        removeFromAllWindows()

        // Restore full opacity
        restoreOpacityOnAllWindows()

        // Show menu bar icon
        onMenuBarShow?()

        // Restore original process name
        ProcessInfo.processInfo.processName = originalProcessName

        print("[Stealth] Deactivated — \(managedWindows.count) windows restored")
    }

    /// Current opacity value (published for SwiftUI reactivity)
    @Published private(set) var currentOpacity: Double = 1.0

    /// Register a window for stealth management
    func registerWindow(_ window: NSWindow) {
        managedWindows.add(window)

        // If stealth is already active, apply immediately
        if isStealthActive {
            applyStrategies(to: window)
            makeWindowTransparent(window)
        }
    }

    /// Apply current stealth state to a specific window
    func applyCurrentState(to window: NSWindow) {
        if isStealthActive {
            applyStrategies(to: window)
            makeWindowTransparent(window)
        } else {
            removeStrategies(from: window)
            makeWindowOpaque(window)
        }
    }

    /// Update opacity on all windows (called when slider changes)
    func updateOpacity(_ opacity: Double) {
        UserDefaults.standard.stealthOpacity = opacity
        currentOpacity = opacity
        if isStealthActive {
            applyOpacityToAllWindows()
        }
    }

    /// Number of currently managed windows (for testing)
    var managedWindowCount: Int {
        return managedWindows.count
    }

    // MARK: - Private Methods

    private func applyStrategies(to window: NSWindow) {
        for strategy in strategies {
            strategy.apply(to: window)
        }
    }

    private func removeStrategies(from window: NSWindow) {
        for strategy in strategies {
            strategy.remove(from: window)
        }
    }

    private func applyToAllWindows() {
        for window in managedWindows.allObjects {
            applyStrategies(to: window)
        }
    }

    private func removeFromAllWindows() {
        for window in managedWindows.allObjects {
            removeStrategies(from: window)
        }
    }

    private func makeWindowTransparent(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // NSPanel (main prompt) uses SwiftUI material background for readable text
        // Other windows (preferences) use alphaValue since their native chrome is opaque
        if !(window is NSPanel) {
            window.alphaValue = CGFloat(UserDefaults.standard.stealthOpacity)
        }
    }

    private func makeWindowOpaque(_ window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.alphaValue = 1.0
    }

    private func applyOpacityToAllWindows() {
        let opacity = UserDefaults.standard.stealthOpacity
        currentOpacity = opacity
        for window in managedWindows.allObjects {
            makeWindowTransparent(window)
        }
    }

    private func restoreOpacityOnAllWindows() {
        currentOpacity = 1.0
        for window in managedWindows.allObjects {
            makeWindowOpaque(window)
        }
    }

    private func logPlatformVersion() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion >= 15 {
            print("[Stealth] macOS \(version.majorVersion).\(version.minorVersion) detected — " +
                  "local recording tools (QuickTime, OBS) may capture Extremis windows. " +
                  "Meeting platforms (Google Meet, Zoom, Teams) remain unaffected.")
        } else {
            print("[Stealth] macOS \(version.majorVersion).\(version.minorVersion) — " +
                  "full screen capture exclusion supported.")
        }
    }
}
