// MARK: - Command Config File
// Storage structure for command configurations

import Foundation

/// Configuration file structure for storing commands
struct CommandConfigFile: Codable, Equatable {
    /// Schema version for migration support
    var version: Int

    /// All user commands
    var commands: [Command]

    /// Ordered list of pinned command IDs (for explicit pin ordering)
    var pinnedOrder: [UUID]

    // MARK: - Constants

    /// Current schema version
    static let currentVersion = 1

    /// Maximum number of pinned commands
    static let maxPinnedCommands = 5

    /// Empty configuration
    static let empty = CommandConfigFile(
        version: currentVersion,
        commands: [],
        pinnedOrder: []
    )

    // MARK: - Initialization

    init(version: Int = currentVersion, commands: [Command] = [], pinnedOrder: [UUID] = []) {
        self.version = version
        self.commands = commands
        self.pinnedOrder = pinnedOrder
    }

    // MARK: - Command Operations

    /// Add a new command
    mutating func addCommand(_ command: Command) {
        commands.append(command)

        // If pinned and under limit, add to pinned order
        if command.isPinned && pinnedOrder.count < Self.maxPinnedCommands {
            pinnedOrder.append(command.id)
        }
    }

    /// Update an existing command
    mutating func updateCommand(_ command: Command) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }

        let wasUpdated = command.withUpdatedTimestamp()
        commands[index] = wasUpdated

        // Handle pin state changes
        let wasPinned = pinnedOrder.contains(command.id)

        if command.isPinned && !wasPinned {
            // Newly pinned - add if under limit
            if pinnedOrder.count < Self.maxPinnedCommands {
                pinnedOrder.append(command.id)
            }
        } else if !command.isPinned && wasPinned {
            // Unpinned - remove from order
            pinnedOrder.removeAll { $0 == command.id }
        }
    }

    /// Remove a command by ID
    mutating func removeCommand(id: UUID) {
        commands.removeAll { $0.id == id }
        pinnedOrder.removeAll { $0 == id }
    }

    /// Get a command by ID
    func command(id: UUID) -> Command? {
        commands.first { $0.id == id }
    }

    /// Record usage for a command (increments count, updates lastUsedAt)
    mutating func recordUsage(id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index] = commands[index].withRecordedUsage()
    }

    // MARK: - Pin Management

    /// Get pinned commands in their display order
    var pinnedCommands: [Command] {
        pinnedOrder.compactMap { id in
            commands.first { $0.id == id && $0.isPinned }
        }
    }

    /// Set the pinned order explicitly
    mutating func setPinnedOrder(_ order: [UUID]) {
        // Filter to only include valid command IDs that are pinned
        let validOrder = order.filter { id in
            commands.contains { $0.id == id && $0.isPinned }
        }
        pinnedOrder = Array(validOrder.prefix(Self.maxPinnedCommands))
    }

    /// Check if more commands can be pinned
    var canPinMore: Bool {
        pinnedOrder.count < Self.maxPinnedCommands
    }

    // MARK: - Sorting

    /// Commands sorted by recent usage (most recent first)
    var commandsSortedByRecent: [Command] {
        commands.sorted { a, b in
            guard let aDate = a.lastUsedAt else { return false }
            guard let bDate = b.lastUsedAt else { return true }
            return aDate > bDate
        }
    }

    /// Commands sorted by usage count (most used first)
    var commandsSortedByUsage: [Command] {
        commands.sorted { $0.usageCount > $1.usageCount }
    }

    // MARK: - Migration

    /// Migrate from raw JSON data (handles schema versioning)
    static func migrate(from data: Data) throws -> CommandConfigFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode as current version
        var config = try decoder.decode(CommandConfigFile.self, from: data)

        // Handle migrations based on version
        if config.version < currentVersion {
            // Future migrations go here
            config.version = currentVersion
        }

        return config
    }
}

// MARK: - Seeding

extension CommandConfigFile {
    /// Create a new config with default commands seeded
    static func withDefaults() -> CommandConfigFile {
        var config = CommandConfigFile.empty
        for command in Command.defaults {
            config.addCommand(command)
        }
        return config
    }
}
