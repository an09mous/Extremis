# Tasks: Stealth Chat Isolation

**Input**: Design documents from `/specs/016-stealth-chat-isolation/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Included — user requested unit tests for all applicable changes.

**Organization**: Tasks grouped by user story. US1+US2 are combined (both P1, share filtering logic). US4 (persistence) is covered by foundational data model tasks — no separate phase needed.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Foundational (Data Model)

**Purpose**: Add `isStealth` boolean to all session models and storage. Purely additive, no behavior change. All existing tests must still pass after this phase.

- [X] T001 [P] Add `isStealth: Bool` property to `ChatSession` init (default `false`, immutable `let`) in `Extremis/Core/Models/ChatSession.swift`
- [X] T002 [P] Add `isStealth: Bool` field to `PersistedSession` with backward-compatible Codable decoding (`decodeIfPresent` defaulting to `false`) in `Extremis/Core/Models/Persistence/PersistedSession.swift`
- [X] T003 [P] Add `isStealth: Bool` field to `SessionIndexEntry` with backward-compatible Codable decoding (`decodeIfPresent` defaulting to `false`) in `Extremis/Core/Models/Persistence/SessionIndex.swift`
- [X] T004 Pass `isStealth` through `PersistedSession.from(_:)` conversion (read from `ChatSession.isStealth`) and `toSession()` restoration in `Extremis/Core/Models/Persistence/PersistedSession.swift`
- [X] T005 Pass `isStealth` through index entry creation in `JSONSessionStorage.saveSession()` — when creating/updating `SessionIndexEntry`, copy `isStealth` from the `PersistedSession` in `Extremis/Core/Services/JSONSessionStorage.swift`
- [X] T006 Run existing test suite (`./scripts/run-tests.sh`) and verify zero regressions — all existing tests must pass with the new fields defaulting to `false`

**Checkpoint**: Data model complete. `isStealth` flows through create → persist → index → restore. No behavior change yet.

---

## Phase 2: User Stories 1 & 2 — Session Tagging, Filtering, and Auto-Switch (Priority: P1) MVP

**Goal**: New sessions created in stealth mode are tagged `isStealth: true`. Sidebar hides stealth sessions in normal mode and shows all sessions in stealth mode. Active session auto-switches away from stealth on stealth disable. Quick Mode disabled in stealth.

**Independent Test**: Enable stealth → create conversation → disable stealth → conversation disappears from sidebar. Re-enable stealth → conversation reappears.

### Tests for US1+US2

- [X] T007 [P] [US1] Create `Extremis/Tests/Core/StealthSessionTaggingTests.swift` — test `ChatSession` creation with `isStealth: true/false`, test `PersistedSession` encode/decode round-trip preserves `isStealth`, test backward compat (JSON without `isStealth` field decodes as `false`), test `SessionIndexEntry` backward compat same way
- [X] T008 [P] [US1] Create `Extremis/Tests/Core/StealthSessionFilteringTests.swift` — test pure filtering function: stealth active returns all sessions, stealth inactive excludes `isStealth` entries, empty list when all stealth + stealth off, mixed sessions preserve sort order
- [X] T009 [P] [US1] Create `Extremis/Tests/Core/StealthAutoSwitchTests.swift` — test auto-switch logic: stealth disable with active stealth session returns most recent normal session ID, stealth disable with active normal session returns nil (no switch), stealth disable with no normal sessions returns nil (clear), stealth enable returns nil (no switch)
- [X] T010 Add all three new test files to `Extremis/scripts/run-tests.sh` and verify they compile and run

### Implementation for US1+US2

- [X] T011 [US1] In `SessionManager.startNewSession()`, set `isStealth: StealthManager.shared.isStealthActive` when creating the new `ChatSession` in `Extremis/Core/Services/SessionManager.swift`
- [X] T012 [US1] In `SessionListView`, add `@ObservedObject var stealthManager = StealthManager.shared` and filter `sessions` array: if stealth inactive, exclude entries where `isStealth == true`. Add `onChange(of: stealthManager.isStealthActive)` to trigger session list reload in `Extremis/UI/PromptWindow/SessionListView.swift`
- [X] T013 [US1] In `SessionManager`, add Combine subscription to `StealthManager.shared.$isStealthActive` (with `.dropFirst()`) — on stealth deactivation, call new `handleStealthDeactivation()` method. This method: checks if `currentSession?.isStealth == true`, if so loads most recent normal session from storage (or sets `currentSession = nil`), increments `sessionListVersion` in `Extremis/Core/Services/SessionManager.swift`
- [X] T014 [US1] In `AppDelegate.captureContextAndShowPrompt()`, extend the existing stealth check (line ~673) to fully no-op the Quick Mode path: when stealth is active and a selection was detected, discard the selection and proceed as Chat Mode (no selection) instead. Verify Magic Mode guard already exists at `handleMagicModeActivation()` line ~610 in `Extremis/App/AppDelegate.swift`
- [X] T015 [US1] Run full test suite (`./scripts/run-tests.sh`) — all tests (existing + new) must pass

**Checkpoint**: US1+US2 MVP complete. Stealth sessions are tagged, hidden in normal mode, visible in stealth mode. Auto-switch works. Quick Mode disabled in stealth.

---

## Phase 3: User Story 3 — Stealth Visual Indicator (Priority: P2)

**Goal**: Stealth sessions show a subtle lock/shield icon in the sidebar when stealth mode is active, helping users distinguish protected sessions from normal ones.

**Independent Test**: Enable stealth with a mix of stealth and normal sessions → stealth sessions show icon, normal sessions don't.

### Implementation for US3

- [X] T016 [US3] In `SessionRowView` within `SessionListView`, add a stealth indicator: when `entry.isStealth` is true and stealth mode is active, show SF Symbol `lock.shield.fill` (size ~10pt, color `DS.Colors.textSecondary`) next to the session title. Pass `isStealthActive` state to the row view in `Extremis/UI/PromptWindow/SessionListView.swift`
- [X] T017 [US3] Verify the indicator does NOT appear in normal mode (stealth sessions are hidden entirely, so this is automatic) — manual QA check

**Checkpoint**: Visual indicator complete. Stealth sessions are visually distinguishable in stealth mode.

---

## Phase 4: User Story 4 — Persistence Verification (Priority: P2)

**Goal**: Verify stealth session isolation persists across app restarts — stealth sessions stay hidden after relaunch in normal mode.

**Note**: The data model work in Phase 1 (T002, T003, T004, T005) already ensures persistence. This phase is verification only.

- [X] T018 [US4] Verify persistence round-trip: create a stealth session, save it, reload from disk, confirm `isStealth == true` is preserved in index and session file. This is covered by T007 tests — verify those tests pass
- [X] T019 [US4] Manual QA: create stealth session → quit app → relaunch in normal mode → verify stealth session hidden → enable stealth → verify session reappears with all messages intact

**Checkpoint**: Persistence verified. Stealth isolation survives app lifecycle.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final validation, cleanup

- [X] T020 Update `Extremis/docs/` and feature documentation to describe stealth chat isolation behavior, session tagging, and hotkey restrictions in stealth mode
- [X] T021 Run full test suite one final time (`./scripts/run-tests.sh`) and verify all tests pass (existing + new stealth tests)
- [X] T022 Manual QA: exercise all edge cases from spec — rapid stealth toggle, active stealth session on disable, all-stealth-sessions empty state, background generation on hidden stealth session, Quick Mode no-op in stealth

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — start immediately
- **Phase 2 (US1+US2)**: Depends on Phase 1 completion
- **Phase 3 (US3)**: Depends on Phase 2 (needs filtering in place to test indicator visibility)
- **Phase 4 (US4)**: Depends on Phase 1 (data model) — can run in parallel with Phase 2/3
- **Phase 5 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US1+US2 (P1)**: Depends on foundational data model — core MVP, must complete first
- **US3 (P2)**: Depends on US1+US2 (needs sidebar filtering to show mixed sessions in stealth)
- **US4 (P2)**: Independent of US1+US2 at the data level, but verification is most meaningful after filtering works

### Parallel Opportunities

Within Phase 1:
- T001, T002, T003 can run in parallel (different files)

Within Phase 2 tests:
- T007, T008, T009 can run in parallel (different test files)

Phase 4 can overlap with Phase 3 (different concerns).

---

## Parallel Example: Phase 1

```bash
# Launch all model changes in parallel (different files):
Task: "Add isStealth to ChatSession in Extremis/Core/Models/ChatSession.swift"
Task: "Add isStealth to PersistedSession in Extremis/Core/Models/Persistence/PersistedSession.swift"
Task: "Add isStealth to SessionIndexEntry in Extremis/Core/Models/Persistence/SessionIndex.swift"
```

## Parallel Example: Phase 2 Tests

```bash
# Launch all test file creation in parallel:
Task: "Create StealthSessionTaggingTests.swift in Extremis/Tests/Core/"
Task: "Create StealthSessionFilteringTests.swift in Extremis/Tests/Core/"
Task: "Create StealthAutoSwitchTests.swift in Extremis/Tests/Core/"
```

---

## Implementation Strategy

### MVP First (US1+US2 Only)

1. Complete Phase 1: Data model changes (T001-T006)
2. Complete Phase 2: Tagging + filtering + auto-switch + tests (T007-T015)
3. **STOP and VALIDATE**: Test stealth isolation end-to-end
4. This alone delivers the core value — stealth sessions hidden in normal mode

### Incremental Delivery

1. Phase 1 → Data model ready
2. Phase 2 → US1+US2 MVP → Test independently (core isolation works)
3. Phase 3 → US3 visual indicator → Test independently (stealth sessions distinguishable)
4. Phase 4 → US4 persistence verified → Test independently (survives restarts)
5. Phase 5 → Polish, docs, final QA

---

## Notes

- All changes are additive — existing sessions default to `isStealth: false`
- Backward compatibility is critical — test explicitly with JSON lacking `isStealth` field
- US1+US2 are combined because filtering logic is a single `if/else` that satisfies both
- US4 persistence is inherently covered by the Codable changes in Phase 1
- Total: 22 tasks across 5 phases
