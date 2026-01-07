# Data Model: Memory & Persistence

**Feature Branch**: `007-memory-persistence`
**Created**: 2026-01-04
**Updated**: 2026-01-06
**Status**: Phase 1 Design - Validated

---

## T008: Data Model Schemas

### Design Principles

1. **Separation of Concerns**: Persistence models are separate from live UI models
2. **Extensibility**: Optional fields with defaults for backward compatibility
3. **Version Control**: Schema versioning for safe migrations
4. **Per-Message Context**: Context stored per-message to support multi-app invocations
5. **Atomic Operations**: All writes use atomic file operations

### PersistedConversation

Primary model for storing conversation state. Each session is stored as a separate file.

```swift
/// Codable representation of a conversation for persistence
/// Separate from ChatConversation to avoid polluting the live UI model
struct PersistedConversation: Codable, Identifiable, Equatable {
    // MARK: - Identity
    let id: UUID                        // Conversation identifier (generated on first save)
    let version: Int                    // Schema version for migrations

    // MARK: - Core Data
    var messages: [PersistedMessage]    // ALL messages with per-message context
    let initialRequest: String?         // Original user instruction (first invocation)
    let maxMessages: Int                // Max messages setting (for LLM context, not storage)

    // MARK: - Metadata
    let createdAt: Date                 // When conversation started (immutable)
    var updatedAt: Date                 // Last modification time
    var title: String?                  // Auto-generated or user-edited title
    var isArchived: Bool                // Soft-delete flag (future: archive old conversations)

    // MARK: - Summary State (P2)
    var summary: ConversationSummary?   // Embedded summary for LLM context efficiency

    // MARK: - Schema Version
    static let currentVersion = 1

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        version: Int = Self.currentVersion,
        messages: [PersistedMessage] = [],
        initialRequest: String? = nil,
        maxMessages: Int = 20,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        isArchived: Bool = false,
        summary: ConversationSummary? = nil
    ) {
        self.id = id
        self.version = version
        self.messages = messages
        self.initialRequest = initialRequest
        self.maxMessages = maxMessages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.isArchived = isArchived
        self.summary = summary
    }

    // MARK: - Computed Properties

    /// Whether conversation has any user content
    var hasContent: Bool {
        messages.contains { $0.role == .user || $0.role == .assistant }
    }

    /// First user message (for title generation, preview)
    var firstUserMessage: PersistedMessage? {
        messages.first { $0.role == .user }
    }

    /// Last message timestamp (for sorting)
    var lastMessageAt: Date? {
        messages.last?.timestamp
    }

    // MARK: - LLM Context Building

    /// Build messages array for LLM API call (uses summary if available)
    /// Returns: Array of messages optimized for LLM context window
    func buildLLMContext() -> [PersistedMessage] {
        guard let summary = summary, summary.isValid else {
            // No valid summary - return all messages
            return messages
        }

        // Use summary + messages after the summarized portion
        let summaryMessage = PersistedMessage(
            id: UUID(),
            role: .system,
            content: "Previous conversation context: \(summary.content)",
            timestamp: summary.createdAt,
            contextData: nil
        )

        let recentMessages = Array(messages.suffix(from: min(summary.coversMessageCount, messages.count)))
        return [summaryMessage] + recentMessages
    }

    /// Estimate token count for LLM context (rough: 1 token ≈ 4 chars)
    func estimateTokenCount() -> Int {
        let contextMessages = buildLLMContext()
        let totalChars = contextMessages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
}
```

**Encoding Strategy**:
- Use `JSONEncoder` with `.iso8601` date strategy
- Pretty print in debug, compact in production
- Atomic writes for crash safety

---

### PersistedMessage

Message model for persistence with per-message context support. **Separate from ChatMessage** to avoid polluting the live UI model.

**Design Rationale**: Users can invoke Extremis from different apps mid-conversation:
- t0: Message from Slack context (clipboard, selected text from Slack)
- t1: Message from Gmail context (different clipboard, email text)
- t2: Follow-up question (no new context needed)

