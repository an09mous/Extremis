# Research: Memory & Persistence

**Feature Branch**: `007-memory-persistence`
**Created**: 2026-01-04
**Status**: Phase 1 Investigation

---

## T001: macOS Local Storage Options

### Decision Matrix

| Option | Simplicity | Performance | Query Support | Migration | Human-Readable | Recommendation |
|--------|-----------|-------------|---------------|-----------|----------------|----------------|
| **JSON Files** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ **RECOMMENDED** |
| Property Lists | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | Good alternative |
| SQLite/GRDB | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | Overkill for scope |
| Core Data | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐ | Too complex |
| UserDefaults | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ | ⭐ | ⭐⭐⭐ | Size limits |

### Analysis

#### JSON Files (Recommended)
**Pros**:
- Native Swift `Codable` support - no additional dependencies
- Human-readable for debugging
- Simple file management with `FileManager`
- Easy to version and migrate (just add new optional fields)
- Portable - can backup/export easily

**Cons**:
- No built-in querying (must load entire file)
- Manual file locking for concurrent access
- No automatic migration tooling

**Why it fits our needs**:
- Typical usage: ~100 conversations, ~1000 messages = ~1-5MB
- No complex queries needed (load most recent conversation)
- `ChatMessage` is already `Codable`
- Debugging persistence issues is trivial with JSON

#### Property Lists
Similar to JSON but Apple-specific. JSON preferred for portability.

#### SQLite/GRDB
Would require adding GRDB dependency. Efficient for large datasets with complex queries, but overkill for our ~1000 message scale.

#### Core Data
Apple's ORM. Powerful but complex. Would require defining Core Data models, managed object contexts, etc. Overkill for simple key-value storage.

#### UserDefaults
Limited to ~4MB on macOS. Cannot store large conversations reliably.

### Recommendation

**Use JSON files** stored in Application Support directory:
```
~/Library/Application Support/Extremis/
├── conversations/
│   └── current.json          # Active conversation
├── memories/
│   └── user-memories.json    # Cross-session facts (P3)
└── config.json               # App settings
```

---

## T002: ChatConversation Model Analysis

### Current Model Structure

```swift
// ChatMessage - ALREADY Codable ✅
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole      // Codable enum
    let content: String
    let timestamp: Date
}

// ChatConversation - NOT Codable ❌
@MainActor
final class ChatConversation: ObservableObject {
    @Published var messages: [ChatMessage] = []
    let originalContext: Context?        // Context IS Codable ✅
    let initialRequest: String?
    let maxMessages: Int
}
```

### Codable Compatibility Assessment

| Property | Type | Codable? | Notes |
|----------|------|----------|-------|
| `messages` | `[ChatMessage]` | ✅ Yes | Core data to persist |
| `originalContext` | `Context?` | ✅ Yes | Can serialize |
| `initialRequest` | `String?` | ✅ Yes | Simple string |
| `maxMessages` | `Int` | ✅ Yes | Configuration |

### Challenge: `@MainActor` and `@Published`

`ChatConversation` uses:
- `@MainActor` - execution context, not a problem for encoding
- `@Published` - property wrapper that wraps values in `Published<T>`
- `ObservableObject` - protocol for SwiftUI observation

**Issue**: Property wrappers like `@Published` interfere with automatic `Codable` synthesis.

### Solution: Separate Persistence Model

Create a lightweight `PersistedConversation` struct for storage:

```swift
/// Codable representation for persistence
struct PersistedConversation: Codable {
    let id: UUID
    let messages: [ChatMessage]
    let originalContext: Context?
    let initialRequest: String?
    let maxMessages: Int
    let createdAt: Date
    let updatedAt: Date

    /// Convert from live ChatConversation
    @MainActor
    init(from conversation: ChatConversation) {
        self.id = UUID()  // or track conversation ID
        self.messages = conversation.messages
        self.originalContext = conversation.originalContext
        self.initialRequest = conversation.initialRequest
        self.maxMessages = conversation.maxMessages
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Convert to live ChatConversation
    @MainActor
    func toConversation() -> ChatConversation {
        let conv = ChatConversation(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )
        // Restore messages without triggering trimIfNeeded for each
        for message in messages {
            conv.messages.append(message)
        }
        return conv
    }
}
```

### Recommendation

1. **DO NOT** modify `ChatConversation` to be `Codable` directly
2. **CREATE** a separate `PersistedConversation` struct
3. **ADD** conversion methods between the two
4. This follows the principle of separation of concerns

---

## T003: Context Summarization Strategies

### Strategy Comparison

