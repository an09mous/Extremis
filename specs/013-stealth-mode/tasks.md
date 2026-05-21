# Tasks: Stealth Mode

**Input**: Design documents from `/specs/013-stealth-mode/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Included — unit tests explicitly requested by user.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create new files and project structure for stealth mode

- [x] T001 [P] Create StealthStrategy protocol in Extremis/Core/Protocols/StealthStrategy.swift
- [x] T002 [P] Create StealthConfiguration (UserDefaults-backed settings) in Extremis/Core/Models/StealthConfiguration.swift
- [x] T003 [P] Extend HotkeyIdentifier enum with `.stealthToggle` (3) and `.preferences` (4) cases in Extremis/Core/Services/HotkeyManager.swift

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core StealthManager service that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement StealthManager singleton service in Extremis/Core/Services/StealthManager.swift — isStealthActive (@Published), managedWindows (NSHashTable), strategies array, registerWindow(), toggle(), activate(), deactivate(), applyCurrentState()
- [x] T005 Implement SharingTypeStrategy conformance in Extremis/Core/Protocols/StealthStrategy.swift — sets window.sharingType = .none on apply, .readWrite on remove
- [x] T006 Implement CollectionBehaviorStrategy conformance in Extremis/Core/Protocols/StealthStrategy.swift — sets stealth collectionBehavior on apply, caches and restores original on remove

**Checkpoint**: StealthManager can register windows and apply/remove stealth strategies. User story implementation can begin.

---

## Phase 3: User Story 1 — All UI Surfaces Invisible to Screen Capture (Priority: P1)

**Goal**: Every Extremis window and overlay is excluded from screen capture, screen sharing, and screen recording when stealth is active.

**Independent Test**: Enable stealth, start screen share, exercise every UI flow — verify none appear in shared feed.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T007 [P] [US1] Write unit tests for StealthManager state toggling (testStealthToggle, testActivateDeactivateCycle) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T008 [P] [US1] Write unit tests for window registration (testWindowRegistration — count-based) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T009 [P] [US1] Write unit tests for SharingTypeStrategy (testSharingTypeStrategy — apply/remove .none) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T010 [P] [US1] Write unit tests for CollectionBehaviorStrategy (testCollectionBehaviorStrategy — apply stealth behaviors) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T011 [P] [US1] Write unit test for strategy array application (testStrategyArrayApplication — all strategies applied to windows) in Extremis/Tests/Core/StealthManagerTests.swift

### Implementation for User Story 1

- [x] T012 [US1] Register PromptWindowController's NSPanel with StealthManager in configureWindow() in Extremis/UI/PromptWindow/PromptWindowController.swift
- [x] T013 [P] [US1] Register PreferencesWindowController's NSWindow with StealthManager in init() in Extremis/UI/Preferences/PreferencesWindow.swift
- [x] T014 [P] [US1] Register LoadingOverlayController's NSWindow with StealthManager in show() in Extremis/UI/Components/LoadingOverlayController.swift
- [x] T015 [US1] Register AppDelegate's API key dialog NSWindow with StealthManager in showAPIKeyDialogForProvider() in Extremis/App/AppDelegate.swift
- [x] T016 [US1] Add stealth indicator (small green dot) to PromptView toolbar area, conditionally rendered when StealthManager.shared.isStealthActive == true in Extremis/UI/PromptWindow/PromptView.swift
- [x] T017 [US1] Initialize StealthManager on app launch — read stealth_mode_enabled from UserDefaults and activate stealth BEFORE showing any UI in Extremis/App/AppDelegate.swift applicationDidFinishLaunching

**Checkpoint**: All existing Extremis windows are registered with StealthManager. When stealth is active, every UI surface is excluded from screen capture.

---

## Phase 4: User Story 2 — Hidden Menu Bar Icon (Priority: P2)

**Goal**: Menu bar icon is completely hidden when stealth mode is active, reappears when deactivated.

**Independent Test**: Toggle stealth on — verify menu bar icon disappears. Toggle off — verify it reappears.

### Implementation for User Story 2

- [x] T018 [US2] Add hideMenuBarIcon() method to AppDelegate — calls NSStatusBar.system.removeStatusItem() and sets statusItem = nil in Extremis/App/AppDelegate.swift
- [x] T019 [US2] Add showMenuBarIcon() method to AppDelegate — calls setupMenuBar() to re-create statusItem in Extremis/App/AppDelegate.swift
- [x] T020 [US2] Wire StealthManager.onMenuBarHide and onMenuBarShow callbacks to AppDelegate hide/show methods in Extremis/App/AppDelegate.swift applicationDidFinishLaunching
- [x] T021 [US2] Skip setupMenuBar() on app launch when stealth_mode_enabled is true in UserDefaults in Extremis/App/AppDelegate.swift

**Checkpoint**: Menu bar icon hides/shows within 200ms of stealth toggle. Icon never briefly flashes on launch when stealth is persisted.

---

## Phase 5: User Story 3 — Toggle Stealth Mode (Priority: P2)

**Goal**: Users can toggle stealth via a global hotkey (Option+Shift+S) and configure stealth settings in Preferences.

**Independent Test**: Press Option+Shift+S — verify stealth activates (toast shown, menu bar hidden, windows invisible). Press again — verify deactivation.

### Tests for User Story 3

- [x] T022 [P] [US3] Write unit tests for StealthConfiguration defaults and custom values (testStealthConfigurationDefaults, testStealthConfigurationCustomValues) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T023 [P] [US3] Write unit test for HotkeyIdentifier new cases (testHotkeyIdentifierCases — .stealthToggle, .preferences exist) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T024 [P] [US3] Write unit test for stealth persistence (testStealthPersistence — UserDefaults read/write) in Extremis/Tests/Core/StealthManagerTests.swift

### Implementation for User Story 3

- [x] T025 [US3] Create StealthToastController singleton in Extremis/UI/Components/StealthToastController.swift — borderless NSWindow, showToast(message:), auto-fade after 1s, registers with StealthManager
- [x] T026 [US3] Register stealth toggle hotkey (Option+Shift+S) and preferences hotkey (Option+Shift+,) in AppDelegate.setupHotkey() in Extremis/App/AppDelegate.swift
- [x] T027 [US3] Handle stealth toggle hotkey event — call StealthManager.shared.toggle() in AppDelegate hotkey handler in Extremis/App/AppDelegate.swift
- [x] T028 [US3] Handle preferences hotkey event — call PreferencesWindowController.shared.showWindow() in AppDelegate hotkey handler in Extremis/App/AppDelegate.swift
- [x] T029 [US3] Call StealthToastController.shared.showToast("Stealth On"/"Stealth Off") from StealthManager activate()/deactivate() in Extremis/Core/Services/StealthManager.swift
- [x] T030 [US3] Add "Stealth Mode" section to GeneralTab in Extremis/UI/Preferences/GeneralTab.swift — toggle switch, shortcut display, process disguise toggle, process name field, Test Stealth button, info text

**Checkpoint**: Stealth mode is togglable via hotkey and configurable in Preferences. Toast confirms state change.

---

## Phase 6: User Story 4 — Hidden from App Switcher and Mission Control (Priority: P3)

**Goal**: Extremis windows do not appear in Mission Control, Expose, or App Switcher when stealth is active.

**Independent Test**: Enable stealth, open Mission Control — verify Extremis window is not shown. Press Cmd+Tab — verify Extremis not listed.

### Implementation for User Story 4

- [x] T031 [US4] Verify CollectionBehaviorStrategy (T006) applies [.canJoinAllSpaces, .transient, .stationary, .fullScreenAuxiliary] — this should already handle Mission Control hiding. Add integration test if needed in Extremis/Tests/Core/StealthManagerTests.swift

**Checkpoint**: Extremis is hidden from Mission Control and Expose. (App Switcher hiding is inherent from LSUIElement.)

---

## Phase 7: User Story 5 — Obscured Process Identity (Priority: P3)

**Goal**: Process name is disguised in Activity Monitor when stealth is active.

**Independent Test**: Enable stealth, open Activity Monitor — verify process name is not "Extremis".

### Tests for User Story 5

- [x] T032 [P] [US5] Write unit test for process name disguise (testProcessNameDisguise — set and restore) in Extremis/Tests/Core/StealthManagerTests.swift

### Implementation for User Story 5

- [x] T033 [US5] Implement process name disguise in StealthManager — set ProcessInfo.processInfo.processName to configured disguise name on activate, restore originalProcessName on deactivate in Extremis/Core/Services/StealthManager.swift
- [x] T034 [US5] Read stealth_disguise_name and stealth_process_disguise from StealthConfiguration in StealthManager in Extremis/Core/Services/StealthManager.swift

**Checkpoint**: Process appears as "com.apple.hiservices-xpcservice" in Activity Monitor when stealth is active.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Verification, documentation, and cross-cutting improvements

- [x] T035 [P] Implement StealthVerifier utility — verify stealth via CGWindowListCreateImage in Extremis/Core/Services/StealthVerifier.swift
- [x] T036 [P] Wire "Test Stealth" button in GeneralTab to StealthVerifier.verify() — show green checkmark or yellow warning in Extremis/UI/Preferences/GeneralTab.swift
- [x] T037 [P] Add platform version detection — log macOS 15+ warning about ScreenCaptureKit limitations in StealthManager init in Extremis/Core/Services/StealthManager.swift
- [x] T038 [P] Write unit test for platform version detection (testPlatformVersionDetection) in Extremis/Tests/Core/StealthManagerTests.swift
- [x] T039 Add StealthManagerTests to test runner script in Extremis/scripts/run-tests.sh
- [x] T040 Run full test suite (./scripts/run-tests.sh) and verify zero regressions
- [x] T041 Update README.md with stealth mode feature documentation
- [x] T042 Update CLAUDE.md with stealth mode files, patterns, and key files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately. All 3 tasks are parallel.
- **Foundational (Phase 2)**: Depends on Phase 1 (T001, T002, T003). BLOCKS all user stories.
- **US1 (Phase 3)**: Depends on Phase 2. No dependencies on other stories.
- **US2 (Phase 4)**: Depends on Phase 2. No dependencies on other stories.
- **US3 (Phase 5)**: Depends on Phase 2 and US1 (needs windows registered). Depends on US2 (menu bar hide/show).
- **US4 (Phase 6)**: Depends on Phase 2. Verifies CollectionBehaviorStrategy from Phase 2.
- **US5 (Phase 7)**: Depends on Phase 2. Independent of other stories.
- **Polish (Phase 8)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — No dependencies on other stories
- **US2 (P2)**: Can start after Phase 2 — No dependencies on other stories
- **US3 (P2)**: Start after US1 and US2 — needs window registrations and menu bar methods
- **US4 (P3)**: Can start after Phase 2 — Mostly verification of Phase 2 work
- **US5 (P3)**: Can start after Phase 2 — Fully independent

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models/protocols before services
- Services before UI integration
- Core implementation before cross-cutting concerns

### Parallel Opportunities

- Phase 1: All 3 setup tasks (T001, T002, T003) can run in parallel
- Phase 3 tests: T007-T011 can all run in parallel (same file, independent test functions)
- Phase 3 implementation: T013 and T014 can run in parallel (different files)
- Phase 4 and Phase 6-7 can start in parallel after Phase 2 (independent stories)
- Phase 5 tests: T022-T024 can run in parallel
- Phase 8: T035-T038 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all tests together (same file, independent functions):
Task T007: "Write testStealthToggle, testActivateDeactivateCycle"
Task T008: "Write testWindowRegistration"
Task T009: "Write testSharingTypeStrategy"
Task T010: "Write testCollectionBehaviorStrategy"
Task T011: "Write testStrategyArrayApplication"

# Launch parallel window registrations (different files):
Task T013: "Register PreferencesWindow with StealthManager"
Task T014: "Register LoadingOverlayController with StealthManager"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (protocols, config, hotkey enum)
2. Complete Phase 2: Foundational (StealthManager + strategies)
3. Complete Phase 3: User Story 1 (window registrations + indicator)
4. **STOP and VALIDATE**: Test all UI surfaces are invisible to screen capture
5. This alone delivers the core stealth value

### Incremental Delivery

1. Setup + Foundational → StealthManager ready
2. Add US1 → Screen capture invisibility works → **MVP!**
3. Add US2 → Menu bar icon hidden → More discreet
4. Add US3 → Hotkey toggle + toast + Preferences UI → Full user control
5. Add US4 → Mission Control hiding → Defense-in-depth
6. Add US5 → Process disguise → Maximum stealth
7. Polish → Verifier, docs, tests → Production-ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Total tasks: 42
- Tasks per story: US1=11, US2=4, US3=9, US4=1, US5=3, Setup=3, Foundational=3, Polish=8
- All unit tests use the project's TestRunner pattern (standalone Swift files, not XCTest)
- New test file MUST be added to scripts/run-tests.sh (T039)
- StealthToastController's own window must also be registered with StealthManager
- All stealth logic is additive — existing behavior unchanged when stealth is off