```swift
/// A single message in a persisted conversation
/// Separate from ChatMessage to include context without polluting live model
struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole              // .system | .user | .assistant
    let content: String
    let timestamp: Date
    let contextData: Data?          // Encoded Context (optional, for user messages)

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        contextData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
    }

    // MARK: - Convenience Initializers

    /// Create from existing ChatMessage (without context)
    init(from message: ChatMessage, contextData: Data? = nil) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = contextData
    }

    /// Convert to ChatMessage (for UI - loses context data)
    func toChatMessage() -> ChatMessage {
        ChatMessage(id: id, role: role, content: content, timestamp: timestamp)
    }

    // MARK: - Context Helpers

    /// Decode context if present
    func decodeContext() -> Context? {
        guard let data = contextData else { return nil }
        return try? JSONDecoder().decode(Context.self, from: data)
    }

    /// Check if message has context attached
    var hasContext: Bool {
        contextData != nil
    }
}
```

**Key Points**:
- `contextData` is optional - only present on user messages that had context
- Assistant messages always have `contextData = nil`
- System messages may have `contextData = nil`
- Backward compatible: old messages without contextData work fine
- Context encoded as `Data` to support any `Codable` context type

---

### ConversationSummary

Embedded summary for efficient LLM context building. Stored within `PersistedConversation`.

```swift
/// Summary of older messages for LLM context efficiency
struct ConversationSummary: Codable, Equatable {
    let content: String             // The summary text
    let coversMessageCount: Int     // Number of messages summarized
    let createdAt: Date             // When summary was generated
    let modelUsed: String?          // Which LLM generated the summary (for debugging)

    /// Check if summary is still valid (covers at least some messages)
    var isValid: Bool {
        coversMessageCount > 0 && !content.isEmpty
    }

    /// Check if summary needs regeneration (too many new messages since)
    func needsRegeneration(totalMessages: Int, threshold: Int = 10) -> Bool {
        let newMessagesSinceSummary = totalMessages - coversMessageCount
        return newMessagesSinceSummary >= threshold
    }
}
```

### ConversationIndex

Lightweight index for fast session listing without loading full conversation files.

```swift
/// Index entry for a single conversation (for fast listing)
struct ConversationIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID                        // Matches conversation file name
    var title: String                   // Display title (auto-generated or user-edited)
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last activity (for sorting)
    var messageCount: Int               // Total messages (for display)
    var preview: String?                // First user message, truncated to ~100 chars
    var isArchived: Bool                // Soft-delete flag (mirrors conversation)

    // MARK: - Initialization

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int,
        preview: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
        self.isArchived = isArchived
    }

    /// Create entry from a PersistedConversation
    init(from conversation: PersistedConversation) {
        self.id = conversation.id
        self.title = conversation.title ?? Self.generateTitle(from: conversation)
        self.createdAt = conversation.createdAt
        self.updatedAt = conversation.updatedAt
        self.messageCount = conversation.messages.count
        self.preview = Self.generatePreview(from: conversation)
        self.isArchived = conversation.isArchived
    }

    // MARK: - Helpers

    /// Generate title from first user message
    private static func generateTitle(from conversation: PersistedConversation) -> String {
        guard let firstUserMessage = conversation.firstUserMessage else {
            return "New Conversation"
        }
        let content = firstUserMessage.content
        if content.count <= 50 {
            return content
        }
        let truncated = String(content.prefix(50))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    /// Generate preview from first user message
    private static func generatePreview(from conversation: PersistedConversation) -> String? {
        guard let firstUserMessage = conversation.firstUserMessage else {
            return nil
        }
        let content = firstUserMessage.content
        if content.count <= 100 {
            return content
        }
        return String(content.prefix(100)) + "…"
    }
}

/// Index file containing all conversation metadata
struct ConversationIndex: Codable, Equatable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?     // Currently open conversation
    var lastUpdated: Date

    static let currentVersion = 1

    // MARK: - Initialization

    init(
        version: Int = Self.currentVersion,
        conversations: [ConversationIndexEntry] = [],
        activeConversationId: UUID? = nil,
        lastUpdated: Date = Date()
    ) {
        self.version = version
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.lastUpdated = lastUpdated
    }

    // MARK: - Query Helpers

    /// Get non-archived conversations sorted by most recent
    var activeConversations: [ConversationIndexEntry] {
        conversations
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Get archived conversations
    var archivedConversations: [ConversationIndexEntry] {
        conversations
            .filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Find entry by ID
    func entry(for id: UUID) -> ConversationIndexEntry? {
        conversations.first { $0.id == id }
    }

    /// Check if conversation exists
    func contains(id: UUID) -> Bool {
        conversations.contains { $0.id == id }
    }

    // MARK: - Mutation Helpers

    /// Update or insert an entry
    mutating func upsert(_ entry: ConversationIndexEntry) {
        if let index = conversations.firstIndex(where: { $0.id == entry.id }) {
            conversations[index] = entry
        } else {
            conversations.append(entry)
        }
        lastUpdated = Date()
    }

    /// Remove entry by ID
    mutating func remove(id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
        }
        lastUpdated = Date()
    }
}
```

