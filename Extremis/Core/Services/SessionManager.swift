// MARK: - Session Manager
// Manages session persistence with debounced auto-save

import Foundation
import Combine

// MARK: - Session Notification

/// Notification state for background sessions
enum SessionNotification: Equatable {
    case completed
    case error(String)
    case needsApproval
}

/// Manages session persistence with debounced auto-save
@MainActor
final class SessionManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SessionManager()

    // MARK: - Published State
    @Published private(set) var currentSession: ChatSession?
    @Published private(set) var currentSessionId: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var sessionListVersion: Int = 0  // Incremented when list changes

    /// Set of session IDs currently generating (supports concurrent generation)
    @Published private(set) var generatingSessionIds: Set<UUID> = []

    /// Maximum concurrent generations allowed
    let maxConcurrentGenerations: Int = 3

    /// Computed convenience: true if any session is generating
    var isAnySessionGenerating: Bool { !generatingSessionIds.isEmpty }

    /// Whether a new generation can be started (under concurrency limit)
    var canStartGeneration: Bool { generatingSessionIds.count < maxConcurrentGenerations }

    /// Notification state for background sessions (completed, error, needs approval)
    @Published private(set) var sessionNotifications: [UUID: SessionNotification] = [:]

    /// Whether the current session is a draft (not yet persisted)
    /// True when session exists but has no messages (not saved to disk)
    @Published private(set) var hasDraftSession: Bool = false

    // MARK: - Private State
    private var dirtySessionIds: Set<UUID> = []
    private var currentContext: Context?  // Track current context for saving with messages
    private var saveDebounceTasksBySession: [UUID: Task<Void, Never>] = [:]
    private let debounceInterval: TimeInterval = 2.0
    private var sessionObservations: [UUID: Set<AnyCancellable>] = [:]

    /// In-memory cache of sessions to preserve approval memory across switches
    /// Key: Session UUID, Value: ChatSession instance
    private var sessionCache: [UUID: ChatSession] = [:]

    /// Maximum number of sessions to keep in cache
    private let maxCachedSessions = 10

    // MARK: - Storage (Strategy Pattern)
    private let storage: any SessionStorage

    // MARK: - Initialization

    private init() {
        // Default to JSON file storage
        self.storage = JSONSessionStorage.shared
    }

    /// Initialize with custom storage (for testing or alternative backends)
    init(storage: any SessionStorage) {
        self.storage = storage
    }

    // MARK: - Session Lifecycle

    /// Start a new session
    /// Note: Does NOT immediately save - session is only persisted when first message is sent
    func startNewSession(
        context: Context? = nil,
        initialRequest: String? = nil
    ) async {
        // Save current session before starting new one
        await saveCurrentSessionIfDirty()

        let session = ChatSession(
            originalContext: context,
            initialRequest: initialRequest
        )

        let sessionId = UUID()
        currentSession = session
        currentSessionId = sessionId
        hasDraftSession = true  // Mark as draft until first message is sent

        // Cache the session for later retrieval
        cacheSession(session, id: sessionId)

        // Observe changes to the session
        observeSession(session, id: sessionId)

        print("[SessionManager] Prepared new session \(sessionId) (draft - not saved until first message)")
    }

    /// Restore the last active session on app launch
    func restoreLastSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get active session ID from index
            guard let activeId = try await storage.getActiveSessionId() else {
                print("[SessionManager] No active session to restore")
                return
            }

            // Load the session
            guard let persisted = try await storage.loadSession(id: activeId) else {
                print("[SessionManager] Active session \(activeId) not found in storage")
                return
            }

            // Convert to live session (context is now embedded in messages)
            let session = persisted.toSession()
            currentSession = session
            currentSessionId = activeId
            hasDraftSession = false  // Restored sessions are not drafts

            // Cache the session for later retrieval
            cacheSession(session, id: activeId)

            // Observe changes
            observeSession(session, id: activeId)

            print("[SessionManager] Restored session \(activeId) with \(session.messages.count) messages")
        } catch {
            print("[SessionManager] Failed to restore session: \(error)")
        }
    }

    /// Set the current session (for cases where session already exists)
    func setCurrentSession(_ session: ChatSession, id: UUID? = nil) {
        let sessionId = id ?? UUID()
        currentSession = session
        currentSessionId = sessionId
        hasDraftSession = session.messages.isEmpty  // Draft if no messages yet

        // Cache the session for later retrieval
        cacheSession(session, id: sessionId)
        observeSession(session, id: sessionId)
        markDirty(sessionId: sessionId)
    }

    /// Update the current context (called when hotkey is triggered with new context)
    /// This context will be attached to the next user message
    func updateCurrentContext(_ context: Context?) {
        currentContext = context
        if context != nil {
            print("[SessionManager] Updated current context from \(context!.source.applicationName)")
        }
    }

    /// Get the current context (for attaching to new user messages)
    func getCurrentContext() -> Context? {
        return currentContext
    }

    // MARK: - Generation State Tracking

    /// Register that a session is actively generating
    /// Returns false if the concurrency limit has been reached
    @discardableResult
    func registerActiveGeneration(sessionId: UUID) -> Bool {
        guard generatingSessionIds.count < maxConcurrentGenerations else {
            print("[SessionManager] Rejected generation for \(sessionId) - max concurrent reached (\(maxConcurrentGenerations))")
            return false
        }
        generatingSessionIds.insert(sessionId)
        // Clear any stale notification when generation starts
        sessionNotifications.removeValue(forKey: sessionId)
        print("[SessionManager] Registered generation for \(sessionId) (active: \(generatingSessionIds.count)/\(maxConcurrentGenerations))")
        return true
    }

    /// Unregister when generation completes
    func unregisterActiveGeneration(sessionId: UUID) {
        generatingSessionIds.remove(sessionId)
        print("[SessionManager] Unregistered generation for \(sessionId) (active: \(generatingSessionIds.count)/\(maxConcurrentGenerations))")
    }

    /// Check if a specific session is currently generating
    func isSessionGenerating(_ sessionId: UUID) -> Bool {
        generatingSessionIds.contains(sessionId)
    }

    // MARK: - Notification Management

    /// Set a notification for a background session
    func setNotification(_ notification: SessionNotification, for sessionId: UUID) {
        sessionNotifications[sessionId] = notification
    }

    /// Clear notification when user navigates to a session
    func clearNotification(for sessionId: UUID) {
        sessionNotifications.removeValue(forKey: sessionId)
    }

    // MARK: - Dirty Tracking

    /// Mark a session as modified
    /// Defaults to the current session if no sessionId is provided
    func markDirty(sessionId: UUID? = nil) {
        let targetId = sessionId ?? currentSessionId
        guard let id = targetId else { return }

        dirtySessionIds.insert(id)

        // Draft becomes real session once it has content
        if id == currentSessionId, hasDraftSession,
           let session = currentSession, !session.messages.isEmpty {
            hasDraftSession = false
            print("[SessionManager] Session transitioned from draft to saved")

            // Save immediately when draft becomes real session
            Task {
                await saveSession(id: id)
            }
            return  // Don't schedule another debounced save
        }

        scheduleDebouncedSave(for: id)
    }

    private func scheduleDebouncedSave(for sessionId: UUID) {
        saveDebounceTasksBySession[sessionId]?.cancel()
        saveDebounceTasksBySession[sessionId] = Task {
            do {
                try await Task.sleep(for: .seconds(debounceInterval))
                guard !Task.isCancelled else { return }
                await saveSession(id: sessionId)
            } catch {
                // Task was cancelled - that's fine
            }
        }
    }

    // MARK: - Save Operations

    /// Save a specific session by ID
    func saveSession(id: UUID) async {
        guard dirtySessionIds.contains(id) else { return }

        // Get session from cache
        guard let session = sessionCache[id] else {
            print("[SessionManager] Cannot save session \(id) - not in cache")
            return
        }

        // Don't save empty sessions
        guard !session.messages.isEmpty else {
            print("[SessionManager] Skipping save - session \(id) is empty")
            return
        }

        // Cancel any pending debounced save for this session
        saveDebounceTasksBySession[id]?.cancel()
        saveDebounceTasksBySession.removeValue(forKey: id)

        do {
            // Convert to persisted format
            // Use currentContext only for the current session
            let contextToUse = (id == currentSessionId) ? currentContext : nil
            var persisted = PersistedSession.from(
                session,
                id: id,
                currentContext: contextToUse
            )
            persisted.updatedAt = Date()

            // Save to storage
            try await storage.saveSession(persisted)

            // Update active session ID for the current session
            if id == currentSessionId {
                try await storage.setActiveSessionId(id)
            }

            dirtySessionIds.remove(id)
            sessionListVersion += 1  // Notify sidebar to refresh
            print("[SessionManager] Saved session \(id)")

            // Check if summarization is needed (runs async, doesn't block)
            let storageRef = self.storage
            Task { [weak self] in
                let updated = await SummarizationManager.shared.summarizeIfNeeded(persisted, storage: storageRef)
                if let newSummary = updated.summary, newSummary != persisted.summary {
                    // Sync summary back to live session for immediate use
                    await MainActor.run {
                        session.updateSummary(newSummary, coversCount: newSummary.coversMessageCount)
                    }
                    print("[SessionManager] Session \(id) summarized and synced to live session")
                }
            }
        } catch {
            print("[SessionManager] Failed to save session \(id): \(error)")
        }
    }

    /// Save all dirty sessions
    func saveIfDirty() async {
        let ids = dirtySessionIds
        for id in ids {
            await saveSession(id: id)
        }
    }

    /// Save only the current session if dirty (used before switching sessions)
    private func saveCurrentSessionIfDirty() async {
        guard let id = currentSessionId, dirtySessionIds.contains(id) else { return }
        await saveSession(id: id)
    }

    /// Force immediate save of all dirty sessions (for app termination)
    func saveImmediately() {
        // Collect all sessions that need saving: dirty ones + generating ones
        var sessionIdsToSave: Set<UUID> = dirtySessionIds
        for id in generatingSessionIds {
            if let session = sessionCache[id], !session.messages.isEmpty {
                sessionIdsToSave.insert(id)
            }
        }

        guard !sessionIdsToSave.isEmpty else { return }

        // Cancel all pending debounced saves
        for (_, task) in saveDebounceTasksBySession {
            task.cancel()
        }
        saveDebounceTasksBySession.removeAll()

        // Capture values for the closure
        let contextToSave = currentContext
        let currentId = currentSessionId

        // Use semaphore to block until save completes
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            for id in sessionIdsToSave {
                guard let session = self.sessionCache[id], !session.messages.isEmpty else { continue }

                do {
                    let contextForSession = (id == currentId) ? contextToSave : nil
                    var persisted = PersistedSession.from(
                        session,
                        id: id,
                        currentContext: contextForSession
                    )
                    persisted.updatedAt = Date()
                    try await self.storage.saveSession(persisted)

                    if id == currentId {
                        try await self.storage.setActiveSessionId(id)
                    }

                    print("[SessionManager] Immediate save completed for \(id)")
                } catch {
                    print("[SessionManager] Immediate save failed for \(id): \(error)")
                }
            }
            self.dirtySessionIds.removeAll()
            semaphore.signal()
        }

        // Wait up to 5 seconds for all saves to complete
        let result = semaphore.wait(timeout: .now() + 5)
        if result == .timedOut {
            print("[SessionManager] Warning: Immediate save timed out")
        }
    }

    // MARK: - Session Observation

    private func observeSession(_ session: ChatSession, id: UUID) {
        // Cancel previous observation for this session
        sessionObservations[id] = nil

        var cancellables = Set<AnyCancellable>()

        // Observe message changes
        session.$messages
            .dropFirst()  // Skip initial value
            .sink { [weak self] _ in
                self?.markDirty(sessionId: id)
            }
            .store(in: &cancellables)

        sessionObservations[id] = cancellables
    }

    // MARK: - Clear Session

    /// Clear the current session and start fresh
    func clearCurrentSession() async {
        // Save current first if dirty
        await saveCurrentSessionIfDirty()

        // Clear state
        currentSession = nil
        currentSessionId = nil
        hasDraftSession = false

        // Clear active session in index
        do {
            try await storage.setActiveSessionId(nil)
        } catch {
            print("[SessionManager] Failed to clear active session: \(error)")
        }

        print("[SessionManager] Cleared current session")
    }

    // MARK: - List Operations

    /// Get list of all sessions
    func listSessions() async throws -> [SessionIndexEntry] {
        try await storage.listSessions()
    }

    /// Load a specific session by ID
    func loadSession(id: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        // Discard any existing draft (empty sessions are not saved)
        hasDraftSession = false

        // Save current session if dirty (but don't cancel background generations)
        await saveCurrentSessionIfDirty()

        // Check cache first to preserve approval memory
        let session: ChatSession
        if let cached = sessionCache[id] {
            session = cached
            print("[SessionManager] Using cached session \(id) (approval memory preserved)")
        } else {
            // Load from storage
            guard let persisted = try await storage.loadSession(id: id) else {
                throw StorageError.sessionNotFound(id: id)
            }
            session = persisted.toSession()
            // Cache for future retrieval
            cacheSession(session, id: id)
        }

        currentSession = session
        currentSessionId = id
        currentContext = nil  // Clear context when switching sessions

        // Set active session but don't mark dirty (don't update timestamp)
        try await storage.setActiveSessionId(id)
        observeSession(session, id: id)

        print("[SessionManager] Loaded session \(id)")
    }

    /// Delete a session by ID
    func deleteSession(id: UUID) async throws {
        // If deleting current session, clear it
        if id == currentSessionId {
            currentSession = nil
            currentSessionId = nil
            hasDraftSession = false
        }

        // Remove from cache and clean up observations
        sessionCache.removeValue(forKey: id)
        sessionObservations.removeValue(forKey: id)
        saveDebounceTasksBySession[id]?.cancel()
        saveDebounceTasksBySession.removeValue(forKey: id)
        dirtySessionIds.remove(id)
        generatingSessionIds.remove(id)
        sessionNotifications.removeValue(forKey: id)

        try await storage.deleteSession(id: id)
        sessionListVersion += 1  // Notify sidebar to refresh
        print("[SessionManager] Deleted session \(id)")
    }

    // MARK: - Session Cache

    /// Cache a session for later retrieval (preserves approval memory across switches)
    private func cacheSession(_ session: ChatSession, id: UUID) {
        sessionCache[id] = session

        // Evict oldest sessions if cache is full
        if sessionCache.count > maxCachedSessions {
            // Never evict the current session or any generating session
            if let keyToRemove = sessionCache.keys.first(where: {
                $0 != id && $0 != currentSessionId && !generatingSessionIds.contains($0)
            }) {
                sessionCache.removeValue(forKey: keyToRemove)
                sessionObservations.removeValue(forKey: keyToRemove)
                print("[SessionManager] Evicted session \(keyToRemove) from cache (limit: \(maxCachedSessions))")
            }
        }
    }

    /// Clear the session cache (e.g., on app termination)
    func clearSessionCache() {
        sessionCache.removeAll()
        sessionObservations.removeAll()
        print("[SessionManager] Cleared session cache")
    }
}
