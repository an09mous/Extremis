# Tasks: New Session Indicator

**Input**: Design documents from `/specs/009-session-indicator/`
**Prerequisites**: plan.md (required), spec.md (required), data-model.md, quickstart.md, research.md

**Tests**: Not explicitly requested - manual QA checklist provided instead.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `Extremis/` at repository root
- UI components: `Extremis/UI/PromptWindow/`
- Core services: `Extremis/Core/Services/`

---

## Phase 1: Setup

**Purpose**: Project setup and feature branch initialization

- [x] T001 Create feature branch `009-session-indicator` from main
- [x] T002 Verify build passes with `cd Extremis && swift build`
- [x] T003 Verify all tests pass with `./scripts/run-tests.sh`

**Checkpoint**: Development environment ready

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that enables all user stories

**⚠️ CRITICAL**: All user stories depend on the NewSessionBadge component and ViewModel state

- [x] T004 Create Components directory `Extremis/UI/PromptWindow/Components/` if not exists
- [x] T005 Create `NewSessionBadge.swift` component in `Extremis/UI/PromptWindow/Components/NewSessionBadge.swift`
- [x] T006 Add `showNewSessionIndicator` @Published property to PromptViewModel in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T007 Add `indicatorDismissTimer` private property to PromptViewModel in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T008 Implement `showNewSessionBadge()` method in PromptViewModel in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T009 Implement `hideNewSessionBadge()` method in PromptViewModel in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T010 Update `reset()` method to clean up indicator timer in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T011 Update `deinit` to invalidate indicator timer in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T012 Integrate NewSessionBadge in PromptContainerView header in `Extremis/UI/PromptWindow/PromptWindowController.swift`

**Checkpoint**: Foundation ready - badge component exists and can be controlled via ViewModel state

---

## Phase 3: User Story 1 - Quick Mode Indicator (Priority: P1) 🎯 MVP

**Goal**: Users in Quick Mode see a "New Session" badge when a new session is created

**Independent Test**: Select text → Option+Space → submit instruction → verify badge appears and auto-dismisses

### Implementation for User Story 1

- [x] T013 [US1] Call `showNewSessionBadge()` in `ensureSession()` when creating new session in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T014 [US1] Call `hideNewSessionBadge()` at start of `generate()` method in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [ ] T015 [US1] Verify badge auto-dismisses after 2.5 seconds (manual test)
- [ ] T016 [US1] Verify badge disappears on user interaction before timer (manual test)

**Checkpoint**: User Story 1 complete - Quick Mode shows "New Session" badge

---

## Phase 4: User Story 2 - Chat Mode Indicator (Priority: P2)

**Goal**: Users in Chat Mode see a "New Session" badge when a new session is created

**Independent Test**: Option+Space (no selection) → verify badge appears immediately

### Implementation for User Story 2

- [x] T017 [US2] Verify badge appears for Chat Mode new sessions (uses same `ensureSession()` path as US1)
- [x] T018 [US2] Call `hideNewSessionBadge()` at start of `sendChatMessage()` method in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T019 [US2] Call `hideNewSessionBadge()` in `setRestoredSession()` to prevent showing for existing sessions in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [ ] T020 [US2] Verify NO badge appears when loading existing session from sidebar (manual test)

**Checkpoint**: User Story 2 complete - Chat Mode shows badge consistently

---

## Phase 5: User Story 3 - Session Transition Indicator (Priority: P3)

**Goal**: Users see badge when explicitly creating a new session via button

**Independent Test**: Have active session → click New Session button → verify badge appears

### Implementation for User Story 3

- [x] T021 [US3] Call `showNewSessionBadge()` in `startNewSession()` after session creation in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [ ] T022 [US3] Verify badge appears when clicking New Session button (manual test)
- [ ] T023 [US3] Verify previous session content is cleared when new session starts (manual test)

**Checkpoint**: User Story 3 complete - explicit New Session shows badge

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, accessibility, and final validation

- [ ] T024 Verify no layout shift when badge appears/disappears (manual test)
- [ ] T025 Verify smooth animations on entry and exit (manual test)
- [ ] T026 [P] Test with VoiceOver enabled - verify "New session started" is announced
- [ ] T027 [P] Test with Reduce Motion enabled - verify simple fade animation
- [ ] T028 Test rapid session switching - verify no flickering or stacked badges
- [x] T029 Build and run all existing tests with `./scripts/run-tests.sh`
- [ ] T030 Run quickstart.md manual QA checklist validation
- [ ] T031 Commit all changes with descriptive message

**Checkpoint**: Feature complete and validated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can proceed sequentially (P1 → P2 → P3)
  - Most logic is shared, so sequential is recommended
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Phase 2 - Shares foundational code with US1, minor additions
- **User Story 3 (P3)**: Can start after Phase 2 - Uses same badge, different trigger point

### Within Each User Story

- Core implementation tasks before manual verification
- All implementation in same file (`PromptWindowController.swift`) - sequential recommended
- Story complete before moving to next priority

### Parallel Opportunities

- T026 and T027 (accessibility tests) can run in parallel
- Most other tasks are sequential due to shared file modifications

---

## Parallel Example: Foundational Phase

```bash
# These tasks modify different sections of the same file, so run sequentially:
# T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012

# However, T005 (new file) can be done in parallel with T006-T011:
# Developer A: T005 (NewSessionBadge.swift)
# Developer B: T006-T011 (PromptWindowController.swift modifications)
# Then: T012 (integration - depends on both)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - creates badge component)
3. Complete Phase 3: User Story 1 (Quick Mode)
4. **STOP and VALIDATE**: Test Quick Mode badge independently
5. Deploy/demo if ready - core problem is solved

### Incremental Delivery

1. Complete Setup + Foundational → Badge component ready
2. Add User Story 1 → Test Quick Mode → **MVP Complete!**
3. Add User Story 2 → Test Chat Mode → More consistent UX
4. Add User Story 3 → Test explicit new session → Power user feature
5. Polish → Accessibility, edge cases → Production ready

### File Summary

| File | Changes |
|------|---------|
| `Extremis/UI/PromptWindow/Components/NewSessionBadge.swift` | **NEW** - Badge SwiftUI component |
| `Extremis/UI/PromptWindow/PromptWindowController.swift` | Add state, methods, triggers, integration |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Manual QA replaces automated tests for this UI feature
- Commit after each phase or logical group
- Stop at any checkpoint to validate story independently
