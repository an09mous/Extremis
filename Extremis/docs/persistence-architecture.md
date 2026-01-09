# Persistence Architecture

Extremis uses a file-based JSON persistence system to store session history across app restarts. The architecture follows a layered design with clear separation between data models, storage, and session management.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer                                  │
│   PromptView ─── SessionListView ─── SessionRowView             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    SessionManager                                │
│   @MainActor, ObservableObject, Singleton                       │
│   - Debounced auto-save (2s)                                    │
│   - Session lifecycle management                                 │
│   - Per-message context tracking                                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                  SessionStorage Protocol                         │
│   Actor-based interface for thread-safe storage                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                  JSONSessionStorage                              │
│   Actor, file-based implementation                              │
│   - Atomic writes                                                │
│   - In-memory index cache                                        │
│   - Schema migration support                                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    File System                                   │
│   ~/Library/Application Support/Extremis/sessions/              │
│   ├── index.json                                                 │
│   ├── <uuid-1>.json                                              │
│   ├── <uuid-2>.json                                              │
│   └── ...                                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Models

### PersistedMessage
**File**: `Core/Models/Persistence/PersistedMessage.swift`

A single message with optional per-message context for cross-app invocations.

```swift
struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole           // .user, .assistant, .system
    let content: String
    let timestamp: Date
    let contextData: Data?       // Encoded Context (for user messages)
}
```

**Key Features**:
- Converts to/from `ChatMessage` (live UI model)
- Context is stored as encoded `Data` to avoid polluting the live model
- Helper methods: `decodeContext()`, `encodeContext(_:)`, `hasContext`

---

### PersistedSession
**File**: `Core/Models/Persistence/PersistedSession.swift`

Complete session state for disk storage.

```swift
struct PersistedSession: Codable, Identifiable, Equatable {
    let id: UUID
    let version: Int                    // Schema version (currently 1)
    var messages: [PersistedMessage]
    let initialRequest: String?
    let maxMessages: Int
    let createdAt: Date
    var updatedAt: Date
    var title: String?                  // Auto-generated, immutable once set
    var isArchived: Bool
    var summary: SessionSummary?        // For future summarization
}
```

**Key Features**:
- Separate from `ChatSession` to avoid polluting UI models
- Title is auto-generated from first message content (max 50 chars)
- `buildLLMContext()` returns optimized message array for API calls
- `restoreMessageContexts()` rebuilds the message-to-context mapping

---

### SessionIndexEntry
**File**: `Core/Models/Persistence/SessionIndex.swift`

Lightweight metadata for fast session listing.

```swift
struct SessionIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var preview: String?                // First user message (~100 chars)
    var isArchived: Bool
}
```

**Key Features**:
- Created from `PersistedSession` for index file
- Title generation: truncates first message to 50 chars at word boundary
- Preview generation: first user message, initial request, or selected text
- Backward compatibility: supports old `lastModifiedAt` key

---

### SessionIndex
**File**: `Core/Models/Persistence/SessionIndex.swift`

Master index of all sessions.

```swift
struct SessionIndex: Codable, Equatable {
    let version: Int
    var sessions: [SessionIndexEntry]
    var activeSessionId: UUID?
    var lastUpdated: Date
}
```

**Key Features**:
- `activeSessions` / `archivedSessions` computed properties
- `upsert(_:)` preserves existing title (immutability)
- Backward compatibility: reads old `conversations` key

---

### SessionSummary
**File**: `Core/Models/Persistence/SessionSummary.swift`

Summary of older messages for LLM context efficiency (future use).

```swift
struct SessionSummary: Codable, Equatable {
    let content: String
    let coversMessageCount: Int
    let createdAt: Date
    let modelUsed: String?
}
```

---

### StorageError
**File**: `Core/Models/Persistence/StorageError.swift`

Comprehensive error types for storage operations.

```swift
enum StorageError: LocalizedError {
    case directoryCreationFailed(path: String, underlying: Error)
    case fileWriteFailed(path: String, underlying: Error)
    case fileReadFailed(path: String, underlying: Error)
    case fileDeleteFailed(path: String, underlying: Error)
    case encodingFailed(type: String, underlying: Error)
    case decodingFailed(type: String, underlying: Error)
    case migrationFailed(fromVersion: Int, toVersion: Int)
    case sessionNotFound(id: UUID)
    case indexCorrupted(underlying: Error)
    case storageUnavailable
}
```

---

## Storage Layer

### SessionStorage Protocol
**File**: `Core/Protocols/SessionStorage.swift`

Actor-based protocol for thread-safe storage implementations.

```swift
protocol SessionStorage: Actor {
    // Initialization
    func ensureStorageReady() throws

    // CRUD
    func saveSession(_ session: PersistedSession) throws
    func loadSession(id: UUID) throws -> PersistedSession?
    func deleteSession(id: UUID) throws
    func sessionExists(id: UUID) -> Bool

    // Listing
    func listSessions() throws -> [SessionIndexEntry]
    func listArchivedSessions() throws -> [SessionIndexEntry]

    // Active Session
    func getActiveSessionId() throws -> UUID?
    func setActiveSessionId(_ id: UUID?) throws

    // Archive
    func archiveSession(id: UUID) throws
    func unarchiveSession(id: UUID) throws
    func purgeArchivedBefore(_ date: Date) throws

    // Maintenance
    func calculateStorageSize() throws -> Int64
    func getStorageDescription() -> String
}
```

**Design Rationale**:
- Strategy pattern allows swapping implementations (JSON, SQLite, Core Data)
- Actor requirement ensures thread safety
- Separates index operations from full session I/O

---

### JSONSessionStorage
**File**: `Core/Services/JSONSessionStorage.swift`

