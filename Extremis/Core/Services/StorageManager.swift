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
    private var cachedIndex: SessionIndex?

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

    private var sessionsURL: URL { baseURL.appendingPathComponent("sessions") }
    private var memoriesURL: URL { baseURL.appendingPathComponent("memories") }
    private var indexURL: URL { sessionsURL.appendingPathComponent("index.json") }
    private var memoriesFileURL: URL { memoriesURL.appendingPathComponent("user-memories.json") }

    func sessionFileURL(id: UUID) -> URL {
        sessionsURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Initialization

    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: memoriesURL, withIntermediateDirectories: true)
        } catch {
            throw StorageError.directoryCreationFailed(path: baseURL.path, underlying: error)
        }
    }

    // MARK: - Index Operations

    /// Load index from cache or disk (lazy load with caching)
    func loadIndex() throws -> SessionIndex {
        // Return cached index if available
        if let cached = cachedIndex {
            return cached
        }

        // Load from disk
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            let emptyIndex = SessionIndex()
            cachedIndex = emptyIndex
            return emptyIndex
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let index = try decoder.decode(SessionIndex.self, from: data)
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
    func saveIndex(_ index: SessionIndex) throws {
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
            // Only update cache after successful disk write
            cachedIndex = index
        } catch let error as EncodingError {
            // Invalidate cache on failure to ensure next read comes from disk
            cachedIndex = nil
            throw StorageError.encodingFailed(type: "SessionIndex", underlying: error)
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

    // MARK: - Session Operations

    func saveSession(_ session: PersistedSession) throws {
        // Ensure directories exist
        try ensureDirectoriesExist()

        // 1. Save session file
        let fileURL = sessionFileURL(id: session.id)
        do {
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw StorageError.encodingFailed(type: "PersistedSession", underlying: error)
        } catch {
            throw StorageError.fileWriteFailed(path: fileURL.path, underlying: error)
        }

        // 2. Update index
        var index = try loadIndex()
        let entry = SessionIndexEntry(from: session)
        index.upsert(entry)
        try saveIndex(index)

        print("[StorageManager] Saved session \(session.id) with \(session.messages.count) messages")
    }

    func loadSession(id: UUID) throws -> PersistedSession? {
        let fileURL = sessionFileURL(id: id)
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

    func deleteSession(id: UUID) throws {
        // 1. Delete file
        let fileURL = sessionFileURL(id: id)
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

        print("[StorageManager] Deleted session \(id)")
    }

    func sessionExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: sessionFileURL(id: id).path)
    }

    /// List all sessions (from index only - fast)
    func listSessions() throws -> [SessionIndexEntry] {
        try loadIndex().activeSessions
    }

    /// Get/Set active session ID
    func getActiveSessionId() throws -> UUID? {
        try loadIndex().activeSessionId
    }

    func setActiveSession(id: UUID?) throws {
        var index = try loadIndex()
        index.activeSessionId = id
        index.lastUpdated = Date()
        try saveIndex(index)
    }

    // MARK: - Migration

    private func migrate(_ data: Data) throws -> PersistedSession {
        // Try current version first
        if let current = try? decoder.decode(PersistedSession.self, from: data) {
            return current
        }

        // Add migration handlers here as schema evolves:
        // if let v0 = try? decoder.decode(PersistedSessionV0.self, from: data) {
        //     return migrate(from: v0)
        // }

        throw StorageError.migrationFailed(
            fromVersion: -1,
            toVersion: PersistedSession.currentVersion
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

    /// Archive old sessions (soft delete)
    func archiveSession(id: UUID) throws {
        guard var session = try loadSession(id: id) else {
            throw StorageError.sessionNotFound(id: id)
        }
        session.isArchived = true
        try saveSession(session)
    }

    /// Permanently delete archived sessions older than given date
    func purgeArchivedBefore(_ date: Date) throws {
        let index = try loadIndex()
        for entry in index.archivedSessions {
            if entry.updatedAt < date {
                try deleteSession(id: entry.id)
            }
        }
    }

    // MARK: - Debug Helpers

    /// Get storage directory path (for debugging)
    func getStoragePath() -> String {
        baseURL.path
    }
}
