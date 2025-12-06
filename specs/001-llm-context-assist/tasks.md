# Tasks: Extremis - Context-Aware LLM Writing Assistant

**Input**: Design documents from `/specs/001-llm-context-assist/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓, quickstart.md ✓

**Tests**: Tests are NOT included by default. Add test tasks only if explicitly requested.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md project structure:
- **App code**: `Extremis/` at repository root
- **Tests**: `Tests/` at repository root

---

## Phase 1: Setup (Shared Infrastructure) ✅

**Purpose**: Project initialization and basic structure

- [x] T001 Create Xcode project "Extremis" as macOS App with SwiftUI, configure Bundle ID
- [x] T002 [P] Configure Info.plist with LSUIElement=true (menu bar app), privacy descriptions
- [x] T003 [P] Create Extremis.entitlements with automation and keychain access
- [x] T004 Create folder structure: App/, Core/, Extractors/, LLMProviders/, UI/, Utilities/, Resources/
- [x] T005 [P] Create Core/Models/ folder and placeholder files
- [x] T006 [P] Create Core/Protocols/ folder and placeholder files
- [x] T007 [P] Create Core/Services/ folder and placeholder files
- [x] T008 Setup Tests/ExtremisTests/ and Tests/ExtremisUITests/ targets

**Checkpoint**: ✅ Project compiles and runs (shows empty menu bar icon)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T009 Implement data models in Extremis/Core/Models/Context.swift (Context, ContextSource, ContextMetadata)
- [x] T010 [P] Implement data models in Extremis/Core/Models/Instruction.swift
- [x] T011 [P] Implement data models in Extremis/Core/Models/Generation.swift (Generation, TokenUsage, LLMProviderType)
- [x] T012 [P] Implement data models in Extremis/Core/Models/Preferences.swift (Preferences, HotkeyConfiguration, AppearanceSettings)
- [x] T013 Implement ContextExtractor protocol in Extremis/Core/Protocols/ContextExtractor.swift
- [x] T014 [P] Implement LLMProvider protocol in Extremis/Core/Protocols/LLMProvider.swift
- [x] T015 [P] Implement TextInserter protocol in Extremis/Core/Protocols/TextInserter.swift
- [x] T016 Implement typed errors (in protocol files: ContextExtractionError, LLMProviderError, TextInsertionError, PreferencesError)
- [x] T017 Implement KeychainHelper utility in Extremis/Utilities/KeychainHelper.swift
- [x] T018 [P] Implement ClipboardManager utility in Extremis/Utilities/ClipboardManager.swift
- [x] T019 [P] Implement AccessibilityHelpers utility in Extremis/Utilities/AccessibilityHelpers.swift
- [x] T020 Implement PermissionManager service in Extremis/Core/Services/PermissionManager.swift
- [x] T021 Implement PreferencesManager service in Extremis/Utilities/UserDefaultsHelper.swift (UserDefaults + Keychain)

**Checkpoint**: ✅ Foundation ready - all models, protocols, and core utilities in place

---

## Phase 3: User Story 1 - Basic Hotkey Activation & Text Completion (Priority: P1) 🎯 MVP

**Goal**: User presses hotkey → prompt window appears → types instruction → AI generates → text inserted

**Independent Test**: Press hotkey in TextEdit, type "write a greeting", see text appear at cursor

### Implementation for User Story 1

- [x] T022 [US1] Implement HotkeyManager with Carbon APIs in Extremis/Core/Services/HotkeyManager.swift
- [x] T023 [US1] Implement PromptWindowController (NSPanel) in Extremis/UI/PromptWindow/PromptWindowController.swift
- [x] T024 [US1] Implement PromptView (SwiftUI input) in Extremis/UI/PromptWindow/PromptView.swift
- [x] T025 [US1] Implement ResponseView (SwiftUI output) in Extremis/UI/PromptWindow/ResponseView.swift
- [x] T026 [US1] Implement LoadingIndicator component in Extremis/UI/Components/LoadingIndicator.swift
- [x] T027 [US1] Implement LLMProviderRegistry in Extremis/LLMProviders/ProviderRegistry.swift
- [x] T028 [US1] Implement OpenAIProvider in Extremis/LLMProviders/OpenAIProvider.swift
- [x] T029 [P] [US1] Implement AnthropicProvider in Extremis/LLMProviders/AnthropicProvider.swift
- [x] T030 [P] [US1] Implement GeminiProvider in Extremis/LLMProviders/GeminiProvider.swift
- [x] T031 [US1] Implement basic TextInserter (clipboard-based) in Extremis/Core/Services/TextInserterService.swift
- [x] T032 [US1] Implement ExtremisApp entry point with menu bar in Extremis/App/ExtremisApp.swift
- [x] T033 [US1] Implement AppDelegate with lifecycle/permissions in Extremis/App/AppDelegate.swift
- [x] T034 [US1] Wire hotkey → window → LLM → insert flow in AppDelegate
- [x] T035 [US1] Add keyboard navigation (Enter submit, Escape cancel, Tab navigate)

**Checkpoint**: ✅ MVP complete - can activate hotkey, enter instruction, get AI response, insert text

---

## Phase 4: User Story 6 - Generic Text Field Support (Priority: P2) ✅

**Goal**: Fallback context extraction works in any app using Accessibility APIs

**Independent Test**: Activate in Notes app with text selected, ask "improve this", get contextual response

### Implementation for User Story 6

- [x] T036 [US6] Implement GenericExtractor in Extremis/Extractors/GenericExtractor.swift
- [x] T037 [US6] Implement ExtractorRegistry in Extremis/Extractors/ExtractorRegistry.swift
- [x] T038 [US6] Implement ContextOrchestrator in Extremis/Core/Services/ContextOrchestrator.swift
- [x] T039 [US6] Integrate ContextOrchestrator into prompt flow (replace basic context)
- [x] T040 [US6] Handle edge case: no text field detected (show message, allow freeform)
- [x] T041 [US6] Handle edge case: very long context (intelligent truncation)

**Checkpoint**: ✅ Generic extraction works in any macOS app with graceful fallbacks

---

## Phase 5: User Story 2 - Slack Context Awareness (Priority: P2) ✅

**Goal**: When activated in Slack, capture channel/DM info, participants, recent messages

**Independent Test**: Open Slack DM, activate Extremis, ask "summarize discussion" - should reference actual messages

### Implementation for User Story 2

- [x] T042 [US2] Implement SlackMetadata model additions in Extremis/Core/Models/Context.swift
- [x] T043 [US2] Implement BrowserBridge utility for AppleScript/JS execution in Extremis/Utilities/BrowserBridge.swift
- [x] T044 [US2] Implement SlackExtractor (desktop app via AX) in Extremis/Extractors/SlackExtractor.swift
- [x] T045 [US2] Add Slack web detection and DOM extraction to SlackExtractor
- [x] T046 [US2] Register SlackExtractor in ExtractorRegistry for com.tinyspeck.slackmacgap and browser URLs
- [x] T047 [US2] Test and refine Slack DOM selectors for channels, DMs, threads

**Checkpoint**: ✅ Slack context (channel, participants, messages) captured and used by LLM

---

## Phase 6: User Story 3 - Gmail Context Awareness (Priority: P2) ✅

**Goal**: When activated in Gmail compose, capture recipients, subject, thread history, draft

**Independent Test**: Reply to email in Gmail, activate Extremis, ask "write polite follow-up" - should reference email

### Implementation for User Story 3

- [x] T048 [US3] Implement GmailMetadata model additions in Extremis/Core/Models/Context.swift
- [x] T049 [US3] Implement GmailExtractor in Extremis/Extractors/GmailExtractor.swift
- [x] T050 [US3] Add Gmail DOM extraction for compose window, thread view
- [x] T051 [US3] Register GmailExtractor in ExtractorRegistry for mail.google.com URLs
- [x] T052 [US3] Handle new compose vs reply vs forward scenarios
- [x] T053 [US3] Test and refine Gmail DOM selectors (.editable, .a3s.aiL, etc.)

**Checkpoint**: ✅ Gmail context (recipients, subject, thread) captured and used by LLM

---

## Phase 7: User Story 4 - GitHub PR Context Awareness (Priority: P3) ✅

**Goal**: When activated on GitHub PR page, capture PR title, branches, changed files, comments

**Independent Test**: Open GitHub PR, activate in description field, ask "summarize changes" - should list files

### Implementation for User Story 4

- [x] T054 [US4] Implement GitHubMetadata model additions in Extremis/Core/Models/Context.swift
- [x] T055 [US4] Implement GitHubExtractor in Extremis/Extractors/GitHubExtractor.swift
- [x] T056 [US4] Add GitHub DOM extraction for PR page elements
- [x] T057 [US4] Register GitHubExtractor in ExtractorRegistry for github.com URLs
- [x] T058 [US4] Handle PR description vs review comment vs issue comment scenarios
- [x] T059 [US4] Test and refine GitHub DOM selectors (.comment-form-textarea, .diff-table, etc.)

**Checkpoint**: ✅ GitHub PR context (title, branches, files, comments) captured and used by LLM

---

## Phase 8: User Story 5 - Custom Hotkey & Preferences (Priority: P3) ✅

**Goal**: User can customize hotkey, configure LLM provider, set appearance and launch options

**Independent Test**: Open preferences, change hotkey to ⌘+Shift+E, close, new hotkey works

### Implementation for User Story 5

- [x] T060 [US5] Implement PreferencesWindow in Extremis/UI/Preferences/PreferencesWindow.swift
- [x] T061 [US5] Implement GeneralTab (hotkey, launch at login) in Extremis/UI/Preferences/GeneralTab.swift
- [x] T062 [US5] Implement KeyboardShortcutField component in Extremis/UI/Components/KeyboardShortcutField.swift
- [x] T063 [US5] Implement ProvidersTab (API keys, active provider) in Extremis/UI/Preferences/ProvidersTab.swift
- [x] T064 [US5] Implement AppearanceTab (theme, window size) in Extremis/UI/Preferences/AppearanceTab.swift
- [x] T065 [US5] Add hotkey conflict detection in HotkeyManager
- [x] T066 [US5] Implement launch at login with SMAppService or LoginItem
- [x] T067 [US5] Wire menu bar "Preferences..." menu item to PreferencesWindow

**Checkpoint**: ✅ All user preferences customizable and persisted

---

## Phase 9: Polish & Cross-Cutting Concerns ✅

**Purpose**: Improvements that affect multiple user stories

- [x] T068 Add visual polish: app icon, menu bar icon states (idle, active, error)
- [x] T069 Add Localizable.strings for user-facing text
- [x] T070 Implement streaming response display in ResponseView
- [x] T071 Add retry logic with exponential backoff for LLM API calls
- [x] T072 Handle edge case: rapid successive activations (debounce)
- [x] T073 Handle edge case: user cancels mid-generation
- [x] T074 Add provider status indicator in prompt window
- [x] T075 Final code review for force unwraps and error handling
- [ ] T076 Performance validation: <200ms activation, <50MB idle memory
- [ ] T077 Run quickstart.md validation (full manual test cycle)

**Checkpoint**: ✅ Production-ready application (pending manual validation)

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup) ────────────────────────────────────────┐
         │                                              │
         ▼                                              │
Phase 2 (Foundational) ◀────────────────────────────────┘
         │
         │ ⚠️ BLOCKS ALL USER STORIES
         ▼
┌────────┴────────┬─────────────┬─────────────┬─────────────┐
│                 │             │             │             │
▼                 ▼             ▼             ▼             ▼
Phase 3 (US1)   Phase 4 (US6) Phase 5 (US2) Phase 6 (US3) Phase 8 (US5)
MVP 🎯          Generic       Slack         Gmail         Preferences
│                 │             │             │             │
│                 │             │             │             │
└────────┬────────┴─────────────┴─────────────┴─────────────┘
         │
         ▼
Phase 7 (US4) - GitHub (can run after US6 for BrowserBridge)
         │
         ▼
Phase 9 (Polish)
```

