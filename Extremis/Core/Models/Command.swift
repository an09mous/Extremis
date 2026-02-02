// MARK: - Command Model
// User-defined commands with prompt templates

import Foundation

// MARK: - Command

/// A user-defined command with a prompt template
struct Command: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: UUID

    /// Display name (e.g., "Fix Grammar")
    var name: String

    /// Brief description of what the command does
    var description: String?

    /// The prompt template to execute
    /// Context is injected inline by the prompt builder
    var promptTemplate: String

    /// SF Symbol icon name (optional, defaults to "command")
    var icon: String?

    /// Whether this command is pinned to the quick access bar
    var isPinned: Bool

    /// Number of times this command has been used
    var usageCount: Int

    /// Last time this command was used
    var lastUsedAt: Date?

    /// When this command was created
    let createdAt: Date

    /// When this command was last modified
    var updatedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        promptTemplate: String,
        icon: String? = nil,
        isPinned: Bool = false,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.promptTemplate = promptTemplate
        self.icon = icon
        self.isPinned = isPinned
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Helpers

    /// Returns the icon to display (command icon or default)
    var displayIcon: String {
        icon ?? "command"
    }

    /// Returns a copy with updated usage stats
    func withRecordedUsage() -> Command {
        var copy = self
        copy.usageCount += 1
        copy.lastUsedAt = Date()
        return copy
    }

    /// Returns a copy marked as updated now
    func withUpdatedTimestamp() -> Command {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}

// MARK: - Default Commands

extension Command {
    /// Default commands seeded on first launch
    static let defaults: [Command] = [
        Command(
            name: "Proofread",
            description: "Check grammar, spelling, and punctuation",
            promptTemplate: "Proofread the selected text for grammar, spelling, and punctuation. Please correct any errors while maintaining my original tone and style. If a sentence is particularly confusing, suggest a clearer alternative.",
            icon: "doc.text.magnifyingglass",
            isPinned: true
        ),
        Command(
            name: "Professionalize",
            description: "Make text more formal and professional",
            promptTemplate: "Rewrite the selected text to be more professional and formal. Ensure the tone is diplomatic, respectful and use more sophisticated vocabulary. Remove any slang, fillers, or overly casual phrasing while keeping the core message intact.",
            icon: "briefcase",
            isPinned: true
        ),
        Command(
            name: "Simplify",
            description: "Make text easier to understand",
            promptTemplate: "Simplify this text to make it clearer and easier to understand.",
            icon: "text.redaction",
            isPinned: true
        ),
        Command(
            name: "Explain Code",
            description: "Explain what this code does",
            promptTemplate: "Explain what this code does in simple terms.",
            icon: "questionmark.circle",
            isPinned: true
        ),
    ]
}