**Benefits**:
- List all sessions without loading each file
- Fast sorting by date (O(n log n) on small list)
- Search by title without full file load
- Track active conversation across app restarts
- Support for soft-delete (archive) without data loss

### UserMemory (P3)

For cross-session memory storage. Enables Extremis to remember facts about the user across conversations.

```swift
/// A single fact remembered about the user
struct UserMemory: Codable, Identifiable, Equatable {
    let id: UUID
    let fact: String                    // The extracted fact (single statement)
    let category: MemoryCategory        // Categorization for organization
    let source: MemorySource            // How it was created
    let extractedAt: Date               // When extracted
    var confidence: Float               // LLM confidence (0.0-1.0)
    var isActive: Bool                  // User can disable without deleting
    var lastUsedAt: Date?               // Track usage for pruning
    var usageCount: Int                 // How many times injected into context

    // MARK: - Memory Category

    enum MemoryCategory: String, Codable, CaseIterable {
        case preference                 // "User prefers concise responses"
        case technical                  // "User works with Swift and SwiftUI"
        case personal                   // "User's name is John"
        case work                       // "User works at Anthropic"
        case project                    // "User is building Extremis app"
        case other                      // Uncategorized
    }

    // MARK: - Memory Source

    enum MemorySource: Codable, Equatable {
        case llmExtracted(conversationId: UUID)  // Auto-extracted from conversation
        case userExplicit                        // User clicked "Remember this"
        case imported                            // Imported from file (future)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        fact: String,
        category: MemoryCategory = .other,
        source: MemorySource,
        extractedAt: Date = Date(),
        confidence: Float = 1.0,
        isActive: Bool = true,
        lastUsedAt: Date? = nil,
        usageCount: Int = 0
    ) {
        self.id = id
        self.fact = fact
        self.category = category
        self.source = source
        self.extractedAt = extractedAt
        self.confidence = confidence
        self.isActive = isActive
        self.lastUsedAt = lastUsedAt
        self.usageCount = usageCount
    }

    // MARK: - Computed Properties

    /// Check if memory is stale (unused for 90 days)
    var isStale: Bool {
        guard let lastUsed = lastUsedAt else {
            // Never used - check extraction date
            return extractedAt.timeIntervalSinceNow < -90 * 24 * 60 * 60
        }
        return lastUsed.timeIntervalSinceNow < -90 * 24 * 60 * 60
    }

    /// Source conversation ID if LLM-extracted
    var sourceConversationId: UUID? {
        if case .llmExtracted(let id) = source {
            return id
        }
        return nil
    }
}

/// Container for all user memories
struct UserMemoryStore: Codable, Equatable {
    let version: Int
    var memories: [UserMemory]
    var lastUpdated: Date
    var isEnabled: Bool                 // User can disable entire feature

    static let currentVersion = 1
    static let softLimit = 50           // Warn user at this count
    static let hardLimit = 100          // Require cleanup at this count

    // MARK: - Initialization

    init(
        version: Int = Self.currentVersion,
        memories: [UserMemory] = [],
        lastUpdated: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.version = version
        self.memories = memories
        self.lastUpdated = lastUpdated
        self.isEnabled = isEnabled
    }

    // MARK: - Query Helpers

    /// Get active memories for LLM injection
    var activeMemories: [UserMemory] {
        memories.filter { $0.isActive }
    }

    /// Get memories by category
    func memories(for category: UserMemory.MemoryCategory) -> [UserMemory] {
        memories.filter { $0.category == category && $0.isActive }
    }

    /// Get stale memories for review
    var staleMemories: [UserMemory] {
        memories.filter { $0.isStale }
    }

    /// Check if at soft limit
    var isAtSoftLimit: Bool {
        memories.count >= Self.softLimit
    }

    /// Check if at hard limit
    var isAtHardLimit: Bool {
        memories.count >= Self.hardLimit
    }

    // MARK: - Mutation Helpers

    /// Add memory with deduplication check
    /// Returns: true if added, false if duplicate detected
    mutating func addIfUnique(_ memory: UserMemory) -> Bool {
        // Simple check: exact fact match (future: semantic similarity)
        if memories.contains(where: { $0.fact.lowercased() == memory.fact.lowercased() }) {
            return false
        }
        memories.append(memory)
        lastUpdated = Date()
        return true
    }

    /// Mark memory as used (updates lastUsedAt and usageCount)
    mutating func markUsed(id: UUID) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].lastUsedAt = Date()
            memories[index].usageCount += 1
        }
    }

    /// Deactivate memory (soft delete)
    mutating func deactivate(id: UUID) {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].isActive = false
            lastUpdated = Date()
        }
    }

    /// Permanently remove memory
    mutating func remove(id: UUID) {
        memories.removeAll { $0.id == id }
        lastUpdated = Date()
    }

    /// Clear all memories
    mutating func clearAll() {
        memories.removeAll()
        lastUpdated = Date()
    }

    // MARK: - LLM Context Building

    /// Build memories string for system prompt injection
    func buildMemoriesContext() -> String? {
        guard isEnabled else { return nil }

        let active = activeMemories
        guard !active.isEmpty else { return nil }

        let facts = active.map { "- \($0.fact)" }.joined(separator: "\n")
        return """
        Things you know about this user:
        \(facts)

        Keep these in mind but don't mention them unless relevant.
        """
    }
}
```