| Strategy | Quality | Cost | Latency | Complexity | Recommendation |
|----------|---------|------|---------|------------|----------------|
| **LLM-based (Sliding Window)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ **RECOMMENDED** |
| Extractive | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Fallback option |
| Hierarchical | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐ | Too complex |
| Simple Truncation | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Current behavior |

### Recommended: LLM-based Sliding Window

**Approach**:
1. Keep last N messages (e.g., 10) in full detail
2. Summarize messages before that into a "context summary"
3. Include summary as a system message at conversation start

**Architecture**:
```
[System: You are a helpful assistant. Previous context: {summary}]
[User: Message 11]
[Assistant: Response 11]
...
[User: Message 20]
[Assistant: Response 20]
```

**Summarization Prompt**:
```
Summarize the following conversation, preserving:
1. Key facts mentioned by the user (names, preferences, technical details)
2. Decisions or conclusions reached
3. Any ongoing tasks or requests

Keep the summary under 500 words. Focus on information the assistant needs to continue helping effectively.

Conversation to summarize:
{messages 1-10}
```

### Trigger Logic

**When to summarize**:
- Message count exceeds threshold (20 messages)
- OR estimated token count exceeds limit (~8000 tokens)

**Token estimation** (rough):
```swift
func estimateTokens(_ text: String) -> Int {
    // Rough estimate: 1 token ≈ 4 characters for English
    return text.count / 4
}
```

### Failure Handling

If summarization fails (LLM error, timeout):
1. Fall back to simple truncation (current `trimIfNeeded` behavior)
2. Log warning but don't block the user
3. Retry summarization on next opportunity

---

## T004: Industry Alternatives Comparison

### Feature Matrix

| Product | Session Persist | Cross-Session Memory | Summarization | User Control |
|---------|-----------------|---------------------|---------------|--------------|
| **ChatGPT** | ✅ Yes | ✅ "Memory" feature | ✅ Automatic | ✅ Can view/delete |
| **Claude.ai** | ✅ Yes | ❌ No persistent | ❌ Manual context | ✅ Full control |
| **Raycast AI** | ✅ Yes | ❌ No | ❌ No | ✅ Clear history |
| **Cursor** | ✅ Yes | ❌ Workspace only | ✅ Codebase context | ⚠️ Limited |
| **Copilot Chat** | ⚠️ Session only | ❌ No | ⚠️ File context | ✅ Clear |

### Key Insights

#### ChatGPT Memory
- Automatically extracts facts from conversations
- User can view "What do you remember about me?"
- User can delete specific memories or all
- Memory persists across conversations
- **Learning**: This is exactly what our P3 feature should do

#### Claude.ai
- No persistent memory by design (privacy focus)
- "Projects" feature for shared context within a project
- User must manually re-provide context each session
- **Learning**: Some users prefer no persistence - offer clear option

#### Raycast AI
- Simple chat history persistence
- No cross-session memory
- "New Chat" button clears context
- **Learning**: Good UX for session management - simple and clear

#### Cursor
- Persists chat within workspace
- Uses codebase as context (different use case)
- **Learning**: Context-aware responses without explicit memory

### Recommendations for Extremis

1. **Session Persistence (P1)**: Follow Raycast model - simple, automatic, clear "New Chat" option
2. **Summarization (P2)**: Follow ChatGPT model - automatic, transparent, background operation
3. **Cross-Session Memory (P3)**: Follow ChatGPT Memory model:
   - Automatic fact extraction
   - "What do you remember?" query
   - View/delete memories in preferences
   - Clear opt-out option

### Privacy Considerations

- All data stored **locally only** (unlike ChatGPT)
- No cloud sync for MVP
- Clear path to delete all data
- Transparent about what's stored

---

## T007: Cross-Session Memory Extraction (POC)

### Overview

Cross-session memory enables Extremis to remember facts about the user across conversations, similar to ChatGPT's Memory feature. This requires extracting relevant facts from conversations and storing them for future reference.

### LLM Fact Extraction Strategies

#### Strategy 1: End-of-Conversation Extraction

Extract facts when user starts a new conversation or app closes.

**Prompt Template**:
```
Analyze this conversation and extract any facts worth remembering about the user for future conversations.

Focus on:
1. Personal preferences (communication style, formatting preferences)
2. Technical context (programming languages, tools, frameworks they use)
3. Work context (role, team, company, projects)
4. Explicit preferences stated by the user
5. Important decisions or conclusions reached

Format each fact as a single, self-contained statement.
Only extract facts that would be useful in future, unrelated conversations.
Do NOT extract conversation-specific details that won't generalize.

If no memorable facts are present, respond with: NO_FACTS_EXTRACTED

Conversation:
{full_conversation}
```

