// MARK: - Preferences Model
// User settings and configuration

import Foundation
import Carbon.HIToolbox

/// User preferences and settings
struct Preferences: Codable, Equatable {
    var hotkey: HotkeyConfiguration
    var activeProvider: LLMProviderType
    var launchAtLogin: Bool
    var appearance: AppearanceSettings
    
    init(
        hotkey: HotkeyConfiguration = .default,
        activeProvider: LLMProviderType = .openai,
        launchAtLogin: Bool = false,
        appearance: AppearanceSettings = .default
    ) {
        self.hotkey = hotkey
        self.activeProvider = activeProvider
        self.launchAtLogin = launchAtLogin
        self.appearance = appearance
    }
    
    /// Default preferences
    static let `default` = Preferences()
}

// MARK: - Hotkey Configuration

/// Configuration for the global activation hotkey
struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    /// Default hotkey: ⌘+Shift+Space
    static let `default` = HotkeyConfiguration(
        keyCode: UInt32(kVK_Space),      // Space key
        modifiers: UInt32(cmdKey | shiftKey)  // Cmd + Shift
    )
    
    /// Human-readable description of the hotkey
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        
        // Add key name
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_A...kVK_ANSI_Z:
            let letters = "ASDGHJKL;'QWERTYUIOP[]\\ZXCVBNM,./"
            let index = Int(keyCode)
            if index < letters.count {
                return String(letters[letters.index(letters.startIndex, offsetBy: index)])
            }
            return "?"
        default:
            return "Key\(keyCode)"
        }
    }
}

// MARK: - Appearance Settings

/// Visual appearance settings
struct AppearanceSettings: Codable, Equatable {
    var appearance: AppearanceMode
    var windowWidth: Int
    var windowHeight: Int
    var fontSize: Int

    init(
        appearance: AppearanceMode = .system,
        windowWidth: Int = 500,
        windowHeight: Int = 300,
        fontSize: Int = 14
    ) {
        self.appearance = appearance
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.fontSize = fontSize
    }

    /// Default appearance settings
    static let `default` = AppearanceSettings()
}

/// App appearance mode
enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

// MARK: - Conversation (Phase 2 Ready)

/// In-memory conversation tracking (persistence in Phase 2)
struct Conversation: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var turns: [ConversationTurn]
    var context: Context
    
    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        turns: [ConversationTurn] = [],
        context: Context
    ) {
        self.id = id
        self.startedAt = startedAt
        self.turns = turns
        self.context = context
    }
}

struct ConversationTurn: Codable, Equatable {
    let instruction: Instruction
    var generation: Generation?
    var status: GenerationStatus
    
    init(instruction: Instruction, generation: Generation? = nil, status: GenerationStatus = .pending) {
        self.instruction = instruction
        self.generation = generation
        self.status = status
    }
}