**Memory Lifecycle**:
1. **Extraction**: On "New Conversation", extract facts from completed conversation
2. **Deduplication**: Check for existing similar facts before adding
3. **Injection**: Include active memories in system prompt for new conversations
4. **Tracking**: Update `lastUsedAt` and `usageCount` when memory influences response
5. **Pruning**: Flag memories unused for 90 days for user review

---

## T009: Storage Architecture

### Directory Structure

```
~/Library/Application Support/Extremis/
├── conversations/
│   ├── index.json                # Lightweight metadata for all sessions
│   ├── {uuid-1}.json             # Session 1 (full conversation + embedded summary)
│   ├── {uuid-2}.json             # Session 2
│   └── {uuid-3}.json             # Session 3
├── memories/
│   └── user-memories.json        # Cross-session facts (P3)
└── config.json                   # App settings (future)
```

### File Naming Conventions

| File | Purpose | Update Frequency |
|------|---------|------------------|
| `index.json` | Session list metadata | On conversation create/update/delete |
| `{uuid}.json` | Full conversation with embedded summary | Every message (debounced) |
| `user-memories.json` | Long-term facts about user | End of conversation |

### Example: index.json

```json
{
  "version": 1,
  "conversations": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "title": "Swift JSON Parsing Help",
      "createdAt": "2026-01-04T10:00:00Z",
      "updatedAt": "2026-01-04T10:45:00Z",
      "messageCount": 24,
      "preview": "Can you help me parse JSON in Swift?"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "title": "Memory Feature Design",
      "createdAt": "2026-01-03T14:00:00Z",
      "updatedAt": "2026-01-03T16:30:00Z",
      "messageCount": 45,
      "preview": "Build a memory and persistence feature..."
    }
  ],
  "activeConversationId": "550e8400-e29b-41d4-a716-446655440001",
  "lastUpdated": "2026-01-04T10:45:00Z"
}
```

### Example: {uuid}.json (with embedded summary and per-message context)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "version": 1,
  "title": "Swift JSON Parsing Help",
  "messages": [
    {
      "id": "msg-1",
      "role": "user",
      "content": "Can you help me parse JSON?",
      "timestamp": "2026-01-04T10:00:00Z",
      "contextData": "base64-encoded-context-from-slack"
    },
    {
      "id": "msg-2",
      "role": "assistant",
      "content": "Sure! Here's how...",
      "timestamp": "2026-01-04T10:00:30Z",
      "contextData": null
    },
    {
      "id": "msg-3",
      "role": "user",
      "content": "Now help me with this email",
      "timestamp": "2026-01-04T10:15:00Z",
      "contextData": "base64-encoded-context-from-gmail"
    }
  ],
  "createdAt": "2026-01-04T10:00:00Z",
  "updatedAt": "2026-01-04T10:45:00Z",
  "maxMessages": 20,
  "summary": "User asked about JSON parsing in Swift. Discussed Codable protocol, JSONDecoder usage, and error handling. User prefers concise examples.",
  "summaryCoversMessageCount": 14,
  "summaryCreatedAt": "2026-01-04T10:30:00Z"
}
```

**Key Points**:
- All messages stored (for UI viewing/history)
- Context stored per-message (user invoked Extremis from different apps mid-session)
- Assistant messages have `contextData: null`
- Summary covers older messages
- On reload: LLM sees summary + recent messages

### Model Conversion

Conversion between live UI models (`ChatConversation`, `ChatMessage`) and persistence models.

```swift
// MARK: - PersistedConversation Conversion

