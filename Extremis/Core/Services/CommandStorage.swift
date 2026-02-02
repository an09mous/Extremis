// MARK: - Command Storage
// Persistence for command configurations

import Foundation

/// Service for reading and writing command configuration file
@MainActor
final class CommandStorage {

    // MARK: - Properties

    /// File manager
    private let fileManager: FileManager

    /// JSON encoder with pretty printing
    private let encoder: JSONEncoder

    /// JSON decoder
    private let decoder: JSONDecoder

    /// Shared instance
    static let shared = CommandStorage()

    /// Config file URL
    var configFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let extremisDir = appSupport.appendingPathComponent("Extremis", isDirectory: true)
        return extremisDir.appendingPathComponent("commands.json")
    }

    // MARK: - Initialization

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Load configuration from disk
    /// Returns config with defaults if file doesn't exist (first launch)
    func load() throws -> CommandConfigFile {
        let url = configFileURL

        // If file doesn't exist, create with defaults and save (first launch)
        guard fileManager.fileExists(atPath: url.path) else {
            let config = CommandConfigFile.withDefaults()
            try save(config)
            return config
        }

        // Read and decode
        let data = try Data(contentsOf: url)

        // Use migration-aware loading
        return try CommandConfigFile.migrate(from: data)
    }

    /// Save configuration to disk
    func save(_ config: CommandConfigFile) throws {
        let url = configFileURL

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Encode and write atomically
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Command Operations

    /// Add a new command
    func addCommand(_ command: Command) throws {
        var config = try load()
        config.addCommand(command)
        try save(config)
    }

    /// Update an existing command
    func updateCommand(_ command: Command) throws {
        var config = try load()
        config.updateCommand(command)
        try save(config)
    }

    /// Remove a command by ID
    func removeCommand(id: UUID) throws {
        var config = try load()
        config.removeCommand(id: id)
        try save(config)
    }

    /// Get a specific command
    func command(id: UUID) throws -> Command? {
        let config = try load()
        return config.command(id: id)
    }

    /// Get all commands
    func allCommands() throws -> [Command] {
        let config = try load()
        return config.commands
    }

    /// Get pinned commands in display order
    func pinnedCommands() throws -> [Command] {
        let config = try load()
        return config.pinnedCommands
    }

    /// Record usage for a command
    func recordUsage(id: UUID) throws {
        var config = try load()
        config.recordUsage(id: id)
        try save(config)
    }

    // MARK: - Pin Management

    /// Update the pinned order
    func setPinnedOrder(_ order: [UUID]) throws {
        var config = try load()
        config.setPinnedOrder(order)
        try save(config)
    }

    /// Toggle pin state for a command
    func togglePin(id: UUID) throws {
        var config = try load()
        guard var command = config.command(id: id) else { return }

        // Check if we can pin more
        if !command.isPinned && !config.canPinMore {
            throw CommandStorageError.maxPinnedReached
        }

        command.isPinned.toggle()
        config.updateCommand(command)
        try save(config)
    }

    // MARK: - Utility

    /// Check if config file exists
    var configFileExists: Bool {
        fileManager.fileExists(atPath: configFileURL.path)
    }

    /// Delete the config file (for testing/reset)
    func deleteConfigFile() throws {
        if configFileExists {
            try fileManager.removeItem(at: configFileURL)
        }
    }

    /// Create a backup of the config file
    func backupConfigFile() throws -> URL? {
        guard configFileExists else { return nil }

        let backupURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("commands.backup.json")

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        try fileManager.copyItem(at: configFileURL, to: backupURL)
        return backupURL
    }

    /// Restore from a backup
    func restoreFromBackup() throws {
        let backupURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("commands.backup.json")

        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw CommandStorageError.backupNotFound
        }

        if fileManager.fileExists(atPath: configFileURL.path) {
            try fileManager.removeItem(at: configFileURL)
        }

        try fileManager.copyItem(at: backupURL, to: configFileURL)
    }

    /// Reset to default commands
    func resetToDefaults() throws {
        try save(.withDefaults())
    }
}

// MARK: - Errors

/// Errors specific to command storage
enum CommandStorageError: LocalizedError {
    case backupNotFound
    case maxPinnedReached
    case commandNotFound
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupNotFound:
            return "No backup file found"
        case .maxPinnedReached:
            return "Maximum number of pinned commands reached (\(CommandConfigFile.maxPinnedCommands))"
        case .commandNotFound:
            return "Command not found"
        case .writeFailed(let reason):
            return "Failed to write configuration: \(reason)"
        }
    }
}
