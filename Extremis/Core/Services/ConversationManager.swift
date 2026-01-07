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
    @Published private(set) var conversationListVersion: Int = 0  // Incremented when list changes

    // MARK: - Private State
    private var isDirty = false
    private var currentContext: Context?  // Track current context for saving with messages
    private var messageContexts: [UUID: Context] = [:]  // Map message IDs to their context
    private var saveDebounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {}

    // MARK: - Conversation Lifecycle

    /// Start a new conversation
    /// Note: Does NOT immediately save - conversation is only persisted when first message is sent
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
        // Don't set isDirty = true here - empty conversations shouldn't be saved
        // isDirty will be set when messages are added (via observeConversation)
        isDirty = false
        messageContexts = [:]  // Clear message contexts for fresh conversation

        // Observe changes to the conversation
        observeConversation(conversation)

        print("[ConversationManager] Prepared new conversation \(conversationId) (not saved until first message)")
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
            messageContexts = persisted.restoreMessageContexts()  // Restore message contexts
            isDirty = false

            // Observe changes
            observeConversation(conversation)

            print("[ConversationManager] Restored conversation \(activeId) with \(conversation.messages.count) messages and \(messageContexts.count) contexts")
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

    /// Update the current context (called when hotkey is triggered with new context)
    /// This context will be attached to the next user message when saved
    func updateCurrentContext(_ context: Context?) {
        currentContext = context
        if context != nil {
            print("[ConversationManager] Updated current context from \(context!.source.applicationName)")
        }
    }

    /// Register context for a specific message (called when user message is added)
    /// This ensures each user message has its associated context preserved
    func registerContextForMessage(messageId: UUID, context: Context?) {
        guard let ctx = context else { return }
        messageContexts[messageId] = ctx
        print("[ConversationManager] Registered context for message \(messageId) from \(ctx.source.applicationName)")
    }

    /// Get contexts for all messages (for saving)
    func getMessageContexts() -> [UUID: Context] {
        return messageContexts
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
    /// Only saves conversations that have actual content (at least one message)
    func saveIfDirty() async {
        guard isDirty, let conversation = currentConversation, let id = currentConversationId else {
            return
        }

        // Don't save empty conversations
        guard !conversation.messages.isEmpty else {
            print("[ConversationManager] Skipping save - conversation is empty")
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        do {
            // Convert to persisted format, passing contexts for all messages
            var persisted = PersistedConversation.from(
                conversation,
                id: id,
                currentContext: currentContext,
                messageContexts: messageContexts
            )
            persisted.updatedAt = Date()

            // Save to storage
            try await StorageManager.shared.saveConversation(persisted)

            // Update active conversation ID
            try await StorageManager.shared.setActiveConversation(id: id)

            isDirty = false
            conversationListVersion += 1  // Notify sidebar to refresh
            print("[ConversationManager] Saved conversation \(id) with \(messageContexts.count) message contexts")
        } catch {
            print("[ConversationManager] Failed to save: \(error)")
        }
    }

    /// Force immediate save (for app termination)
    /// Only saves conversations that have actual content
    func saveImmediately() {
        guard isDirty, let conversation = currentConversation, let id = currentConversationId else {
            return
        }

        // Don't save empty conversations
        guard !conversation.messages.isEmpty else {
            print("[ConversationManager] Skipping immediate save - conversation is empty")
            return
        }

        // Cancel any pending debounced save
        saveDebounceTask?.cancel()

        // Capture values for the closure
        let contextToSave = currentContext
        let contextsToSave = messageContexts

        // Use semaphore to block until save completes
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                var persisted = PersistedConversation.from(
                    conversation,
                    id: id,
                    currentContext: contextToSave,
                    messageContexts: contextsToSave
                )
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
        currentContext = nil  // Clear context when switching conversations
        messageContexts = persisted.restoreMessageContexts()  // Restore message contexts
        isDirty = false

        // Set active conversation but don't mark dirty (don't update timestamp)
        try await StorageManager.shared.setActiveConversation(id: id)
        observeConversation(conversation)

        print("[ConversationManager] Loaded conversation \(id) with \(messageContexts.count) message contexts")
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
        conversationListVersion += 1  // Notify sidebar to refresh
        print("[ConversationManager] Deleted conversation \(id)")
    }
}