extension PersistedConversation {
    /// Create from live ChatConversation
    /// - Parameters:
    ///   - conversation: The live conversation
    ///   - id: Existing ID (for updates) or nil (for new)
    ///   - currentContext: Current context to attach to pending user message
    @MainActor
    static func from(
        _ conversation: ChatConversation,
        id: UUID? = nil,
        currentContext: Context? = nil
    ) -> PersistedConversation {
        // Convert messages with context attachment
        let persistedMessages = conversation.messages.enumerated().map { index, message -> PersistedMessage in
            var contextData: Data? = nil

            // Attach context to user messages if provided
            // First user message gets originalContext, subsequent get currentContext
            if message.role == .user {
                if index == 0, let ctx = conversation.originalContext {
                    contextData = try? JSONEncoder().encode(ctx)
                } else if let ctx = currentContext {
                    contextData = try? JSONEncoder().encode(ctx)
                }
            }

            return PersistedMessage(from: message, contextData: contextData)
        }

        return PersistedConversation(
            id: id ?? UUID(),
            messages: persistedMessages,
            initialRequest: conversation.initialRequest,
            maxMessages: conversation.maxMessages,
            title: nil  // Will be auto-generated from first user message
        )
    }

    /// Convert to live ChatConversation
    @MainActor
    func toConversation() -> ChatConversation {
        // Extract original context from first user message
        let originalContext = firstUserMessage?.decodeContext()

        let conversation = ChatConversation(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )

        // Restore messages (avoid triggering trimIfNeeded for each)
        for message in messages {
            conversation.messages.append(message.toChatMessage())
        }

        return conversation
    }
}
```

### Storage Manager API

```swift
/// Manages file-based persistence for Extremis
/// Actor ensures thread-safe file access
actor StorageManager {

    // MARK: - Singleton
    static let shared = StorageManager()

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
        try fm.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: memoriesURL, withIntermediateDirectories: true)
    }

    // MARK: - Index Operations

    func loadIndex() throws -> ConversationIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return ConversationIndex()  // Return empty index if file doesn't exist
        }
        let data = try Data(contentsOf: indexURL)
        return try decoder.decode(ConversationIndex.self, from: data)
    }

    func saveIndex(_ index: ConversationIndex) throws {
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Conversation Operations

    func saveConversation(_ conversation: PersistedConversation) throws {
        // 1. Save conversation file
        let fileURL = conversationFileURL(id: conversation.id)
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL, options: .atomic)

        // 2. Update index
        var index = try loadIndex()
        let entry = ConversationIndexEntry(from: conversation)
        index.upsert(entry)
        try saveIndex(index)
    }

    func loadConversation(id: UUID) throws -> PersistedConversation? {
        let fileURL = conversationFileURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try migrate(data)  // Apply migrations if needed
    }

    func deleteConversation(id: UUID) throws {
        // 1. Delete file
        let fileURL = conversationFileURL(id: id)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        // 2. Update index
        var index = try loadIndex()
        index.remove(id: id)
        try saveIndex(index)
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

    // MARK: - Memory Operations (P3)

    func loadMemories() throws -> UserMemoryStore {
        guard FileManager.default.fileExists(atPath: memoriesFileURL.path) else {
            return UserMemoryStore()
        }
        let data = try Data(contentsOf: memoriesFileURL)
        return try decoder.decode(UserMemoryStore.self, from: data)
    }

    func saveMemories(_ store: UserMemoryStore) throws {
        let data = try encoder.encode(store)
        try data.write(to: memoriesFileURL, options: .atomic)
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

        let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            totalSize += Int64(size)
        }

        return totalSize
    }

    /// Archive old conversations (soft delete)
    func archiveConversation(id: UUID) throws {
        guard var conversation = try loadConversation(id: id) else { return }
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
}
```

### Backup Strategy

**Atomic Writes**:
```swift
// Always use atomic writes to prevent corruption
try data.write(to: url, options: .atomic)
```

**Backup on Major Changes**:
- Before schema migrations
- Before "Clear All Data" operations
- Store in `backups/` subdirectory with timestamp

### Error Handling

```swift
enum StorageError: Error {
    case directoryCreationFailed(URL)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(URL, Error)
    case readFailed(URL, Error)
    case fileNotFound(URL)
    case migrationFailed(fromVersion: Int, toVersion: Int)
}
```

---

## Design Decisions

### Q1: Conversation ID Generation

**Decision**: Generate UUID on first save, preserve across sessions.

**Rationale**:
- Enables linking summaries to conversations
- Enables memory extraction attribution
- Simple to implement

### Q2: Auto-save Frequency (Crash-Proof Strategy)

**Decision**: Debounced save 2 seconds after last change, with immediate saves on critical events.

**Rationale**:
- Balances data safety vs performance
- Cancel debounce if user returns quickly
- Force save on app lifecycle events
- Worst case data loss: 2 seconds of work

#### Save Triggers

| Trigger | When | Why |
|---------|------|-----|
| **Debounced (2s)** | After any message change | Crash recovery - lose max 2s of work |
| **Immediate** | Insert/Copy action | User completed an action |
| **Immediate** | New Conversation | Save previous before starting fresh |
| **Immediate** | App willTerminate | Last chance before normal quit |
| **Immediate** | Session switch | Save current before loading another |

#### When `markDirty()` is Called

The conversation is marked dirty (triggering debounced save) when:
- `addUserMessage()` - User sends a message
- `addAssistantMessage()` - LLM response completes
- `removeMessageAndFollowing()` - User retries/regenerates

#### Implementation Pattern

```swift
@MainActor
class ConversationManager {
    private var saveDebounceTask: Task<Void, Never>?
    private var isDirty = false