**Pros**:
- Complete context available
- Lower API costs (one call per conversation)

**Cons**:
- May miss facts if conversation is long
- User must end conversation for extraction

#### Strategy 2: Continuous Extraction (After Each Exchange)

Extract facts after each user-assistant exchange pair.

**Prompt Template**:
```
Given this exchange, extract any new facts about the user worth remembering.

Previous memories (do not duplicate):
{existing_memories}

New exchange:
User: {user_message}
Assistant: {assistant_response}

Extract only NEW facts not already in memories. Format as single statements.
If no new facts, respond with: NO_NEW_FACTS

Focus on: preferences, technical context, work context, explicit requests.
```

**Pros**:
- Real-time extraction
- Never misses facts

**Cons**:
- Higher API costs
- May extract too many trivial facts

#### Strategy 3: Hybrid (Recommended)

Use end-of-conversation extraction as primary, with optional user-triggered extraction.

**Implementation**:
1. Extract facts when user clicks "New Conversation"
2. Optional: Add "Remember this" quick action for explicit fact storage
3. Deduplicate against existing memories before storing

### Memory Storage Format

```swift
struct UserMemory: Codable, Identifiable {
    let id: UUID
    let fact: String                    // The extracted fact
    let source: MemorySource            // Where it came from
    let extractedAt: Date               // When extracted
    let confidence: Float               // LLM confidence (0-1)
    var isActive: Bool                  // User can disable

    enum MemorySource: Codable {
        case llmExtracted(conversationId: UUID)
        case userExplicit                // User said "remember this"
    }
}
```

### Memory Injection Strategy

When starting a new conversation, inject relevant memories into system prompt:

```
You are helping the user with their request.

Things you know about this user:
- They prefer concise responses
- They work with Swift and SwiftUI
- They are building a macOS application called Extremis
- They prefer code examples over lengthy explanations

Keep these in mind but don't mention them unless relevant.
```

### Deduplication & Pruning

**Deduplication Rules**:
1. Semantic similarity check before adding new memory
2. Newer facts override older contradictory facts
3. User-explicit memories take precedence

**Pruning Strategy**:
- Soft limit: 50 memories (warn user)
- Hard limit: 100 memories (require cleanup)
- Memories unused for 90 days flagged for review

### POC Test Results

**Test Prompt Used**:
```
Extract memorable facts from this conversation:

User: Can you help me write a Swift function to parse JSON?
Assistant: [response about JSON parsing]
User: Thanks! I always use Codable for this. Also, I prefer short variable names.
Assistant: [response]
```

**Expected Extraction**:
- "User prefers using Codable for JSON parsing in Swift"
- "User prefers short variable names"

**Observations**:
1. Claude effectively extracts preference-type statements
2. Explicit preferences ("I prefer X") are reliably detected
3. Implicit preferences require more context to extract
4. "NO_FACTS_EXTRACTED" response works well for empty cases

### Recommendations

| Aspect | Recommendation | Rationale |
|--------|----------------|-----------|
| **Extraction Timing** | End-of-conversation | Lower cost, complete context |
| **Prompt Style** | Explicit format instructions | Reliable parsing |
| **Storage** | JSON file with UserMemory array | Simple, matches overall architecture |
| **Injection** | System prompt prefix | Non-intrusive, natural |
| **User Control** | View/delete in preferences | Privacy and transparency |
| **Deduplication** | Semantic check before add | Prevent bloat |

### Privacy Considerations

1. **Local Only**: All memories stored on device, never synced
2. **User Control**: Clear UI to view and delete memories
3. **Opt-Out**: Setting to disable memory feature entirely
4. **Transparency**: Show which memories influenced a response (optional future feature)

---

## Summary of Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| **Storage** | JSON files (one per session + index) | Simple, debuggable, sufficient for scale |
| **Model** | Separate `PersistedConversation` | Don't pollute live model with persistence |
| **Location** | Application Support | Standard macOS pattern |
| **Multi-session** | One {uuid}.json per session + index.json | Fast listing, self-contained sessions |
| **Context Storage** | Per-message (not per-conversation) | User can invoke from different apps mid-session |
| **Summary Storage** | Embedded in conversation file | Persisted once, no re-computation on reload |
| **Message Storage** | All messages preserved | UI can display full history |
| **LLM Context** | Summary + recent messages | Efficient context window usage |
| **Summarization** | LLM-based sliding window | Best quality, acceptable cost |
| **Trigger** | 20 messages OR 8K tokens | Balance context vs cost |
| **Memory UX** | ChatGPT-style | Users familiar, proven model |

