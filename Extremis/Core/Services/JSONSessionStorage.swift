// MARK: - JSON Session Storage
// File-based session persistence using JSON files
// Implements SessionStorage protocol

import Foundation

/// File-based session storage using JSON files
/// Each session is stored as a separate JSON file with a lightweight index
actor JSONSessionStorage: SessionStorage {

    // MARK: - Singleton (default instance)
    static let shared = JSONSessionStorage()

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
    private var indexURL: URL { sessionsURL.appendingPathComponent("index.json") }

    private func sessionFileURL(id: UUID) -> URL {
        sessionsURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - SessionStorage Protocol Implementation

    func ensureStorageReady() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        } catch {
            throw StorageError.directoryCreationFailed(path: baseURL.path, underlying: error)
        }
    }

    // MARK: - Session CRUD

    func saveSession(_ session: PersistedSession) throws {
        // Ensure directories exist
        try ensureStorageReady()

        // Preserve existing title if this is an update (title is immutable once set)
        var sessionToSave = session
        if let existingSession = try? loadSession(id: session.id) {
            if let existingTitle = existingSession.title {
                sessionToSave.title = existingTitle
            }
        }

        // 1. Save session file
        let fileURL = sessionFileURL(id: sessionToSave.id)
        do {
            let data = try encoder.encode(sessionToSave)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw StorageError.encodingFailed(type: "PersistedSession", underlying: error)
        } catch {
            throw StorageError.fileWriteFailed(path: fileURL.path, underlying: error)
        }

        // 2. Update index
        var index = try loadIndex()
        let entry = SessionIndexEntry(from: sessionToSave)
        index.upsert(entry)
        try saveIndex(index)

        print("[JSONSessionStorage] Saved session \(sessionToSave.id) with \(sessionToSave.messages.count) messages")
    }

    func loadSession(id: UUID) throws -> PersistedSession? {
        let fileURL = sessionFileURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try migrate(data)
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

        print("[JSONSessionStorage] Deleted session \(id)")
    }

    func sessionExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: sessionFileURL(id: id).path)
    }

    // MARK: - Session Listing

    func listSessions() throws -> [SessionIndexEntry] {
        try loadIndex().activeSessions
    }

    func listArchivedSessions() throws -> [SessionIndexEntry] {
        try loadIndex().archivedSessions
    }

    // MARK: - Active Session Tracking

    func getActiveSessionId() throws -> UUID? {
        try loadIndex().activeSessionId
    }

    func setActiveSessionId(_ id: UUID?) throws {
        var index = try loadIndex()
        index.activeSessionId = id
        index.lastUpdated = Date()
        try saveIndex(index)
    }

    // MARK: - Archive Operations

    func archiveSession(id: UUID) throws {
        guard var session = try loadSession(id: id) else {
            throw StorageError.sessionNotFound(id: id)
        }
        session.isArchived = true
        try saveSession(session)
    }

    func unarchiveSession(id: UUID) throws {
        guard var session = try loadSession(id: id) else {
            throw StorageError.sessionNotFound(id: id)
        }
        session.isArchived = false
        try saveSession(session)
    }

    func purgeArchivedBefore(_ date: Date) throws {
        let index = try loadIndex()
        for entry in index.archivedSessions {
            if entry.updatedAt < date {
                try deleteSession(id: entry.id)
            }
        }
    }

    // MARK: - Maintenance

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
                continue
            }
        }

        return totalSize
    }

    func getStorageDescription() -> String {
        "JSON Files: \(baseURL.path)"
    }

    // MARK: - Private: Index Operations

    private func loadIndex() throws -> SessionIndex {
        if let cached = cachedIndex {
            return cached
        }

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            let emptyIndex = SessionIndex()
            cachedIndex = emptyIndex
            return emptyIndex
        }

        do {
            let data = try Data(contentsOf: indexURL)
            let index = try decoder.decode(SessionIndex.self, from: data)
            cachedIndex = index
            return index
        } catch let error as DecodingError {
            cachedIndex = nil
            throw StorageError.indexCorrupted(underlying: error)
        } catch {
            cachedIndex = nil
            throw StorageError.fileReadFailed(path: indexURL.path, underlying: error)
        }
    }

    private func saveIndex(_ index: SessionIndex) throws {
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
            cachedIndex = index
        } catch let error as EncodingError {
            cachedIndex = nil
            throw StorageError.encodingFailed(type: "SessionIndex", underlying: error)
        } catch {
            cachedIndex = nil
            throw StorageError.fileWriteFailed(path: indexURL.path, underlying: error)
        }
    }

    /// Invalidate the cached index (force reload from disk)
    func invalidateIndexCache() {
        cachedIndex = nil
    }

    // MARK: - Private: Migration

    private func migrate(_ data: Data) throws -> PersistedSession {
        if let current = try? decoder.decode(PersistedSession.self, from: data) {
            return current
        }

        throw StorageError.migrationFailed(
            fromVersion: -1,
            toVersion: PersistedSession.currentVersion
        )
    }
}
