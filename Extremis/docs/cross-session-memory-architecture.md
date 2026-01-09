# Cross-Session Memory Architecture (US4)

**Feature**: Memory & Persistence - User Story 4
**Status**: Architecture Complete, Implementation Deferred
**Priority**: P3 (Future Phase)
**Created**: 2026-01-09

---

## Overview

Cross-session memory enables Extremis to remember important facts about the user across conversations. Unlike session persistence (US1/US2) which stores conversation history, and summarization (US3) which compresses within-session context, cross-session memory extracts and retains discrete facts that persist indefinitely.

### Key Capabilities

1. **Automatic Fact Extraction**: LLM analyzes completed conversations to identify important user facts
2. **Persistent Storage**: Facts stored in `user-memories.json` across app restarts
3. **Context Injection**: Relevant memories injected into new conversation system prompts
4. **User Control**: View, edit, disable, or delete memories via Preferences UI

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           User Interaction                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐  │
│   │  Conversation   │     │  New Session    │     │   Preferences   │  │
│   │     Flow        │────▶│    Action       │     │      UI         │  │
│   └─────────────────┘     └────────┬────────┘     └────────┬────────┘  │
│                                    │                       │           │
└────────────────────────────────────┼───────────────────────┼───────────┘
                                     │                       │
                                     ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Service Layer                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                      MemoryService                               │  │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │  │
│   │  │  Extract    │  │  Inject     │  │  CRUD Operations        │  │  │
│   │  │  Facts      │  │  Context    │  │  (add/update/delete)    │  │  │
│   │  └─────────────┘  └─────────────┘  └─────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                    │                                    │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Data Layer                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                     UserMemoryStore                              │  │
│   │  ┌──────────────────────────────────────────────────────────┐   │  │
│   │  │  UserMemory[]                                             │   │  │
│   │  │  ┌────────────┐ ┌────────────┐ ┌────────────┐            │   │  │
│   │  │  │ fact       │ │ category   │ │ confidence │            │   │  │
│   │  │  │ source     │ │ isActive   │ │ usageCount │            │   │  │
│   │  │  └────────────┘ └────────────┘ └────────────┘            │   │  │
│   │  └──────────────────────────────────────────────────────────┘   │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                    │                                    │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Storage Layer                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ~/Library/Application Support/Extremis/memories/                      │
│   └── user-memories.json                                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Data Models

### UserMemory

Represents a single fact remembered about the user.

```swift
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
}
```

### MemoryCategory

Categories help organize and filter memories:

| Category | Description | Example |
|----------|-------------|---------|
| `preference` | User preferences for responses | "User prefers concise responses" |
| `technical` | Technical skills and tools | "User works with Swift and SwiftUI" |
| `personal` | Personal information | "User's name is John" |
| `work` | Work-related facts | "User works at Anthropic" |
| `project` | Current projects | "User is building Extremis app" |
| `other` | Uncategorized | Any other relevant facts |

### MemorySource

Tracks how a memory was created:

```swift
enum MemorySource: Codable, Equatable {
    case llmExtracted(conversationId: UUID)  // Auto-extracted from conversation
    case userExplicit                        // User clicked "Remember this"
    case imported                            // Imported from file (future)
}
```

### UserMemoryStore

Container for all user memories:

```swift
struct UserMemoryStore: Codable, Equatable {
    let version: Int
    var memories: [UserMemory]
    var lastUpdated: Date
    var isEnabled: Bool                 // User can disable entire feature

    static let currentVersion = 1
    static let softLimit = 50           // Warn user at this count
    static let hardLimit = 100          // Require cleanup at this count
}
```

---

## Storage

### File Location

```
~/Library/Application Support/Extremis/
├── sessions/                    # Session data (US1/US2)
│   ├── index.json
│   └── {uuid}.json
└── memories/                    # Cross-session memory (US4)
    └── user-memories.json       # All user facts
```

### Example: user-memories.json

```json
{
  "version": 1,
  "memories": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "fact": "User prefers concise, technical responses",
      "category": "preference",
      "source": {
        "llmExtracted": {
          "conversationId": "660e8400-e29b-41d4-a716-446655440002"
        }
      },
      "extractedAt": "2026-01-09T10:00:00Z",
      "confidence": 0.85,
      "isActive": true,
      "lastUsedAt": "2026-01-09T14:30:00Z",
      "usageCount": 5
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440003",
      "fact": "User works with Swift, SwiftUI, and macOS development",
      "category": "technical",
      "source": {
        "llmExtracted": {
          "conversationId": "660e8400-e29b-41d4-a716-446655440002"
        }
      },
      "extractedAt": "2026-01-09T10:00:00Z",
      "confidence": 0.95,
      "isActive": true,
      "lastUsedAt": "2026-01-09T15:00:00Z",
      "usageCount": 12
    }
  ],
  "lastUpdated": "2026-01-09T15:00:00Z",
  "isEnabled": true
}
```

