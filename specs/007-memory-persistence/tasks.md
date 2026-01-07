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

## Phase 2: Implementation (APPROVED)

> **✅ APPROVED**: Phase 1 approved by user on 2026-01-06. Proceeding with implementation.

---

### 2.1 Core Models (P1)

- [x] T013 [P] Create PersistedMessage model in Extremis/Core/Models/Persistence/PersistedMessage.swift
- [x] T014 [P] Create ConversationSummary model in Extremis/Core/Models/Persistence/ConversationSummary.swift
- [x] T015 Create PersistedConversation model in Extremis/Core/Models/Persistence/PersistedConversation.swift (depends on T013, T014)
- [x] T016 [P] Create ConversationIndexEntry model in Extremis/Core/Models/Persistence/ConversationIndex.swift
- [x] T017 Create ConversationIndex model in Extremis/Core/Models/Persistence/ConversationIndex.swift (depends on T016)
- [x] T018 [P] Create StorageError enum in Extremis/Core/Models/Persistence/StorageError.swift

---

### 2.2 Storage Layer (P1)

- [x] T019 Implement StorageManager actor in Extremis/Core/Services/StorageManager.swift (depends on T015, T017, T018)

---

### 2.3 Conversation Management (P1)

- [x] T020 Implement ConversationManager with debounced save in Extremis/Core/Services/ConversationManager.swift (depends on T019)

---

### 2.4 App Integration (P1)

- [x] T021 Add lifecycle hooks to AppDelegate for save on terminate in Extremis/App/AppDelegate.swift (depends on T020)
- [x] T022 Add conversation restore on launch in Extremis/App/AppDelegate.swift (depends on T020)
- [x] T023 Integrate ConversationManager with PromptViewModel in Extremis/UI/PromptWindow/PromptViewModel.swift (depends on T020)
- [x] T024 Add "New Conversation" menu item and keyboard shortcut (depends on T023)

---

### 2.5 Validation (P1)

- [ ] T025 Test save/load cycle with real app usage
- [ ] T026 Test force-quit recovery (debounced saves work)
- [ ] T027 Test New Conversation action clears and persists correctly

---

### 2.6 US3: Summarization (P2) - FUTURE

> **⚠️ DEFERRED**: Complete US1+US2 first, then implement summarization.

- [ ] T028 Implement SummarizationManager in Extremis/Core/Services/SummarizationManager.swift
- [ ] T029 Add summarization trigger logic (20 messages OR 8K tokens)
- [ ] T030 Integrate with PersistedConversation.summary field
- [ ] T031 Test summarization preserves key context

---

### 2.7 US4: Cross-Session Memory (P3) - FUTURE

> **⚠️ DEFERRED**: Complete US1+US2+US3 first, then implement cross-session memory.

- [ ] T032 Create UserMemory model in Extremis/Core/Models/Persistence/UserMemory.swift
- [ ] T033 Create UserMemoryStore model in Extremis/Core/Models/Persistence/UserMemory.swift
- [ ] T034 Implement MemoryService in Extremis/Core/Services/MemoryService.swift
- [ ] T035 Add memory extraction on New Conversation action
- [ ] T036 Add memory injection in system prompt
- [ ] T037 Add memory viewing/clearing UI in Extremis/UI/Preferences/

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
| Phase 1: Research | T001-T004 | ✅ Complete |
| Phase 1: POC | T005-T007 | ✅ Complete |
| Phase 1: Design | T008-T010 | ✅ Complete |
| Phase 1: Approval | T011-T012 | ✅ Complete |
| Phase 2: Core Models | T013-T018 | ✅ Complete |
| Phase 2: Storage | T019 | ✅ Complete |
| Phase 2: Conversation Mgmt | T020 | ✅ Complete |
| Phase 2: App Integration | T021-T024 | ✅ Complete |
| Phase 2: Validation | T025-T027 | 🔄 In Progress |
| Phase 2: US3 (Summarization) | T028-T031 | ⏸️ Deferred |
| Phase 2: US4 (Memory) | T032-T037 | ⏸️ Deferred |

**Total Phase 1 Tasks**: 12 (Complete)
**Total Phase 2 US1+US2 Tasks**: 15 (T013-T027)
**Parallel Opportunities**: T013, T014, T016, T018 can run in parallel
