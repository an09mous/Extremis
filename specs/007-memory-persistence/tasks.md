# Tasks: Memory & Persistence

**Input**: Design documents from `/specs/007-memory-persistence/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Note**: This feature uses a two-phase approach per the implementation plan:
- **Phase 1**: Investigation, POC & Exploration (tasks below)
- **Phase 2**: Implementation (BLOCKED until Phase 1 approved)

## Format: `[ID] [P?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions

## Path Conventions

Per plan.md, this is a single macOS application:
- **Source**: `Extremis/` at repository root
- **Specs**: `specs/007-memory-persistence/`

---

## Phase 1: Investigation & POC

> **⚠️ IMPORTANT**: No production code changes until this phase is complete and approved.

**Purpose**: Research, proof-of-concept, and design validation before implementation.

**Deliverables**:
- `specs/007-memory-persistence/research.md`
- `specs/007-memory-persistence/data-model.md`
- `specs/007-memory-persistence/quickstart.md`

---

### 1.1 Research Tasks

- [x] T001 [P] Research macOS local storage options (JSON, Plist, SQLite, Core Data) and document findings in specs/007-memory-persistence/research.md
- [x] T002 [P] Analyze existing ChatConversation model in Extremis/Core/Models/ChatMessage.swift for Codable compatibility and document in specs/007-memory-persistence/research.md
- [x] T003 [P] Research context summarization strategies (LLM-based, extractive, sliding window, hierarchical) and document in specs/007-memory-persistence/research.md
- [x] T004 [P] Research industry alternatives (ChatGPT Memory, Claude.ai, Raycast AI, Cursor) and create comparison matrix in specs/007-memory-persistence/research.md

---

### 1.2 POC Tasks

- [x] T005 POC: Basic save/load cycle - prove ChatConversation can be serialized/deserialized in Extremis/Tests/Core/PersistencePOC.swift
- [x] T006 POC: App lifecycle integration - prove reliable save on quit using AppKit notifications in Extremis/Tests/Core/LifecyclePOC.swift
- [x] T007 POC: Cross-session memory extraction - test LLM fact extraction prompts and document results in specs/007-memory-persistence/research.md

---

### 1.3 Design Tasks

- [x] T008 Design data model schemas (PersistedConversation, ConversationSummary, UserMemory) in specs/007-memory-persistence/data-model.md
- [x] T009 Design storage architecture (file structure, naming, backup, pruning) in specs/007-memory-persistence/data-model.md
- [x] T010 Create quickstart guide with POC testing instructions in specs/007-memory-persistence/quickstart.md

---

### 1.4 Phase 1 Completion

- [x] T011 Consolidate all research findings into specs/007-memory-persistence/research.md with decision matrix and recommendations
- [x] T012 Present Phase 1 findings for user approval before proceeding to implementation

**Checkpoint**: Phase 1 complete - await user approval before Phase 2

---

## Phase 2: Implementation (BLOCKED)

> **⚠️ BLOCKED**: Do not start until Phase 1 is approved by user.

Phase 2 tasks will be generated after Phase 1 approval. High-level scope from plan.md:

### US1 & US2: Session Continuity + Fresh Session (P1)
- Implement `PersistenceService` in Extremis/Core/Services/PersistenceService.swift
- Extend `ChatConversation` for serialization in Extremis/Core/Models/ChatMessage.swift
- Implement `StorageManager` in Extremis/Utilities/StorageManager.swift
- Add app lifecycle hooks for auto-save in Extremis/App/AppDelegate.swift
- Add "New Conversation" UI action in Extremis/UI/PromptWindow/PromptWindowController.swift
- Add conversation restore on launch

### US3: Automatic Context Summarization (P2)
- Implement `SummarizationManager` in Extremis/Core/Services/SummarizationManager.swift
- Integrate with ChatConversation.trimIfNeeded()
- Add summarization trigger logic
- Store and restore summaries

### US4: Cross-Session Memory (P3)
- Implement `MemoryService` in Extremis/Core/Services/MemoryService.swift
- Create `UserMemory` model in Extremis/Core/Models/UserMemory.swift
- Add memory extraction logic
- Add memory viewing/clearing UI in Extremis/UI/Preferences/

---

## Dependencies & Execution Order

### Phase 1 Dependencies

```
T001 ─┐
T002 ─┼── All parallel (research)
T003 ─┤
T004 ─┘
      │
      ▼
T005 ─┐
T006 ─┼── Sequential (POCs depend on research)
T007 ─┘
      │
      ▼
T008 ─┐
T009 ─┼── Sequential (design depends on POC findings)
T010 ─┘
      │
      ▼
T011 ── Consolidation
      │
      ▼
T012 ── User Approval Gate
```

### Phase 2 Dependencies (after approval)

```
Phase 1 Complete + Approved
    │
    ├── US1 & US2: Session Continuity (P1) ─────┐
    │   (must complete before US3/US4)          │
    │                                           │
    ├── US3: Summarization (P2) ────────────────┤
    │   (depends on US1/US2 storage)            │
    │                                           │
    └── US4: Cross-Session Memory (P3) ─────────┘
        (depends on US1/US2 + US3)
```

---

## Parallel Opportunities

### Phase 1 Parallelization

```bash
# All research tasks can run in parallel:
T001: Research storage options
T002: Analyze ChatConversation model
T003: Research summarization strategies
T004: Research industry alternatives
```

---

## Implementation Strategy

### MVP First Approach

1. **Complete Phase 1**: All research, POCs, and design documents
2. **User Approval Gate**: Present findings, get approval
3. **Phase 2 MVP**: Implement US1 + US2 (Session Continuity + Fresh Session)
4. **Validate**: Test persistence works reliably
5. **Incremental**: Add US3 (Summarization), then US4 (Cross-Session Memory)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Phase 1: Research | T001-T004 | Ready |
| Phase 1: POC | T005-T007 | Ready |
| Phase 1: Design | T008-T010 | Ready |
| Phase 1: Approval | T011-T012 | Ready |
| Phase 2: US1+US2 | TBD | BLOCKED |
| Phase 2: US3 | TBD | BLOCKED |
| Phase 2: US4 | TBD | BLOCKED |

**Total Phase 1 Tasks**: 12
**Parallel Opportunities**: 4 (T001-T004)
