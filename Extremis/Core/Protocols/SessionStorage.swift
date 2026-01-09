// MARK: - Session Storage Protocol
// Defines the interface for session persistence
// Implementations: JSONSessionStorage (file-based), future: SQLiteSessionStorage, CoreDataSessionStorage

import Foundation

/// Protocol defining session storage operations
/// Implementations must be thread-safe (actor or synchronized)
protocol SessionStorage: Actor {

    // MARK: - Initialization

    /// Ensure storage is ready (create directories, tables, etc.)
    func ensureStorageReady() throws

    // MARK: - Session CRUD

    /// Save a session (create or update)
    func saveSession(_ session: PersistedSession) throws

    /// Load a session by ID
    func loadSession(id: UUID) throws -> PersistedSession?

    /// Delete a session by ID
    func deleteSession(id: UUID) throws

    /// Check if a session exists
    func sessionExists(id: UUID) -> Bool

    // MARK: - Session Listing

    /// List all active (non-archived) sessions
    func listSessions() throws -> [SessionIndexEntry]

    /// List archived sessions
    func listArchivedSessions() throws -> [SessionIndexEntry]

    // MARK: - Active Session Tracking

    /// Get the currently active session ID
    func getActiveSessionId() throws -> UUID?

    /// Set the currently active session ID
    func setActiveSessionId(_ id: UUID?) throws

    // MARK: - Archive Operations

    /// Archive a session (soft delete)
    func archiveSession(id: UUID) throws

    /// Unarchive a session
    func unarchiveSession(id: UUID) throws

    /// Permanently delete archived sessions older than given date
    func purgeArchivedBefore(_ date: Date) throws

    // MARK: - Maintenance

    /// Calculate total storage size in bytes
    func calculateStorageSize() throws -> Int64

    /// Get storage location description (for debugging/settings)
    func getStorageDescription() -> String
}

// Note: StorageError is defined in Core/Models/Persistence/StorageError.swift
