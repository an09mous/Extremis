// MARK: - Session Manager
// Manages session persistence with debounced auto-save

import Foundation
import Combine

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

    /// Whether any session is currently generating (blocks session switching)
    @Published private(set) var isAnySessionGenerating: Bool = false
    /// The ID of the session currently generating (if any)
    @Published private(set) var generatingSessionId: UUID? = nil

    /// Whether the current session is a draft (not yet persisted)
    /// True when session exists but has no messages (not saved to disk)
    @Published private(set) var hasDraftSession: Bool = false

    // MARK: - Private State
    private var isDirty = false
    private var currentContext: Context?  // Track current context for saving with messages
    private var saveDebounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0
    private var cancellables = Set<AnyCancellable>()
    private var sessionObservationCancellables = Set<AnyCancellable>()

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

        // Subscribe to stealth mode changes for auto-switch on disable (FR-006)
        StealthManager.shared.$isStealthActive
            .dropFirst()  // Skip initial value
            .sink { [weak self] isActive in
                guard let self = self else { return }
                if !isActive {
                    Task { @MainActor in
                        await self.handleStealthDeactivation()
                    }
                }
                // On stealth enable: no session change (FR-007)
                // Just refresh sidebar to show/hide stealth sessions
                self.sessionListVersion += 1
            }
            .store(in: &cancellables)
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
        await saveIfDirty()

        let session = ChatSession(
            originalContext: context,
            initialRequest: initialRequest,
            isStealth: StealthManager.shared.isStealthActive
        )

        let sessionId = UUID()
        currentSession = session
        currentSessionId = sessionId
        // Don't set isDirty = true here - empty sessions shouldn't be saved
        // isDirty will be set when messages are added (via observeSession)
        isDirty = false
        hasDraftSession = true  // Mark as draft until first message is sent

        // Cache the session for later retrieval
        cacheSession(session, id: sessionId)

        // Observe changes to the session
        observeSession(session)

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

            // Don't restore a stealth session in normal mode
            if persisted.isStealth && !StealthManager.shared.isStealthActive {
                print("[SessionManager] Skipping restore — stealth session \(activeId) in normal mode")
                return
            }

            // Convert to live session (context and images restored from persistence)
            let session = await persisted.toSession()
            currentSession = session
            currentSessionId = activeId
            isDirty = false
            hasDraftSession = false  // Restored sessions are not drafts

            // Cache the session for later retrieval
            cacheSession(session, id: activeId)

            // Observe changes
            observeSession(session)

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
        isDirty = true
        hasDraftSession = session.messages.isEmpty  // Draft if no messages yet

        // Cache the session for later retrieval
        cacheSession(session, id: sessionId)
        observeSession(session)
        scheduleDebouncedSave()  // Schedule save for the new session
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

    /// Register that a session is actively generating (blocks session switching)
    func registerActiveGeneration(sessionId: UUID) {
        isAnySessionGenerating = true
        generatingSessionId = sessionId
        print("[SessionManager] Registered active generation for session \(sessionId)")
    }

    /// Unregister when generation completes (re-enables session switching)
    func unregisterActiveGeneration(sessionId: UUID) {
        // Only clear if this is the session that was generating
        if generatingSessionId == sessionId {
            isAnySessionGenerating = false
            generatingSessionId = nil
            print("[SessionManager] Unregistered active generation for session \(sessionId)")
        }
    }

    // MARK: - Dirty Tracking

    /// Mark the session as modified
    func markDirty() {
        guard let session = currentSession else { return }
        isDirty = true

        // Draft becomes real session once it has content
        if hasDraftSession && !session.messages.isEmpty {
            hasDraftSession = false
            print("[SessionManager] Session transitioned from draft to saved")

            // Save immediately when draft becomes real session
            // This ensures the sidebar updates with the proper title right away
            Task {
                await saveIfDirty()
            }
            return  // Don't schedule another debounced save
        }

        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(debounceInterval))
                guard !Task.isCancelled else { return }
                await saveIfDirty()
            } catch {
                // Task was cancelled - that's fine
            }
        }
    }

    // MARK: - Save Operations

    /// Save if there are unsaved changes
    /// Only saves sessions that have actual content (at least one message)
    func saveIfDirty() async {
        guard isDirty, let session = currentSession, let id = currentSessionId else {
            return
        }

        // Don't save empty sessions
        guard !session.messages.isEmpty else {
            print("[SessionManager] Skipping save - session is empty")
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        do {
            // Convert to persisted format (context and images saved to disk)
            var persisted = await PersistedSession.from(
                session,
                id: id,
                currentContext: currentContext
            )
            persisted.updatedAt = Date()

            // Save to storage
            try await storage.saveSession(persisted)

            // Update active session ID
            try await storage.setActiveSessionId(id)

            isDirty = false
            sessionListVersion += 1  // Notify sidebar to refresh
            print("[SessionManager] Saved session \(id)")

            // Check if summarization is needed (runs async, doesn't block)
            let storageRef = self.storage
            Task { [weak self] in
                let updated = await SummarizationManager.shared.summarizeIfNeeded(persisted, storage: storageRef)
                if let newSummary = updated.summary, newSummary != persisted.summary {
                    // Sync summary back to live session for immediate use
                    await MainActor.run {
                        self?.currentSession?.updateSummary(newSummary, coversCount: newSummary.coversMessageCount)
                    }
                    print("[SessionManager] Session summarized and synced to live session")
                }
            }
        } catch {
            print("[SessionManager] Failed to save: \(error)")
        }
    }

    /// Force immediate save (for app termination)
    /// Only saves sessions that have actual content
    func saveImmediately() {
        guard isDirty, let session = currentSession, let id = currentSessionId else {
            return
        }

        // Don't save empty sessions
        guard !session.messages.isEmpty else {
            print("[SessionManager] Skipping immediate save - session is empty")
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        // Capture values for the closure
        let contextToSave = currentContext

        // Use semaphore to block until save completes
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                var persisted = await PersistedSession.from(
                    session,
                    id: id,
                    currentContext: contextToSave
                )
                persisted.updatedAt = Date()
                try await storage.saveSession(persisted)
                try await storage.setActiveSessionId(id)
                isDirty = false
                print("[SessionManager] Immediate save completed for \(id)")
            } catch {
                print("[SessionManager] Immediate save failed: \(error)")
            }
            semaphore.signal()
        }

        // Wait up to 3 seconds for save to complete
        let result = semaphore.wait(timeout: .now() + 3)
        if result == .timedOut {
            print("[SessionManager] Warning: Immediate save timed out")
        }
    }

    // MARK: - Session Observation

    private func observeSession(_ session: ChatSession) {
        // Cancel previous session-specific subscriptions (preserves stealth subscription)
        sessionObservationCancellables.removeAll()

        // Observe message changes
        session.$messages
            .dropFirst()  // Skip initial value
            .sink { [weak self] _ in
                self?.markDirty()
            }
            .store(in: &sessionObservationCancellables)
    }

    // MARK: - Clear Session

    /// Clear the current session and start fresh
    func clearCurrentSession() async {
        // Save current first if dirty
        await saveIfDirty()

        // Clear state
        currentSession = nil
        currentSessionId = nil
        isDirty = false
        hasDraftSession = false
        sessionObservationCancellables.removeAll()

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

        // Save current first (if it has content)
        await saveIfDirty()

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
            session = await persisted.toSession()
            // Cache for future retrieval
            cacheSession(session, id: id)
        }

        currentSession = session
        currentSessionId = id
        currentContext = nil  // Clear context when switching sessions
        isDirty = false

        // Set active session but don't mark dirty (don't update timestamp)
        try await storage.setActiveSessionId(id)
        observeSession(session)

        print("[SessionManager] Loaded session \(id)")
    }

    /// Delete a session by ID
    func deleteSession(id: UUID) async throws {
        // If deleting current session, clear it
        if id == currentSessionId {
            currentSession = nil
            currentSessionId = nil
            isDirty = false
            hasDraftSession = false
            sessionObservationCancellables.removeAll()
        }

        // Remove from cache
        sessionCache.removeValue(forKey: id)

        try await storage.deleteSession(id: id)
        sessionListVersion += 1  // Notify sidebar to refresh
        print("[SessionManager] Deleted session \(id)")
    }

    // MARK: - Stealth Isolation

    /// Handle stealth mode deactivation: switch away from stealth sessions (FR-006)
    private func handleStealthDeactivation() async {
        // Always evict stealth sessions from in-memory cache
        let stealthKeys = sessionCache.filter { $0.value.isStealth }.map { $0.key }
        for key in stealthKeys {
            sessionCache.removeValue(forKey: key)
        }
        if !stealthKeys.isEmpty {
            print("[SessionManager] Evicted \(stealthKeys.count) stealth session(s) from cache")
        }

        // If current session is not stealth, no switch needed
        guard let session = currentSession, session.isStealth else { return }

        print("[SessionManager] Stealth deactivated — switching away from stealth session")

        // Save current stealth session before switching
        await saveIfDirty()

        // Find most recent normal (non-stealth, non-archived) session
        do {
            let allSessions = try await storage.listSessions()
            let normalSessions = allSessions
                .filter { !$0.isStealth && !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }

            if let mostRecent = normalSessions.first {
                try await loadSession(id: mostRecent.id)
                print("[SessionManager] Switched to normal session \(mostRecent.id)")
            } else {
                // No normal sessions — clear active session
                currentSession = nil
                currentSessionId = nil
                hasDraftSession = false
                try await storage.setActiveSessionId(nil)
                print("[SessionManager] No normal sessions — cleared active session")
            }
        } catch {
            print("[SessionManager] Error during stealth deactivation switch: \(error)")
            // Fallback: clear active session to prevent stealth content showing
            currentSession = nil
            currentSessionId = nil
            hasDraftSession = false
        }
    }

    // MARK: - Session Cache

    /// Cache a session for later retrieval (preserves approval memory across switches)
    private func cacheSession(_ session: ChatSession, id: UUID) {
        sessionCache[id] = session

        // Evict oldest sessions if cache is full
        if sessionCache.count > maxCachedSessions {
            // Remove sessions that aren't the current one
            // Keep a simple LRU-ish approach: just remove one that's not current
            if let keyToRemove = sessionCache.keys.first(where: { $0 != id && $0 != currentSessionId }) {
                sessionCache.removeValue(forKey: keyToRemove)
                print("[SessionManager] Evicted session \(keyToRemove) from cache (limit: \(maxCachedSessions))")
            }
        }
    }

    /// Clear the session cache (e.g., on app termination)
    func clearSessionCache() {
        sessionCache.removeAll()
        print("[SessionManager] Cleared session cache")
    }
}