---

## Open Questions (Resolved)

| Question | Resolution | Reference |
|----------|------------|-----------|
| Conversation ID | Generate UUID on first save, preserve across sessions | data-model.md |
| Auto-save frequency | Debounced 2s after last change | data-model.md |
| Multiple conversations | One file per session + index.json | data-model.md |
| Summary storage | Embedded in conversation file (persisted) | data-model.md |
| Summary on reload | Use persisted summary, no re-computation | data-model.md |
| Memory extraction timing | On "New Conversation" action | T007 section |
| Session memory management | Load on switch, discard previous (no caching for MVP) | data-model.md Q6 |

---

## T011: Consolidated Findings & Recommendations

### Phase 1 Investigation Complete

All research, POC, and design tasks have been completed:

| Task | Status | Deliverable |
|------|--------|-------------|
| T001-T004 | ✅ Complete | Storage, model, summarization, industry research |
| T005 | ✅ Complete | PersistencePOC.swift - save/load cycle works |
| T006 | ✅ Complete | LifecyclePOC.swift - lifecycle hooks viable |
| T007 | ✅ Complete | Memory extraction prompts documented |
| T008-T009 | ✅ Complete | data-model.md with schemas and architecture |
| T010 | ✅ Complete | quickstart.md with testing instructions |

### Key Findings

1. **Storage**: JSON files in Application Support are sufficient for our scale (~1000 messages)
2. **Model**: Separate `PersistedConversation` struct avoids polluting `ChatConversation`
3. **Lifecycle**: `willTerminateNotification` is reliable; debounced saves handle force-quit
4. **Summarization**: LLM-based sliding window provides best quality at acceptable cost
5. **Memory**: End-of-conversation extraction is simplest and most effective

### Recommended Implementation Order

| Phase | User Stories | Priority | Complexity |
|-------|--------------|----------|------------|
| 2.1 | US1 + US2 (Session Continuity) | P1 | Medium |
| 2.2 | US3 (Summarization) | P2 | Medium |
| 2.3 | US4 (Cross-Session Memory) | P3 | High |

### Risk Assessment

| Risk | Mitigation |
|------|------------|
| Force-quit data loss | Debounced auto-save every 2s |
| Schema migration | Version field in all persisted types |
| Summary quality | Fall back to truncation on LLM failure |
| Memory bloat | Soft/hard limits with user warnings |

### Edge Cases Identified

| # | Scenario | Handling |
|---|----------|----------|
| E1 | Partial message on cancel | Already handled - partial content saved |
| E2 | Message retry removes history | Destructive - save after retry |
| E3 | Message trimming (>20 msgs) | Store ALL messages; trim only for LLM |
| E4 | Force-quit / crash | Debounced saves (2s) as recovery |
| E5 | Corrupted files | Log error, start fresh, optionally notify |
| E6 | Multiple windows | Last-write-wins (independent sessions) |
| E7 | Empty conversations | Don't persist empty conversations |
| E8 | Large messages (100KB+) | JSON handles fine, no special handling |
| E9 | Streaming chunks | Only persist final message, not chunks |
| E10 | System clock changes | Timestamps informational only |

See `data-model.md` Edge Cases section for detailed handling.

### Files Created

```
specs/007-memory-persistence/
├── spec.md           # Feature specification (4 user stories)
├── plan.md           # Two-phase implementation plan
├── tasks.md          # Phase 1 & 2 task breakdown
├── research.md       # All research findings (this file)
├── data-model.md     # Schema and architecture design
└── quickstart.md     # POC testing guide

Extremis/Tests/Core/
├── PersistencePOC.swift   # Save/load POC
└── LifecyclePOC.swift     # Lifecycle POC
```

---

## T012: Phase 1 Approval Request

### Summary

Phase 1 investigation is complete. All research, POC implementations, and design documents have been created.

**Ready for Phase 2 implementation upon your approval.**

### Phase 2 Scope (Pending Approval)

1. **US1 + US2 (P1)**: Implement `PersistenceService`, auto-save, restore on launch, "New Conversation" action
2. **US3 (P2)**: Implement `SummarizationManager`, integrate with conversation trimming
3. **US4 (P3)**: Implement `MemoryService`, memory extraction, preferences UI

### Approval Checklist

- [ ] Research findings are acceptable
- [ ] Data model design is approved
- [ ] Storage architecture is approved
- [ ] POC approach is validated
- [ ] Ready to proceed with Phase 2
