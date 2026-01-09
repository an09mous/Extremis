# Implementation Plan: Memory & Persistence

**Branch**: `007-memory-persistence` | **Date**: 2026-01-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-memory-persistence/spec.md`

## Summary

Build memory and persistence capabilities for Extremis to preserve conversation state across app launches, automatically summarize long conversations to manage context limits, and maintain cross-session user memories. This plan is divided into two phases: **Phase 1 (Investigation & POC)** for research and validation, and **Phase 2 (Implementation)** for production code.

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency
**Primary Dependencies**: SwiftUI, AppKit, Foundation (Codable for serialization)
**Storage**: Local file system (Application Support directory) - JSON or Property List format
**Testing**: XCTest (existing test infrastructure)
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS application
**Performance Goals**: <2s conversation restore, <100ms save operation
**Constraints**: <10MB storage for typical usage, offline-capable, no external dependencies
**Scale/Scope**: Single user, ~100 conversations, ~1000 messages

## Constitution Check

*GATE: Must pass before Phase 1 research. Re-check after Phase 2 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity | ✅ PASS | Persistence layer will be a separate service, not coupled to UI |
| II. Code Quality | ✅ PASS | Will follow Swift conventions, use Codable protocols |
| III. Extensibility | ✅ PASS | Storage protocol allows future backends (iCloud, etc.) |
| IV. UX Excellence | ✅ PASS | <2s restore, background saves, no blocking operations |
| V. Documentation | ✅ PASS | Will update README with persistence behavior |
| VI. Testing | ✅ PASS | Unit tests for serialization, integration tests for persistence |
| VII. Regression Prevention | ✅ PASS | Phase 1 POC validates approach before touching production code |

## Project Structure

### Documentation (this feature)

```text
specs/007-memory-persistence/
├── plan.md              # This file
├── research.md          # Phase 1 output - investigation findings
├── data-model.md        # Phase 1 output - entity designs
├── quickstart.md        # Phase 1 output - testing guide
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   ├── ChatMessage.swift      # Existing - extend for Codable persistence
│   │   └── UserMemory.swift       # New - cross-session memory entity
│   └── Services/
│       ├── PersistenceService.swift    # New - save/load conversations
│       ├── SummarizationManager.swift  # New - context compression
│       └── MemoryService.swift         # New - cross-session facts (P3)
├── Utilities/
│   └── StorageManager.swift       # New - file system abstraction
└── UI/
    └── PromptWindow/
        └── PromptWindowController.swift  # Modify - integrate persistence
```

**Structure Decision**: Single macOS app structure. New services follow existing patterns in `Core/Services/`. Storage abstraction in `Utilities/` follows existing helpers pattern.

---

# PHASE 1: Investigation, POC & Exploration

> **⚠️ IMPORTANT**: No production code changes until Phase 1 is complete and approved.

## Phase 1 Objectives

1. **Investigate** existing persistence patterns in macOS/Swift ecosystem
2. **POC** the core technical challenges before committing to implementation
3. **Explore** how similar tools (ChatGPT, Claude, Raycast AI) handle memory
4. **Validate** assumptions from spec against real-world constraints
5. **Document** findings and recommended approach

## Phase 1 Tasks

### 1.1 Research: macOS Local Storage Options

**Goal**: Determine best storage mechanism for conversation data.

**Options to evaluate**:
| Option | Pros | Cons | Investigate |
|--------|------|------|-------------|
| JSON files | Simple, human-readable, debuggable | Manual file management | ✅ |
| Property Lists | Native macOS, type-safe | Less flexible schema | ✅ |
| SQLite/GRDB | Efficient queries, migrations | Added dependency, overkill? | ✅ |
| Core Data | Apple-native, migration support | Complex for simple data | ✅ |
| UserDefaults | Simplest | Size limits, not for large data | ❌ |

**Deliverable**: Decision matrix in `research.md` with recommendation

### 1.2 Research: Existing ChatConversation Model

**Goal**: Understand current model limitations and extension points.

**Questions to answer**:
- Is `ChatConversation` already `Codable`? Can it be made `Codable`?
- What data is stored vs. computed?
- How does `originalContext` work - can it be serialized?
- What happens to `@Published` properties during encoding?

**Deliverable**: Analysis in `research.md` with code snippets

### 1.3 POC: Basic Save/Load Cycle

**Goal**: Prove we can serialize and deserialize a conversation.

**POC scope**:
```swift
// Pseudocode for POC
let conversation = ChatConversation(...)
conversation.addUserMessage("Hello")
conversation.addAssistantMessage("Hi there!")

// Save
let data = try JSONEncoder().encode(conversation)
FileManager.default.createFile(at: path, contents: data)

// Load
let loadedData = FileManager.default.contents(atPath: path)
let restored = try JSONDecoder().decode(ChatConversation.self, from: loadedData)