---

## Memory Lifecycle

### 1. Extraction

**Trigger**: User clicks "New Session" (completes current conversation)

**Flow**:
```
User clicks "New Session"
         │
         ▼
┌─────────────────────────┐
│ Save current session    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ MemoryService.extract() │
│  - Build extraction     │
│    prompt               │
│  - Call LLM provider    │
│  - Parse JSON response  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Deduplicate facts       │
│  - Check existing       │
│  - Skip duplicates      │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Save to UserMemoryStore │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Start new session       │
└─────────────────────────┘
```

**Extraction Prompt**:
```
Analyze this conversation and extract important facts about the user that would be helpful to remember for future conversations.

Rules:
- Extract only facts explicitly stated or strongly implied
- Each fact should be a single, clear statement
- Assign a category: preference, technical, personal, work, project, or other
- Assign a confidence score (0.0-1.0)
- Return 0-5 facts (only the most important)

Conversation:
{conversation_content}

Return JSON array:
[
  {"fact": "...", "category": "...", "confidence": 0.0}
]
```

### 2. Deduplication

Before adding a new memory, check for duplicates:

```swift
mutating func addIfUnique(_ memory: UserMemory) -> Bool {
    // Simple check: exact fact match (case-insensitive)
    if memories.contains(where: {
        $0.fact.lowercased() == memory.fact.lowercased()
    }) {
        return false
    }
    memories.append(memory)
    lastUpdated = Date()
    return true
}
```

**Future Enhancement**: Semantic similarity check using embeddings.

### 3. Injection

**Trigger**: Starting a new conversation

**Flow**:
```swift
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
```

**System Prompt Integration**:
```
{base_system_prompt}

{memories_context}

{user_message}
```

### 4. Usage Tracking

When memories are injected, update usage stats:

```swift
mutating func markUsed(id: UUID) {
    if let index = memories.firstIndex(where: { $0.id == id }) {
        memories[index].lastUsedAt = Date()
        memories[index].usageCount += 1
    }
}
```

### 5. Pruning

**Stale Memory Detection**:
- Memory unused for 90 days is flagged as stale
- Stale memories shown in Preferences for user review

```swift
var isStale: Bool {
    guard let lastUsed = lastUsedAt else {
        return extractedAt.timeIntervalSinceNow < -90 * 24 * 60 * 60
    }
    return lastUsed.timeIntervalSinceNow < -90 * 24 * 60 * 60
}
```

**Limits**:
- Soft limit (50): Warn user, suggest review
- Hard limit (100): Block new memories until cleanup

---

## MemoryService API

```swift
@MainActor
class MemoryService {
    static let shared = MemoryService()

    private var store: UserMemoryStore

    // MARK: - Extraction

    /// Extract memories from a completed conversation
    func extractMemories(from session: PersistedSession) async throws -> [UserMemory]

    // MARK: - Query

    /// Get all active memories for injection
    func activeMemories() -> [UserMemory]

    /// Get memories by category
    func memories(for category: MemoryCategory) -> [UserMemory]

    /// Get stale memories for review
    func staleMemories() -> [UserMemory]

    /// Build context string for system prompt
    func buildContext() -> String?

    // MARK: - Mutation

    /// Add memory (with deduplication)
    func addMemory(_ memory: UserMemory) -> Bool

    /// Update memory confidence/category
    func updateMemory(id: UUID, confidence: Float?, category: MemoryCategory?)

    /// Deactivate memory (soft delete)
    func deactivateMemory(id: UUID)

    /// Permanently delete memory
    func deleteMemory(id: UUID)

    /// Clear all memories
    func clearAll()

    // MARK: - Settings

    /// Enable/disable memory feature
    var isEnabled: Bool { get set }

    // MARK: - Usage Tracking

    /// Mark memories as used (called after injection)
    func markUsed(ids: [UUID])
}
```

---

## User Interface

### Preferences Panel

Location: `Extremis/UI/Preferences/MemoryPreferencesView.swift`

**Features**:

