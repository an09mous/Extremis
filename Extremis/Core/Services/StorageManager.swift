// MARK: - Storage Manager
// Manages file-based persistence for Extremis
// Actor ensures thread-safe file access

import Foundation

/// Manages file-based persistence for Extremis
/// Actor ensures thread-safe file access
actor StorageManager {

    // MARK: - Singleton
    static let shared = StorageManager()

    // MARK: - In-Memory Cache
    private var cachedIndex: ConversationIndex?

    // MARK: - Configuration
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #if DEBUG
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #endif
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Paths
    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Extremis", isDirectory: true)
    }

    private var conversationsURL: URL { baseURL.appendingPathComponent("conversations") }
    private var memoriesURL: URL { baseURL.appendingPathComponent("memories") }
    private var indexURL: URL { conversationsURL.appendingPathComponent("index.json") }
    private var memoriesFileURL: URL { memoriesURL.appendingPathComponent("user-memories.json") }

    func conversationFileURL(id: UUID) -> URL {
        conversationsURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Initialization

    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: memoriesURL, withIntermediateDirectories: true)
        } catch {
            throw StorageError.directoryCreationFailed(path: baseURL.path, underlying: error)
        }
    }

    // MARK: - Index Operations

    /// Load index from cache or disk (lazy load with caching)
    func loadIndex() throws -> ConversationIndex {
        // Return cached index if available
        if let cached = cachedIndex {
            return cached
        }

        // Load from disk
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            let emptyIndex = ConversationIndex()
            cachedIndex = emptyIndex
            return emptyIndex
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let index = try decoder.decode(ConversationIndex.self, from: data)
            cachedIndex = index  // Cache it
            return index
        } catch let error as DecodingError {
            // Don't cache corrupted index - keep cache nil so we return empty next time
            cachedIndex = nil
            throw StorageError.indexCorrupted(underlying: error)
        } catch {
            // Keep cache nil on read failure
            cachedIndex = nil
            throw StorageError.fileReadFailed(path: indexURL.path, underlying: error)
        }
    }

    /// Save index to disk and update cache
    /// Cache is only updated AFTER successful disk write to ensure consistency
    func saveIndex(_ index: ConversationIndex) throws {
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
            // Only update cache after successful disk write
            cachedIndex = index
        } catch let error as EncodingError {
            // Invalidate cache on failure to ensure next read comes from disk
            cachedIndex = nil
            throw StorageError.encodingFailed(type: "ConversationIndex", underlying: error)
        } catch {
            // Invalidate cache on failure to ensure next read comes from disk
            cachedIndex = nil
            throw StorageError.fileWriteFailed(path: indexURL.path, underlying: error)
        }
    }

    /// Invalidate the cached index (force reload from disk next time)
    func invalidateIndexCache() {
        cachedIndex = nil
    }

    // MARK: - Conversation Operations

    func saveConversation(_ conversation: PersistedConversation) throws {
        // Ensure directories exist
        try ensureDirectoriesExist()

        // 1. Save conversation file
        let fileURL = conversationFileURL(id: conversation.id)
        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw StorageError.encodingFailed(type: "PersistedConversation", underlying: error)
        } catch {
            throw StorageError.fileWriteFailed(path: fileURL.path, underlying: error)
        }

        // 2. Update index
        var index = try loadIndex()
        let entry = ConversationIndexEntry(from: conversation)
        index.upsert(entry)
        try saveIndex(index)

        print("[StorageManager] Saved conversation \(conversation.id) with \(conversation.messages.count) messages")
    }

    func loadConversation(id: UUID) throws -> PersistedConversation? {
        let fileURL = conversationFileURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try migrate(data)  // Apply migrations if needed
        } catch {
            throw StorageError.fileReadFailed(path: fileURL.path, underlying: error)
        }
    }

    func deleteConversation(id: UUID) throws {
        // 1. Delete file
        let fileURL = conversationFileURL(id: id)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                throw StorageError.fileDeleteFailed(path: fileURL.path, underlying: error)
            }
        }

        // 2. Update index
        var index = try loadIndex()
        index.remove(id: id)
        try saveIndex(index)

        print("[StorageManager] Deleted conversation \(id)")
    }

    func conversationExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: conversationFileURL(id: id).path)
    }

    /// List all conversations (from index only - fast)
    func listConversations() throws -> [ConversationIndexEntry] {
        try loadIndex().activeConversations
    }

    /// Get/Set active conversation ID
    func getActiveConversationId() throws -> UUID? {
        try loadIndex().activeConversationId
    }

    func setActiveConversation(id: UUID?) throws {
        var index = try loadIndex()
        index.activeConversationId = id
        index.lastUpdated = Date()
        try saveIndex(index)
    }

    // MARK: - Migration

    private func migrate(_ data: Data) throws -> PersistedConversation {
        // Try current version first
        if let current = try? decoder.decode(PersistedConversation.self, from: data) {
            return current
        }

        // Add migration handlers here as schema evolves:
        // if let v0 = try? decoder.decode(PersistedConversationV0.self, from: data) {
        //     return migrate(from: v0)
        // }

        throw StorageError.migrationFailed(
            fromVersion: -1,
            toVersion: PersistedConversation.currentVersion
        )
    }

    // MARK: - Maintenance

    /// Calculate total storage size in bytes
    func calculateStorageSize() throws -> Int64 {
        let fm = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        while let url = enumerator.nextObject() as? URL {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                totalSize += Int64(size)
            } catch {
                // Skip files we can't read
                continue
            }
        }

        return totalSize
    }

    /// Archive old conversations (soft delete)
    func archiveConversation(id: UUID) throws {
        guard var conversation = try loadConversation(id: id) else {
            throw StorageError.conversationNotFound(id: id)
        }
        conversation.isArchived = true
        try saveConversation(conversation)
    }

    /// Permanently delete archived conversations older than given date
    func purgeArchivedBefore(_ date: Date) throws {
        let index = try loadIndex()
        for entry in index.archivedConversations {
            if entry.updatedAt < date {
                try deleteConversation(id: entry.id)
            }
        }
    }

    // MARK: - Debug Helpers

    /// Get storage directory path (for debugging)
    func getStoragePath() -> String {
        baseURL.path
    }
}