// Verify
assert(restored.messages.count == 2)
```

**Deliverable**: Working POC code (can be in a test file or playground)

### 1.4 POC: App Lifecycle Integration

**Goal**: Prove we can hook into app termination/launch reliably.

**Questions to answer**:
- Which AppKit notifications to observe? (`NSApplication.willTerminateNotification`?)
- Does `applicationWillTerminate` give enough time to save?
- How to handle force-quit scenarios?
- Should we save on every message or debounce?

**Deliverable**: POC demonstrating reliable save on quit

### 1.5 Research: Context Summarization Strategies

**Goal**: Determine best approach for summarizing long conversations.

**Options to evaluate**:
| Strategy | Description | Investigate |
|----------|-------------|-------------|
| LLM-based | Use same LLM to summarize older messages | ✅ |
| Extractive | Pull key sentences without LLM | ✅ |
| Sliding window | Keep N recent + summary of older | ✅ |
| Hierarchical | Summaries of summaries | ✅ |

**Key questions**:
- What prompt produces best summaries?
- How to preserve key facts vs. conversation flow?
- When to trigger summarization (message count? token estimate?)
- How to handle summarization failure?

**Deliverable**: Comparison in `research.md` with recommended approach

### 1.6 Research: Industry Alternatives

**Goal**: Learn from existing AI assistants with memory features.

**Products to study**:
| Product | Memory Features | Notes |
|---------|-----------------|-------|
| ChatGPT | Memory, custom instructions | How does "Memory" work? |
| Claude.ai | Project knowledge, no persistent memory | Different approach |
| Raycast AI | Conversation history, no cross-session | Similar scope to P1 |
| GitHub Copilot Chat | Per-workspace context | Limited persistence |
| Cursor | Codebase context, chat history | Developer-focused |

**Deliverable**: Feature comparison matrix and insights

### 1.7 POC: Cross-Session Memory Extraction (P3)

**Goal**: Validate whether LLM can reliably extract facts from conversation.

**POC scope**:
```
Given conversation:
User: "I prefer TypeScript over JavaScript"
User: "My timezone is PST"
User: "I work on a Mac with M1 chip"

Extract as structured facts:
- preference: TypeScript > JavaScript
- timezone: PST
- hardware: Mac M1
```

**Questions to answer**:
- What prompt reliably extracts facts?
- How to categorize facts (preferences, personal info, technical)?
- How to avoid hallucinated facts?
- How to deduplicate/update existing facts?

**Deliverable**: POC with sample prompts and results

### 1.8 Design: Data Model

**Goal**: Finalize entity schemas based on research.

**Deliverable**: `data-model.md` with:
- `PersistedConversation` schema
- `ConversationSummary` schema
- `UserMemory` schema
- Migration strategy for schema changes

### 1.9 Design: Storage Architecture

**Goal**: Define how and where data is stored.

**Deliverable**: Architecture diagram and decisions:
- File structure in Application Support
- Naming conventions
- Backup/recovery approach
- Size management (pruning old conversations)

### 1.10 Create Quickstart Guide

**Goal**: Document how to test the POCs and validate assumptions.

**Deliverable**: `quickstart.md` with:
- How to run POC code
- Expected behavior
- Manual test scenarios
- Success criteria

## Phase 1 Exit Criteria

Before proceeding to Phase 2, the following must be complete:

- [ ] `research.md` documents all investigation findings
- [ ] `data-model.md` defines all entity schemas
- [ ] `quickstart.md` provides testing instructions
- [ ] All POCs demonstrate feasibility
- [ ] **User approval** of recommended approach

---

# PHASE 2: Implementation

> **⚠️ BLOCKED**: Do not start until Phase 1 is approved.

## Phase 2 Overview

Phase 2 will be planned in detail via `/speckit.tasks` after Phase 1 approval. High-level scope:

### P1 Features (Session Continuity)
- Implement `PersistenceService` based on Phase 1 findings
- Extend `ChatConversation` for serialization
- Add app lifecycle hooks for auto-save
- Add "New Conversation" UI action
- Add conversation restore on launch

### P2 Features (Context Summarization)
- Implement `SummarizationManager` using chosen strategy
- Integrate with `ChatConversation.trimIfNeeded()`
- Add summarization trigger logic
- Store and restore summaries

### P3 Features (Cross-Session Memory)
- Implement `MemoryService` and `UserMemory` model
- Add memory extraction logic
- Add memory viewing UI
- Add memory clearing option

## Phase 2 Dependencies

```
Phase 1 Complete
    │
    ├── P1: Session Continuity ─────┐
    │                               │
    ├── P2: Summarization ──────────┼── P3: Cross-Session Memory
    │   (depends on P1 storage)     │   (depends on P1 + P2)
    │                               │
    └───────────────────────────────┘
```

---

## Complexity Tracking

> No constitution violations identified. All approaches favor simplicity.

| Decision | Simpler Alternative | Why Chosen Approach |
|----------|---------------------|---------------------|
| JSON files over SQLite | In-memory only | JSON is simpler than SQLite, sufficient for ~1000 messages |
| Single file per conversation | One big file | Allows independent loading, easier debugging |
| LLM summarization over extractive | No summarization | LLM produces more coherent summaries, worth the cost |

---

## Next Steps

1. **Start Phase 1 tasks** (investigation and POCs)
2. Complete `research.md` with findings
3. Complete `data-model.md` with schemas
4. Complete `quickstart.md` with test guide
5. **Present findings for approval**
6. Upon approval, run `/speckit.tasks` to generate Phase 2 implementation tasks
