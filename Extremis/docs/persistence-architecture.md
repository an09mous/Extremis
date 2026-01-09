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

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `role` | ChatRole | .user, .assistant, .system |
| `content` | String | Message text |
| `timestamp` | Date | When message was created |
| `contextData` | Data? | Encoded Context (for user messages) |

**Key Features**:
- Converts to/from `ChatMessage` (live UI model)
- Context is stored as encoded `Data` to avoid polluting the live model
- Helper methods: `decodeContext()`, `encodeContext(_:)`, `hasContext`

---

### PersistedSession
**File**: `Core/Models/Persistence/PersistedSession.swift`

Complete session state for disk storage.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `version` | Int | Schema version (currently 1) |
| `messages` | [PersistedMessage] | All messages in session |
| `initialRequest` | String? | Original user request |
| `maxMessages` | Int | Max messages for context window |
| `createdAt` | Date | Session creation time |
| `updatedAt` | Date | Last modification time |
| `title` | String? | Auto-generated, immutable once set |
| `isArchived` | Bool | Whether session is archived |
| `summary` | SessionSummary? | For long-term memory |

**Key Features**:
- Separate from `ChatSession` to avoid polluting UI models
- Title is auto-generated from first message content (max 50 chars)
- `buildLLMContext()` returns optimized message array for API calls
- `restoreMessageContexts()` rebuilds the message-to-context mapping
- `summary` enables long-term memory - see [Memory Architecture](memory-architecture.md)

---

### SessionIndexEntry
**File**: `Core/Models/Persistence/SessionIndex.swift`

Lightweight metadata for fast session listing.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Session identifier |
| `title` | String | Display title |
| `createdAt` | Date | Session creation time |
| `updatedAt` | Date | Last modification time |
| `messageCount` | Int | Number of messages |
| `preview` | String? | First user message (~100 chars) |
| `isArchived` | Bool | Whether session is archived |

**Key Features**:
- Created from `PersistedSession` for index file
- Title generation: truncates first message to 50 chars at word boundary
- Preview generation: first user message, initial request, or selected text
- Backward compatibility: supports old `lastModifiedAt` key

---

### SessionIndex
**File**: `Core/Models/Persistence/SessionIndex.swift`

Master index of all sessions.

| Field | Type | Description |
|-------|------|-------------|
| `version` | Int | Index schema version |
| `sessions` | [SessionIndexEntry] | All session entries |
| `activeSessionId` | UUID? | Currently active session |
| `lastUpdated` | Date | Last index modification |

**Key Features**:
- `activeSessions` / `archivedSessions` computed properties
- `upsert(_:)` preserves existing title (immutability)
- Backward compatibility: reads old `conversations` key

---

### SessionSummary
**File**: `Core/Models/Persistence/SessionSummary.swift`

Summary of older messages for LLM context efficiency. See **[Memory Architecture](memory-architecture.md)** for detailed documentation on the hierarchical summarization system.

| Field | Type | Description |
|-------|------|-------------|
| `content` | String | The summary text |
| `coversMessageCount` | Int | Number of messages summarized |
| `createdAt` | Date | When summary was generated |
| `modelUsed` | String? | Which LLM generated it |

**Computed Properties**:
- `isValid`: True if summary has content and covers messages
- `needsRegeneration(totalMessages:threshold:)`: Determines if update needed

---

### StorageError
**File**: `Core/Models/Persistence/StorageError.swift`

Comprehensive error types for storage operations.

| Error Case | Description |
|------------|-------------|
| `directoryCreationFailed` | Failed to create storage directory |
| `fileWriteFailed` | Failed to write session/index file |
| `fileReadFailed` | Failed to read session/index file |
| `fileDeleteFailed` | Failed to delete session file |
| `encodingFailed` | Failed to encode data to JSON |
| `decodingFailed` | Failed to decode JSON data |
| `migrationFailed` | Schema migration failed |
| `sessionNotFound` | Requested session doesn't exist |
| `indexCorrupted` | Index file is corrupted |
| `storageUnavailable` | Storage system unavailable |

---

## Storage Layer

### SessionStorage Protocol
**File**: `Core/Protocols/SessionStorage.swift`

Actor-based protocol for thread-safe storage implementations.

**Operations**:

| Category | Methods |
|----------|---------|
| Initialization | `ensureStorageReady()` |
| CRUD | `saveSession()`, `loadSession()`, `deleteSession()`, `sessionExists()` |
| Listing | `listSessions()`, `listArchivedSessions()` |
| Active Session | `getActiveSessionId()`, `setActiveSessionId()` |
| Archive | `archiveSession()`, `unarchiveSession()`, `purgeArchivedBefore()` |
| Maintenance | `calculateStorageSize()`, `getStorageDescription()` |

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
4. **Schema Migration**: Handles version upgrades
5. **ISO8601 Dates**: Standard date encoding for portability

---

## Session Management

### SessionManager
**File**: `Core/Services/SessionManager.swift`

Main coordinator for session lifecycle and persistence.

**Published Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `currentSession` | ChatSession? | Active session |
| `currentSessionId` | UUID? | Active session ID |
| `isLoading` | Bool | Loading state |
| `sessionListVersion` | Int | For sidebar refresh |

**Key Behaviors**:

1. **Debounced Auto-Save (2 seconds)**:
   - Avoids excessive disk writes during active typing
   - Every change schedules a save 2 seconds later
   - New changes reset the timer

2. **Immediate Save on Terminate**:
   - Uses semaphore to block until complete
   - Waits up to 3 seconds before timing out
   - Called from `AppDelegate.applicationWillTerminate`

3. **Empty Session Handling**:
   - New sessions aren't saved until first message is added
   - `startNewSession()` doesn't mark dirty

4. **Per-Message Context Tracking**:
   - Stores context per user message
   - Enables context viewing for any message, not just the first
   - Restored on session load

5. **Generation Blocking**:
   - Tracks active generation
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

1. **JSONSessionStorage.saveSession()**: Checks for existing title and preserves it
2. **SessionIndex.upsert()**: Keeps existing title when updating entry

---

## Backward Compatibility

The system handles schema evolution through:

1. **CodingKeys with fallbacks**: Attempts new key names first, falls back to old ones

2. **Old key names supported**:
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
| `Core/Models/Persistence/SessionSummary.swift` | Summary model |
| `Core/Models/Persistence/StorageError.swift` | Error types |
| `Core/Protocols/SessionStorage.swift` | Storage protocol |
| `Core/Services/JSONSessionStorage.swift` | JSON file implementation |
| `Core/Services/SessionManager.swift` | Session lifecycle manager |
