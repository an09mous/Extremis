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

    // MARK: - Active Session Tracking

    /// Get the currently active session ID
    func getActiveSessionId() throws -> UUID?

    /// Set the currently active session ID
    func setActiveSessionId(_ id: UUID?) throws
}

// Note: StorageError is defined in Core/Models/Persistence/StorageError.swift