File-based implementation using JSON files.

**Storage Location**:
```
~/Library/Application Support/Extremis/sessions/
├── index.json          # SessionIndex with metadata
├── <uuid-1>.json       # PersistedSession
├── <uuid-2>.json
└── ...
```

**Key Features**:

1. **Atomic Writes**: Uses `.atomic` option for crash safety
2. **In-Memory Cache**: Index is cached to avoid repeated disk reads
3. **Title Immutability**: Preserves existing title on updates
4. **Schema Migration**: `migrate(_:)` handles version upgrades
5. **ISO8601 Dates**: Standard date encoding for portability

```swift
actor JSONSessionStorage: SessionStorage {
    static let shared = JSONSessionStorage()

    private var cachedIndex: SessionIndex?

    func saveSession(_ session: PersistedSession) throws {
        // Preserve existing title if updating
        var sessionToSave = session
        if let existingSession = try? loadSession(id: session.id) {
            if let existingTitle = existingSession.title {
                sessionToSave.title = existingTitle
            }
        }

        // 1. Write session file atomically
        let data = try encoder.encode(sessionToSave)
        try data.write(to: fileURL, options: .atomic)

        // 2. Update index
        var index = try loadIndex()
        index.upsert(SessionIndexEntry(from: sessionToSave))
        try saveIndex(index)
    }
}
```

---

## Session Management

### SessionManager
**File**: `Core/Services/SessionManager.swift`

Main coordinator for session lifecycle and persistence.

```swift
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var currentSession: ChatSession?
    @Published private(set) var currentSessionId: UUID?
    @Published private(set) var isLoading: Bool
    @Published private(set) var sessionListVersion: Int  // For sidebar refresh

    private let storage: any SessionStorage
    private var messageContexts: [UUID: Context]  // Per-message context tracking
    private var saveDebounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0
}
```

**Key Behaviors**:

1. **Debounced Auto-Save (2 seconds)**:
   - Avoids excessive disk writes during active typing
   - Every change schedules a save 2 seconds later
   - New changes reset the timer

2. **Immediate Save on Terminate**:
   - `saveImmediately()` uses semaphore to block until complete
   - Waits up to 3 seconds before timing out
   - Called from `AppDelegate.applicationWillTerminate`

3. **Empty Session Handling**:
   - New sessions aren't saved until first message is added
   - `startNewSession()` doesn't mark dirty

4. **Per-Message Context Tracking**:
   - `registerContextForMessage()` stores context per user message
   - Enables context viewing for any message, not just the first
   - Restored via `restoreMessageContexts()` on load

5. **Generation Blocking**:
   - Tracks active generation via `isAnySessionGenerating`
   - Prevents session switching while LLM is responding

---

## Data Flow

### Save Flow

```
User types message
       │
       ▼
ChatSession.messages updated
       │
       ▼
SessionManager observes via Combine
       │
       ▼
markDirty() → scheduleDebouncedSave()
       │
       ▼
[2 second debounce]
       │
       ▼
saveIfDirty()
       │
       ▼
PersistedSession.from(session, messageContexts)
       │
       ▼
JSONSessionStorage.saveSession()
       │
       ├─→ Write <uuid>.json (atomic)
       └─→ Update index.json
```

### Load Flow

```
App launches
       │
       ▼
AppDelegate.applicationDidFinishLaunching
       │
       ▼
SessionManager.restoreLastSession()
       │
       ▼
storage.getActiveSessionId()
       │
       ▼
storage.loadSession(id:)
       │
       ▼
PersistedSession.toSession()
       │
       ▼
restoreMessageContexts()
       │
       ▼
observeSession()
```

---

## Title Management

### Generation Rules

1. **Source**: First message content in the session (any role)
2. **Max Length**: 50 characters
3. **Truncation**: At word boundary with "…" suffix
4. **Fallback**: "New Session" if no messages

### Immutability

Titles are preserved once set. This is enforced at two levels:

1. **JSONSessionStorage.saveSession()**:
   ```swift
   if let existingSession = try? loadSession(id: session.id) {
       if let existingTitle = existingSession.title {
           sessionToSave.title = existingTitle  // Preserve
       }
   }
   ```

2. **SessionIndex.upsert()**:
   ```swift
   if let index = sessions.firstIndex(where: { $0.id == entry.id }) {
       var updatedEntry = entry
       updatedEntry.title = sessions[index].title  // Preserve
       sessions[index] = updatedEntry
   }
   ```

---

## Backward Compatibility

The system handles schema evolution through:

1. **CodingKeys with fallbacks**:
   ```swift
   // SessionIndexEntry
   if let updated = try? container.decode(Date.self, forKey: .updatedAt) {
       updatedAt = updated
   } else {
       updatedAt = try container.decode(Date.self, forKey: .lastModifiedAt)
   }
   ```

2. **Old key names**:
   - `conversations` → `sessions`
   - `activeConversationId` → `activeSessionId`
   - `lastModifiedAt` → `updatedAt`

3. **Version field**: Schema version in `PersistedSession.version` for future migrations

---

## File Locations

| File | Purpose |
|------|---------|
| `Core/Models/Persistence/PersistedMessage.swift` | Message model with context |
| `Core/Models/Persistence/PersistedSession.swift` | Session model for disk |
| `Core/Models/Persistence/SessionIndex.swift` | Index entry and index |
| `Core/Models/Persistence/SessionSummary.swift` | Summary model (future) |
| `Core/Models/Persistence/StorageError.swift` | Error types |
| `Core/Protocols/SessionStorage.swift` | Storage protocol |
| `Core/Services/JSONSessionStorage.swift` | JSON file implementation |
| `Core/Services/SessionManager.swift` | Session lifecycle manager |
