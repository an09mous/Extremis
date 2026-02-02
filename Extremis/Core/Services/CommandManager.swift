// MARK: - Command Manager
// Singleton manager for command operations with reactive state

import Foundation
import Combine

/// Manager for command operations with published state
@MainActor
final class CommandManager: ObservableObject {

    // MARK: - Published State

    /// All commands
    @Published private(set) var commands: [Command] = []

    /// Pinned commands in display order
    @Published private(set) var pinnedCommands: [Command] = []

    /// Whether commands are loading
    @Published private(set) var isLoading: Bool = false

    /// Last error encountered
    @Published var error: Error?

    // MARK: - Properties

    /// Storage service
    private let storage: CommandStorage

    /// Shared instance
    static let shared = CommandManager()

    // MARK: - Initialization

    init(storage: CommandStorage = .shared) {
        self.storage = storage
    }

    // MARK: - Loading

    /// Load commands from storage
    func loadCommands() {
        isLoading = true
        error = nil

        do {
            let config = try storage.load()
            commands = config.commands
            pinnedCommands = config.pinnedCommands
        } catch {
            self.error = error
            commands = []
            pinnedCommands = []
        }

        isLoading = false
    }

    /// Reload commands (convenience for refresh)
    func refresh() {
        loadCommands()
    }

    // MARK: - Command Operations

    /// Add a new command
    func addCommand(_ command: Command) {
        do {
            try storage.addCommand(command)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    /// Update an existing command
    func updateCommand(_ command: Command) {
        do {
            try storage.updateCommand(command)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    /// Remove a command by ID
    func removeCommand(id: UUID) {
        do {
            try storage.removeCommand(id: id)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    /// Record usage for a command
    func recordUsage(id: UUID) {
        do {
            try storage.recordUsage(id: id)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    // MARK: - Pin Management

    /// Toggle pin state for a command
    func togglePin(id: UUID) {
        do {
            try storage.togglePin(id: id)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    /// Update pinned order
    func setPinnedOrder(_ order: [UUID]) {
        do {
            try storage.setPinnedOrder(order)
            loadCommands()
        } catch {
            self.error = error
        }
    }

    /// Check if more commands can be pinned
    var canPinMore: Bool {
        pinnedCommands.count < CommandConfigFile.maxPinnedCommands
    }

    // MARK: - Search & Filtering

    /// Filter commands by search query (fuzzy match on name and description)
    func filter(query: String) -> [Command] {
        guard !query.isEmpty else {
            return commandsSortedForPalette
        }

        let lowercasedQuery = query.lowercased()

        return commands
            .filter { command in
                // Match against name
                if command.name.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match against description
                if let description = command.description,
                   description.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Fuzzy match: check if query letters appear in order
                return fuzzyMatch(query: lowercasedQuery, in: command.name.lowercased())
            }
            .sorted { a, b in
                // Prioritize exact prefix matches
                let aStartsWith = a.name.lowercased().hasPrefix(lowercasedQuery)
                let bStartsWith = b.name.lowercased().hasPrefix(lowercasedQuery)
                if aStartsWith != bStartsWith {
                    return aStartsWith
                }
                // Then by usage count
                return a.usageCount > b.usageCount
            }
    }

    /// Commands sorted for palette display (recent first, then by usage)
    var commandsSortedForPalette: [Command] {
        commands.sorted { a, b in
            // Recently used first
            if let aDate = a.lastUsedAt, let bDate = b.lastUsedAt {
                if aDate != bDate {
                    return aDate > bDate
                }
            } else if a.lastUsedAt != nil {
                return true
            } else if b.lastUsedAt != nil {
                return false
            }
            // Then by usage count
            return a.usageCount > b.usageCount
        }
    }

    // MARK: - Reset

    /// Reset to default commands
    func resetToDefaults() {
        do {
            try storage.resetToDefaults()
            loadCommands()
        } catch {
            self.error = error
        }
    }

    // MARK: - Private Helpers

    /// Simple fuzzy matching - checks if query letters appear in order in the target
    private func fuzzyMatch(query: String, in target: String) -> Bool {
        var targetIndex = target.startIndex
        for char in query {
            guard let foundIndex = target[targetIndex...].firstIndex(of: char) else {
                return false
            }
            targetIndex = target.index(after: foundIndex)
        }
        return true
    }
}

// MARK: - Command Execution Helper

extension CommandManager {
    /// Get a command ready for execution with recorded usage
    func prepareForExecution(id: UUID) -> Command? {
        guard let command = commands.first(where: { $0.id == id }) else {
            return nil
        }

        // Record usage asynchronously
        recordUsage(id: id)

        return command
    }
}