1. **Toggle**: Enable/disable cross-session memory
2. **Memory List**: Scrollable list of all memories
   - Category badge (color-coded)
   - Confidence indicator
   - Usage count
   - Last used date
3. **Actions per Memory**:
   - Toggle active/inactive
   - Edit fact text
   - Change category
   - Delete
4. **Bulk Actions**:
   - Clear all memories
   - Export to JSON
   - Import from JSON (future)
5. **Stats**:
   - Total memories
   - Active vs inactive count
   - Storage used

**Mockup**:
```
┌─────────────────────────────────────────────────────────────────┐
│ Memory Preferences                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ [✓] Enable Cross-Session Memory                                 │
│                                                                 │
│ ─────────────────────────────────────────────────────────────── │
│                                                                 │
│ 12 memories (10 active, 2 inactive)                            │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ [Technical] User works with Swift and SwiftUI               ││
│ │ Confidence: 95% | Used 12 times | Last: 2 hours ago        ││
│ │ [Toggle] [Edit] [Delete]                                    ││
│ ├─────────────────────────────────────────────────────────────┤│
│ │ [Preference] User prefers concise responses                 ││
│ │ Confidence: 85% | Used 5 times | Last: 4 hours ago         ││
│ │ [Toggle] [Edit] [Delete]                                    ││
│ ├─────────────────────────────────────────────────────────────┤│
│ │ [Work] User works at Anthropic                              ││
│ │ Confidence: 90% | Used 3 times | Last: 1 day ago           ││
│ │ [Toggle] [Edit] [Delete]                                    ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ [Clear All Memories]                       [Export to JSON]     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Integration Points

### 1. SessionManager Integration

When starting a new session, extract memories from the completed one:

```swift
// In SessionManager
func startNewSession() async {
    // 1. Save current session
    await saveCurrentSession()

    // 2. Extract memories (non-blocking)
    if let current = currentSession {
        Task {
            try? await MemoryService.shared.extractMemories(from: current)
        }
    }

    // 3. Create new session
    currentSession = ChatSession()
}
```

### 2. PromptBuilder Integration

Inject memories into system prompt:

```swift
// In PromptBuilder
func buildSystemPrompt(basePrompt: String) -> String {
    var prompt = basePrompt

    // Inject memories if available
    if let memoriesContext = MemoryService.shared.buildContext() {
        prompt += "\n\n" + memoriesContext
    }

    return prompt
}
```

### 3. AppDelegate Integration

Load memories on app launch:

```swift
// In AppDelegate
func applicationDidFinishLaunching(_ notification: Notification) {
    // Load memory store
    Task {
        await MemoryService.shared.load()
    }
}
```

---

## Privacy & Security

### Data Handling

1. **Local Storage Only**: All memories stored locally, never transmitted
2. **User Control**: Users can view, edit, disable, or delete any memory
3. **Feature Toggle**: Entire feature can be disabled
4. **Clear Data**: One-click to clear all memories

### Sensitive Data

- Memories may contain PII (names, companies, preferences)
- Storage in Application Support is protected by macOS permissions
- No cloud sync (could be added with encryption in future)

---

## Implementation Tasks

| Task ID | Description | File | Dependencies |
|---------|-------------|------|--------------|
| T032 | Create UserMemory model | `Core/Models/Persistence/UserMemory.swift` | None |
| T033 | Create UserMemoryStore model | `Core/Models/Persistence/UserMemory.swift` | T032 |
| T034 | Implement MemoryService | `Core/Services/MemoryService.swift` | T032, T033 |
| T035 | Memory extraction on New Session | SessionManager integration | T034 |
| T036 | Memory injection in system prompt | PromptBuilder integration | T034 |
| T037 | Memory UI in Preferences | `UI/Preferences/MemoryPreferencesView.swift` | T034 |

---

## Future Enhancements

1. **Semantic Deduplication**: Use embeddings to detect similar facts
2. **Memory Prioritization**: Rank by confidence × usage for limited context
3. **Explicit Memory**: "Remember this" button during conversation
4. **Memory Suggestions**: Prompt user to confirm extracted facts
5. **Import/Export**: Share memories between devices
6. **Memory Decay**: Automatically reduce confidence of unused memories
7. **Category Filters**: Filter injected memories by category

---

## Related Documentation

- [Memory Architecture](./memory-architecture.md) - Session summarization (US3)
- [Persistence Architecture](./persistence-architecture.md) - Session persistence (US1/US2)
- [Data Model Spec](../specs/007-memory-persistence/data-model.md) - Full data model specification