    /// Mark conversation as needing save (starts 2s debounce)
    func markDirty() {
        isDirty = true
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await saveIfDirty()
        }
    }

    /// Save immediately if there are pending changes
    func saveIfDirty() async {
        guard isDirty else { return }
        do {
            try await StorageManager.shared.saveConversation(currentConversation)
            isDirty = false
        } catch {
            print("⚠️ Failed to save: \(error)")
        }
    }

    /// Force immediate save (cancels debounce)
    func saveNow() async {
        saveDebounceTask?.cancel()
        await saveIfDirty()
    }
}
```

#### Crash Scenario Timeline

```
t=0s: User sends message → markDirty() → debounce starts
t=1s: Assistant response arrives → markDirty() → debounce resets
t=3s: Debounce fires → SAVE
t=4s: User sends another message → markDirty() → debounce starts
t=5s: APP CRASHES
       ↓
       Lost: only the message from t=4s (1 second of work)
       Recovered: everything up to t=3s save
```

#### AppDelegate Integration

```swift
// In AppDelegate
func applicationWillTerminate(_ notification: Notification) {
    // Synchronous save - we have ~5s before forced kill
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await ConversationManager.shared.saveNow()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 3)  // Wait max 3s
}
```

**Note**: Force-quit (Cmd+Opt+Esc) does NOT trigger `willTerminate`. The debounced save strategy ensures minimal data loss in this scenario.

### Q3: Multiple Conversations

**Decision**: One JSON file per conversation + lightweight index.json.

**Rationale**:
- Each session is self-contained
- Index enables fast listing without loading full files
- Loading one session = loading one file (same efficiency as single-file)
- Scales to hundreds of sessions
- Easy to delete individual sessions

### Q4: Summary Storage

**Decision**: Embed summary directly in conversation file.

**Rationale**:
- Single file per session to manage
- Atomic consistency (summary + messages always in sync)
- On reload: use persisted summary, no re-summarization needed
- All messages preserved for UI viewing

### Q5: Memory Extraction Timing

**Decision**: Extract on "New Conversation" action.

**Rationale**:
- User has clear control
- Complete conversation context available
- Predictable behavior

### Q6: Session Memory Management

**Decision**: Load on switch, discard previous session from memory.

**Rationale**:
- Session files are small (~50-100KB), JSON parsing is fast (<50ms)
- Keeps memory footprint minimal (only 1 session in memory at a time)
- Simplest implementation
- User won't notice reload time on switch
- Can add LRU caching later if switching feels slow

**Implementation**:
```swift
@MainActor
class ConversationManager {
    private var currentConversation: ChatConversation?
    private var currentPersistedId: UUID?

