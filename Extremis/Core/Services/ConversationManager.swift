// MARK: - Conversation Manager
// Manages conversation persistence with debounced auto-save

import Foundation
import Combine

/// Manages conversation persistence with debounced auto-save
@MainActor
final class ConversationManager: ObservableObject {

    // MARK: - Singleton
    static let shared = ConversationManager()

    // MARK: - Published State
    @Published private(set) var currentConversation: ChatConversation?
    @Published private(set) var currentConversationId: UUID?
    @Published private(set) var isLoading = false

    // MARK: - Private State
    private var isDirty = false
    private var saveDebounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {}

    // MARK: - Conversation Lifecycle

    /// Start a new conversation
    func startNewConversation(
        context: Context? = nil,
        initialRequest: String? = nil
    ) async {
        // Save current conversation before starting new one
        await saveIfDirty()

        let conversation = ChatConversation(
            originalContext: context,
            initialRequest: initialRequest
        )

        let conversationId = UUID()
        currentConversation = conversation
        currentConversationId = conversationId
        isDirty = true

        // Observe changes to the conversation
        observeConversation(conversation)

        print("[ConversationManager] Started new conversation \(conversationId)")
    }

    /// Restore the last active conversation on app launch
    func restoreLastConversation() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get active conversation ID from index
            guard let activeId = try await StorageManager.shared.getActiveConversationId() else {
                print("[ConversationManager] No active conversation to restore")
                return
            }

            // Load the conversation
            guard let persisted = try await StorageManager.shared.loadConversation(id: activeId) else {
                print("[ConversationManager] Active conversation \(activeId) not found in storage")
                return
            }

            // Convert to live conversation
            let conversation = persisted.toConversation()
            currentConversation = conversation
            currentConversationId = activeId
            isDirty = false

            // Observe changes
            observeConversation(conversation)

            print("[ConversationManager] Restored conversation \(activeId) with \(conversation.messages.count) messages")
        } catch {
            print("[ConversationManager] Failed to restore conversation: \(error)")
        }
    }

    /// Set the current conversation (for cases where conversation already exists)
    func setCurrentConversation(_ conversation: ChatConversation, id: UUID? = nil) {
        currentConversation = conversation
        currentConversationId = id ?? UUID()
        isDirty = true
        observeConversation(conversation)
        scheduleDebouncedSave()  // Schedule save for the new conversation
    }

    // MARK: - Dirty Tracking

    /// Mark the conversation as modified
    func markDirty() {
        guard currentConversation != nil else { return }
        isDirty = true
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
    func saveIfDirty() async {
        guard isDirty, let conversation = currentConversation, let id = currentConversationId else {
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        do {
            // Convert to persisted format
            var persisted = PersistedConversation.from(conversation, id: id)
            persisted.updatedAt = Date()

            // Save to storage
            try await StorageManager.shared.saveConversation(persisted)

            // Update active conversation ID
            try await StorageManager.shared.setActiveConversation(id: id)

            isDirty = false
            print("[ConversationManager] Saved conversation \(id)")
        } catch {
            print("[ConversationManager] Failed to save: \(error)")
        }
    }

    /// Force immediate save (for app termination)
    func saveImmediately() {
        guard isDirty, let conversation = currentConversation, let id = currentConversationId else {
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        // Use semaphore to block until save completes
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                var persisted = PersistedConversation.from(conversation, id: id)
                persisted.updatedAt = Date()
                try await StorageManager.shared.saveConversation(persisted)
                try await StorageManager.shared.setActiveConversation(id: id)
                isDirty = false
                print("[ConversationManager] Immediate save completed for \(id)")
            } catch {
                print("[ConversationManager] Immediate save failed: \(error)")
            }
            semaphore.signal()
        }

        // Wait up to 3 seconds for save to complete
        let result = semaphore.wait(timeout: .now() + 3)
        if result == .timedOut {
            print("[ConversationManager] Warning: Immediate save timed out")
        }
    }

    // MARK: - Conversation Observation

    private func observeConversation(_ conversation: ChatConversation) {
        // Cancel previous subscriptions
        cancellables.removeAll()

        // Observe message changes
        conversation.$messages
            .dropFirst()  // Skip initial value
            .sink { [weak self] _ in
                self?.markDirty()
            }
            .store(in: &cancellables)
    }

    // MARK: - Clear Conversation

    /// Clear the current conversation and start fresh
    func clearCurrentConversation() async {
        // Save current first if dirty
        await saveIfDirty()

        // Clear state
        currentConversation = nil
        currentConversationId = nil
        isDirty = false
        cancellables.removeAll()

        // Clear active conversation in index
        do {
            try await StorageManager.shared.setActiveConversation(id: nil)
        } catch {
            print("[ConversationManager] Failed to clear active conversation: \(error)")
        }

        print("[ConversationManager] Cleared current conversation")
    }

    // MARK: - List Operations

    /// Get list of all conversations
    func listConversations() async throws -> [ConversationIndexEntry] {
        try await StorageManager.shared.listConversations()
    }

    /// Load a specific conversation by ID
    func loadConversation(id: UUID) async throws {
        isLoading = true
        defer { isLoading = false }

        // Save current first
        await saveIfDirty()

        guard let persisted = try await StorageManager.shared.loadConversation(id: id) else {
            throw StorageError.conversationNotFound(id: id)
        }

        let conversation = persisted.toConversation()
        currentConversation = conversation
        currentConversationId = id
        isDirty = false

        try await StorageManager.shared.setActiveConversation(id: id)
        observeConversation(conversation)

        print("[ConversationManager] Loaded conversation \(id)")
    }

    /// Delete a conversation by ID
    func deleteConversation(id: UUID) async throws {
        // If deleting current conversation, clear it
        if id == currentConversationId {
            currentConversation = nil
            currentConversationId = nil
            isDirty = false
            cancellables.removeAll()
        }

        try await StorageManager.shared.deleteConversation(id: id)
        print("[ConversationManager] Deleted conversation \(id)")
    }
}
