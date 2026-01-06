# Data Model: Memory & Persistence

**Feature Branch**: `007-memory-persistence`
**Created**: 2026-01-04
**Status**: Phase 1 Design

---

## T008: Data Model Schemas

### PersistedConversation

Primary model for storing conversation state. Each session is stored as a separate file.

```swift
/// Codable representation of a conversation for persistence
struct PersistedConversation: Codable {
    // MARK: - Identity
    let id: UUID                        // Conversation identifier
    let version: Int                    // Schema version for migrations

    // MARK: - Core Data
    let messages: [ChatMessage]         // ALL messages (for UI/history viewing)
                                        // Note: Context is stored per-message in ChatMessage.contextData
    let initialRequest: String?         // Original user instruction
    let maxMessages: Int                // Max messages setting

    // MARK: - Metadata
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last modification time
    var title: String?                  // Auto-generated or user-set title

    // MARK: - Summary State (P2)
    var summary: String?                // LLM-generated summary of older messages
    var summaryCoversMessageCount: Int? // Number of messages covered by summary
    var summaryCreatedAt: Date?         // When summary was generated

    // MARK: - Schema Version
    static let currentVersion = 1

    // MARK: - LLM Context Building

    /// Build messages array for LLM API call (uses summary if available)
    func buildLLMContext() -> [ChatMessage] {
        if let summary = summary, let coveredCount = summaryCoversMessageCount, coveredCount > 0 {
            // Use summary + messages after the summarized portion
            let summaryMessage = ChatMessage(
                id: UUID(),
                role: .system,
                content: "Previous conversation context: \(summary)",
                timestamp: summaryCreatedAt ?? createdAt
            )
            let recentMessages = Array(messages.suffix(from: min(coveredCount, messages.count)))
            return [summaryMessage] + recentMessages
        } else {
            // No summary, use all messages
            return messages
        }
    }
}
```

**Encoding Strategy**:
- Use `JSONEncoder` with `.iso8601` date strategy
- Pretty print for debugging (can disable in production)
- Atomic writes for crash safety

### ChatMessage (Extended)

Extend existing `ChatMessage` to optionally include context data. Context can change mid-conversation as users invoke Extremis from different apps.

**Use Case**: User spawns Extremis from Slack, then later from Gmail in same session:
- t0: Message from Slack context (clipboard, selected text from Slack)
- t1: Message from Gmail context (different clipboard, selected email text)

```swift
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole          // .system | .user | .assistant
    let content: String
    let timestamp: Date
    let contextData: Data?      // Encoded Context (optional, for user messages)
}
```

**Notes**:
- `contextData` is optional - only present on user messages that had context
- Assistant messages will have `contextData = nil`
- Existing messages without context remain compatible (optional field)
- Context is encoded as `Data` to support any `Codable` context type

### ConversationIndex

Lightweight index for fast session listing without loading full conversation files.

```swift
/// Index entry for a single conversation (for fast listing)
struct ConversationIndexEntry: Codable, Identifiable {
    let id: UUID                        // Matches conversation file name
    var title: String                   // Display title
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last activity
    var messageCount: Int               // Total messages
    var preview: String?                // First user message (truncated)
}

/// Index file containing all conversation metadata
struct ConversationIndex: Codable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?     // Currently open conversation
    var lastUpdated: Date

    static let currentVersion = 1
}
```

**Benefits**:
- List all sessions without loading each file
- Fast sorting by date
- Search by title without full load
- Track active conversation

### UserMemory (P3)

For cross-session memory storage.

```swift
/// A single fact remembered about the user
struct UserMemory: Codable, Identifiable {
    let id: UUID
    let fact: String                    // The extracted fact
    let source: MemorySource            // How it was created
    let extractedAt: Date               // When extracted
    let confidence: Float               // LLM confidence (0.0-1.0)
    var isActive: Bool                  // User can disable without deleting
    var lastUsedAt: Date?               // Track usage for pruning

    enum MemorySource: Codable {
        case llmExtracted(conversationId: UUID)
        case userExplicit               // "Remember this" action
    }
}

/// Container for all user memories
struct UserMemoryStore: Codable {
    let version: Int
    var memories: [UserMemory]
    var lastUpdated: Date

    static let currentVersion = 1
}
```

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

### Storage Manager API

```swift
/// Manages file-based persistence for Extremis
actor StorageManager {

    // MARK: - Singleton
    static let shared = StorageManager()

    // MARK: - Paths
    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Extremis", isDirectory: true)
    }

    private var conversationsURL: URL { baseURL.appendingPathComponent("conversations") }
    private var memoriesURL: URL { baseURL.appendingPathComponent("memories") }
    private var indexURL: URL { conversationsURL.appendingPathComponent("index.json") }

    // MARK: - Index Operations

    func loadIndex() throws -> ConversationIndex
    func saveIndex(_ index: ConversationIndex) throws
    func updateIndexEntry(for conversation: PersistedConversation) throws

    // MARK: - Conversation Operations

    func saveConversation(_ conversation: PersistedConversation) throws
    func loadConversation(id: UUID) throws -> PersistedConversation?
    func deleteConversation(id: UUID) throws
    func conversationExists(id: UUID) -> Bool

    /// Create new conversation and update index
    func createConversation() throws -> PersistedConversation

    /// List all conversations (from index, no file loading)
    func listConversations() throws -> [ConversationIndexEntry]

    /// Get active conversation ID from index
    func getActiveConversationId() throws -> UUID?

    /// Set active conversation ID in index
    func setActiveConversation(id: UUID) throws

    // MARK: - Memory Operations (P3)

    func saveMemories(_ store: UserMemoryStore) throws
    func loadMemories() throws -> UserMemoryStore?
    func addMemory(_ memory: UserMemory) throws
    func deleteMemory(id: UUID) throws
    func clearAllMemories() throws

    // MARK: - Maintenance

    func ensureDirectoriesExist() throws
    func calculateStorageSize() -> Int64
    func pruneOldConversations(keepLast: Int) throws
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

| Model | Priority | Storage | Schema Version |
|-------|----------|---------|----------------|
| ConversationIndex | P1 | index.json | 1 |
| PersistedConversation | P1 | {uuid}.json (one per session) | 1 |
| Summary | P2 | (embedded in conversation) | - |
| UserMemory | P3 | user-memories.json | 1 |

**Key Decisions**:
1. JSON files in Application Support
2. One file per conversation session
3. Lightweight index.json for fast session listing
4. Summary embedded in conversation file (persisted, not re-computed)
5. All messages preserved for UI (summary used only for LLM context)
6. Atomic writes for safety
7. Debounced auto-save (2s)
8. Version field for migrations