    func switchToSession(id: UUID) async throws {
        // 1. Save current session if dirty
        if let current = currentConversation {
            try await saveConversation(current, id: currentPersistedId)
        }

        // 2. Load new session (discards old from memory)
        let persisted = try await StorageManager.shared.loadConversation(id: id)
        currentConversation = persisted?.toConversation()
        currentPersistedId = id
    }
}
```

**Future Enhancement**: Add LRU cache (keep last 3 sessions) if users report slow switching

### Q7: Title Generation & Editing

**Decision**: Auto-generate from first user message, allow inline editing.

**Auto-Generation**:
- Generate title when first user message is added
- Truncate to ~50 characters at word boundary
- Title remains `nil` until conversation has content

**Implementation**:
```swift
func generateTitle(from conversation: PersistedConversation) -> String {
    guard let firstUserMessage = conversation.messages.first(where: { $0.role == .user }) else {
        return "New Conversation"
    }

    let content = firstUserMessage.content
    if content.count <= 50 {
        return content
    }

    // Truncate at word boundary
    let truncated = String(content.prefix(50))
    if let lastSpace = truncated.lastIndex(of: " ") {
        return String(truncated[..<lastSpace]) + "…"
    }
    return truncated + "…"
}
```

**Title Editing**:
- Double-click title in session list to edit inline
- Right-click → "Rename" as alternative
- Updates both conversation file and index entry

**StorageManager API**:
```swift
func renameConversation(id: UUID, title: String) throws {
    // 1. Load conversation
    var conversation = try loadConversation(id: id)
    conversation?.title = title

    // 2. Save conversation
    if let conv = conversation {
        try saveConversation(conv)
    }

    // 3. Update index entry
    var index = try loadIndex()
    if let idx = index.conversations.firstIndex(where: { $0.id == id }) {
        index.conversations[idx].title = title
        try saveIndex(index)
    }
}
```

**Rationale**:
- Simple text truncation is fast and predictable
- No API cost (unlike LLM-generated titles)
- User can always override with custom title
- Future: Could add optional LLM title generation as enhancement

---

## Edge Cases & Scenarios

### E1: Partial Message on Cancel

**Scenario**: User stops generation mid-stream.

**Handling**: Already implemented in `PromptWindowController.swift`:
```swift
if Task.isCancelled {
    if !streamingContent.isEmpty {
        conv.addAssistantMessage(streamingContent)  // Save partial
    }
    return
}
```

**Persistence**: Partial content is added to conversation → debounced save triggers → persisted.

### E2: Message Retry/Regeneration

**Scenario**: User retries message #5, which removes messages 5-10.

**Handling**: `removeMessageAndFollowing(id:)` removes the message and all following messages (destructive).

**Persistence**: Save after retry completes (debounced). Old messages are lost permanently.

### E3: Message Trimming vs Persistence

**Scenario**: Conversation exceeds 20 messages.

**Handling**:
- `trimIfNeeded()` removes old messages from memory (for LLM context window)
- Persistence stores ALL messages (for UI viewing/history)
- Summary covers older messages for LLM context

**Key Point**: Memory trimming ≠ persistent trimming. Store everything, trim only for LLM.

### E4: Force-Quit / Crash Recovery

**Scenario**: User force-quits (Cmd+Opt+Esc) or app crashes.

**Handling**:
- `willTerminateNotification` does NOT fire on force-quit
- Debounced saves (2s after last change) provide recovery
- Worst case: lose last 2 seconds of changes

**Mitigation**: Save on every message add (debounced), not just on explicit actions.

### E5: Corrupted or Unreadable Files

**Scenario**: JSON file corrupted or schema incompatible.

**Handling**:
```swift
func loadConversation(id: UUID) throws -> PersistedConversation? {
    do {
        let data = try Data(contentsOf: fileURL)
        return try migrate(data)  // Handle schema versions
    } catch {
        print("⚠️ Failed to load conversation: \(error)")
        // Optionally: move corrupted file to backups/
        return nil  // Start fresh
    }
}
```

**User Experience**: Optionally notify user: "Previous conversation couldn't be restored."

### E6: Multiple Windows

**Scenario**: User opens multiple Extremis windows with different conversations.

**Handling**:
- Each window is independent (own `PromptViewModel`, own conversation)
- `activeConversationId` in index tracks most recently active
- Last-write-wins if same conversation modified in multiple windows

**P1 Acceptable**: Each window = independent session. No merge conflict handling.

### E7: Empty Conversations

**Scenario**: User opens Extremis, doesn't interact, closes.

**Handling**: Don't persist empty conversations.
```swift
func shouldPersist(_ conversation: ChatConversation) -> Bool {
    return !conversation.messages.isEmpty
}
```

### E8: Large Messages (100KB+)

**Scenario**: User pastes large code block or document.

**Handling**: JSON handles large strings fine. No special handling needed.

**File Size Estimate**:
- Typical message: ~2-5KB
- Large message: ~100KB
- Typical conversation (50 msgs): ~100-250KB
- Acceptable for JSON file storage

### E9: Streaming Chunks

**Scenario**: LLM streams response in chunks during generation.

**Handling**:
- `streamingContent` accumulates chunks (not persisted)
- Only final `addAssistantMessage(streamingContent)` triggers persistence
- UI shows streaming via `@Published var response`

**No persistence during streaming** - only persist final message.

### E10: System Clock Changes

**Scenario**: User changes system time, timestamps out of order.

**Handling**: Timestamps are informational only. Message order determined by array index, not timestamp.

**Encoding**: Use ISO8601 strategy for JSON. Millisecond precision may be lost (acceptable).

---

## Schema Migration Strategy

### Version Tracking

Each persisted struct includes a `version` field:
```swift
struct PersistedConversation: Codable {
    let version: Int  // Schema version
    // ...
    static let currentVersion = 1
}
```

### Migration Pattern

```swift
func migrate(_ data: Data) throws -> PersistedConversation {
    // Try current version first
    if let current = try? decode(data, as: PersistedConversationV1.self) {
        return current
    }

    // Try older versions and migrate
    if let v0 = try? decode(data, as: PersistedConversationV0.self) {
        return migrate(from: v0)
    }

    throw StorageError.migrationFailed(fromVersion: -1, toVersion: currentVersion)
}
```

### Backwards Compatibility

- New optional fields: Add with default values
- Removed fields: Ignore during decode
- Changed types: Require migration function

---

## Summary

### Model Overview

| Model | Priority | Storage | Schema Version | Purpose |
|-------|----------|---------|----------------|---------|
| `PersistedMessage` | P1 | (embedded) | - | Message with per-message context |
| `PersistedConversation` | P1 | `{uuid}.json` | 1 | Full conversation with embedded summary |
| `ConversationIndex` | P1 | `index.json` | 1 | Fast session listing |
| `ConversationIndexEntry` | P1 | (embedded) | - | Lightweight metadata per conversation |
| `ConversationSummary` | P2 | (embedded) | - | LLM context optimization |
| `UserMemory` | P3 | (embedded) | - | Single user fact |
| `UserMemoryStore` | P3 | `user-memories.json` | 1 | All cross-session memories |

### Key Design Decisions

1. **Separate Persistence Models**: `PersistedMessage` and `PersistedConversation` are separate from live UI models
2. **Per-Message Context**: Context stored per-message (not per-conversation) for multi-app support
3. **One File Per Session**: Each conversation is self-contained in `{uuid}.json`
4. **Lightweight Index**: `index.json` enables fast listing without loading full files
5. **Embedded Summary**: Summary stored in conversation file (persisted, not re-computed)
6. **All Messages Preserved**: Full history for UI, summary only for LLM context window
7. **Atomic Writes**: `.atomic` option prevents corruption on crash
8. **Debounced Auto-Save**: 2s delay after changes, immediate on critical events
9. **Schema Versioning**: `version` field in all persisted types for safe migrations
10. **Soft Delete**: `isArchived` flag for recoverable deletion
11. **Actor-Based Storage**: `StorageManager` is an actor for thread-safe file access

### Extensibility Points

| Extension | How | Impact |
|-----------|-----|--------|
| New message fields | Add optional field to `PersistedMessage` | Backward compatible |
| New conversation metadata | Add optional field to `PersistedConversation` | Backward compatible |
| New memory categories | Add case to `MemoryCategory` enum | Requires migration |
| Schema changes | Increment `version`, add migration handler | Managed via `migrate()` |
| New storage locations | Add URL computed property to `StorageManager` | No impact on existing |
| Caching | Add LRU cache in `StorageManager` | Internal optimization |

### Performance Characteristics

| Operation | Expected Time | Notes |
|-----------|---------------|-------|
| Load index | <10ms | Single small JSON file |
| List conversations | <10ms | Index only, no file loading |
| Load conversation | <50ms | Single file, ~100-200KB typical |
| Save conversation | <50ms | Atomic write, index update |
| Encode 1000 messages | <5ms | Validated in POC |
| Decode 1000 messages | <5ms | Validated in POC |

### File Structure

```
~/Library/Application Support/Extremis/
├── conversations/
│   ├── index.json                 # Session metadata
│   ├── {uuid-1}.json              # Conversation 1
│   ├── {uuid-2}.json              # Conversation 2
│   └── ...
├── memories/
│   └── user-memories.json         # Cross-session facts (P3)
└── config.json                    # App settings (future)
```
