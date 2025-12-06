// MARK: - Hotkey Manager
// Global hotkey registration using Carbon APIs

import Foundation
import Carbon.HIToolbox
import AppKit

/// Identifier for registered hotkeys
enum HotkeyIdentifier: UInt32, CaseIterable {
    case prompt = 1        // Main prompt window hotkey
    case autocomplete = 2  // Direct autocomplete hotkey
}

/// Manages global hotkey registration and handling
final class HotkeyManager {

    // MARK: - Types

    /// Callback type for hotkey activation
    typealias HotkeyHandler = () -> Void

    /// Registered hotkey info
    private struct RegisteredHotkey {
        var configuration: HotkeyConfiguration
        var handler: HotkeyHandler
        var hotkeyRef: EventHotKeyRef?
    }

    // MARK: - Properties

    /// Singleton instance
    static let shared = HotkeyManager()

    /// Registered hotkeys by identifier
    private var registeredHotkeys: [HotkeyIdentifier: RegisteredHotkey] = [:]

    /// Event handler reference (shared for all hotkeys)
    private var eventHandler: EventHandlerRef?

    /// Whether the event handler is installed
    private var eventHandlerInstalled = false

    // MARK: - Initialization

    private init() {}

    deinit {
        unregisterAll()
    }

    // MARK: - Public Methods

    /// Register a global hotkey
    /// - Parameters:
    ///   - identifier: Unique identifier for this hotkey
    ///   - configuration: The hotkey configuration
    ///   - handler: Handler called when hotkey is pressed
    /// - Throws: PreferencesError if registration fails
    func register(
        identifier: HotkeyIdentifier,
        configuration: HotkeyConfiguration,
        handler: @escaping HotkeyHandler
    ) throws {
        // Unregister existing hotkey with same identifier
        unregister(identifier: identifier)

        // Install event handler if not already installed
        if !eventHandlerInstalled {
            try installEventHandler()
        }

        // Register the hotkey
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x4558_5452), id: identifier.rawValue) // "EXTR"

        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )

        guard registerStatus == noErr else {
            throw PreferencesError.invalidHotkey
        }

        registeredHotkeys[identifier] = RegisteredHotkey(
            configuration: configuration,
            handler: handler,
            hotkeyRef: hotkeyRef
        )

        print("✅ Hotkey registered [\(identifier)]: \(configuration.displayString)")
    }

    /// Legacy method for backward compatibility - registers prompt hotkey
    func register(configuration: HotkeyConfiguration, handler: @escaping HotkeyHandler) throws {
        try register(identifier: .prompt, configuration: configuration, handler: handler)
    }

    /// Unregister a specific hotkey
    func unregister(identifier: HotkeyIdentifier) {
        guard let hotkey = registeredHotkeys[identifier] else { return }

        if let hotkeyRef = hotkey.hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }

        registeredHotkeys.removeValue(forKey: identifier)
        print("🗑️ Hotkey unregistered [\(identifier)]")
    }

    /// Legacy method for backward compatibility - unregisters all hotkeys
    func unregister() {
        unregisterAll()
    }

    /// Unregister all hotkeys
    func unregisterAll() {
        for identifier in registeredHotkeys.keys {
            unregister(identifier: identifier)
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
            eventHandlerInstalled = false
        }
    }

    /// Get configuration for a specific hotkey
    func configuration(for identifier: HotkeyIdentifier) -> HotkeyConfiguration? {
        return registeredHotkeys[identifier]?.configuration
    }

    /// Legacy property for backward compatibility
    var configuration: HotkeyConfiguration {
        return registeredHotkeys[.prompt]?.configuration ?? .default
    }

    // MARK: - Private Methods

    private func installEventHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData,
                      let event = event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotkey(event: event)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw PreferencesError.invalidHotkey
        }

        eventHandlerInstalled = true
    }

    private func handleHotkey(event: EventRef) {
        // Get the hotkey ID from the event
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            print("❌ Failed to get hotkey ID from event")
            return
        }

        // Find the handler for this hotkey
        guard let identifier = HotkeyIdentifier(rawValue: hotkeyID.id),
              let hotkey = registeredHotkeys[identifier] else {
            print("⚠️ Unknown hotkey ID: \(hotkeyID.id)")
            return
        }

        print("🔥 Hotkey triggered [\(identifier)]")
        DispatchQueue.main.async {
            hotkey.handler()
        }
    }
}