### User Story Dependencies

| Story | Depends On | Can Run In Parallel With |
|-------|------------|-------------------------|
| **US1 (P1)** | Foundational only | - |
| **US6 (P2)** | US1 (needs prompt flow) | - |
| **US2 (P2)** | US6 (needs BrowserBridge, ExtractorRegistry) | US3, US5 |
| **US3 (P2)** | US6 (needs BrowserBridge, ExtractorRegistry) | US2, US5 |
| **US4 (P3)** | US6 (needs BrowserBridge, ExtractorRegistry) | US5 |
| **US5 (P3)** | Foundational only | US2, US3, US4 |

### Within Each User Story

1. Models/data structures first
2. Core service implementation
3. UI components
4. Integration with main flow
5. Edge case handling

### Parallel Opportunities Per Phase

**Phase 2 (Foundational)**:
- T010, T011, T012 can run in parallel (different model files)
- T014, T015 can run in parallel (different protocol files)
- T017, T018, T019 can run in parallel (different utility files)

**Phase 3 (US1)**:
- T029, T030 can run in parallel (different LLM providers)

**After Foundational**:
- US2, US3, US5 can run in parallel (different features)
- US4 can run in parallel with US5

---

## Parallel Example: Phase 2 Foundational

```bash
# Models can be created in parallel:
Task T010: "Implement data models in Extremis/Core/Models/Instruction.swift"
Task T011: "Implement data models in Extremis/Core/Models/Generation.swift"
Task T012: "Implement data models in Extremis/Core/Models/Preferences.swift"

# Protocols can be created in parallel:
Task T014: "Implement LLMProvider protocol in Extremis/Core/Protocols/LLMProvider.swift"
Task T015: "Implement TextInserter protocol in Extremis/Core/Protocols/TextInserter.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (~8 tasks)
2. Complete Phase 2: Foundational (~13 tasks)
3. Complete Phase 3: User Story 1 (~14 tasks)
4. **STOP and VALIDATE**: Test hotkey → prompt → AI → insert flow
5. Deploy MVP if ready

**MVP Task Count**: 35 tasks

### Incremental Delivery

1. **MVP (35 tasks)**: Setup + Foundational + US1 → Basic AI writing anywhere
2. **+Generic (6 tasks)**: US6 → Works better with selected text in any app
3. **+Slack (6 tasks)**: US2 → Context-aware in Slack
4. **+Gmail (6 tasks)**: US3 → Context-aware in Gmail
5. **+GitHub (6 tasks)**: US4 → Context-aware in GitHub PRs
6. **+Preferences (8 tasks)**: US5 → Customizable hotkey and settings
7. **+Polish (10 tasks)**: Final polish → Production ready

**Total Task Count**: 77 tasks

### Task Distribution by Phase

| Phase | Task Range | Count | Purpose |
|-------|------------|-------|---------|
| Phase 1 | T001-T008 | 8 | Setup |
| Phase 2 | T009-T021 | 13 | Foundational |
| Phase 3 | T022-T035 | 14 | US1 (MVP) |
| Phase 4 | T036-T041 | 6 | US6 (Generic) |
| Phase 5 | T042-T047 | 6 | US2 (Slack) |
| Phase 6 | T048-T053 | 6 | US3 (Gmail) |
| Phase 7 | T054-T059 | 6 | US4 (GitHub) |
| Phase 8 | T060-T067 | 8 | US5 (Preferences) |
| Phase 9 | T068-T077 | 10 | Polish |

---

## Notes

- [P] tasks = different files, no dependencies - can run in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate functionality
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- All file paths use `Extremis/` prefix as per plan.md structure

