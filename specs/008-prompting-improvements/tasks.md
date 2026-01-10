# Tasks: Prompting Improvements & Mode Simplification

**Input**: Design documents from `/specs/008-prompting-improvements/`
**Prerequisites**: plan.md, spec.md, research.md

**Implementation Phases**:
- **Phase 1** (This file): Feature removal - autocomplete, auto-generation, clipboard capture ✅ COMPLETE
- **Phase 2**: Prompt improvements - **REQUIRES USER APPROVAL AFTER PHASE 1 COMPLETION**

**Tests**: Existing tests will be removed (for deleted features). No new tests requested.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: File Deletions (Blocking) ✅

**Purpose**: Remove files that will cause compilation errors if referenced elsewhere

- [x] T001 Delete template file `Extremis/Resources/PromptTemplates/autocomplete.hbs`
- [x] T002 Delete utility file `Extremis/Utilities/ClipboardCapture.swift`
- [x] T003 Delete test file `Extremis/Tests/Utilities/ClipboardCaptureTests.swift`

---

## Phase 2: Core Removals (Blocking - Must Complete Sequentially) ✅

**Purpose**: Remove autocomplete/clipboard references from core files to restore compilation

### Prompt System Cleanup

- [x] T004 [US1] Remove `.autocomplete` case from `PromptTemplate` enum in `Extremis/LLMProviders/PromptTemplateLoader.swift`
- [x] T005 [US1] Remove `autocompleteTemplate` property from `Extremis/LLMProviders/PromptBuilder.swift`
- [x] T006 [US1] Remove `.autocomplete` case from `PromptMode` enum in `Extremis/LLMProviders/PromptBuilder.swift`
- [x] T007 [US1] Remove autocomplete detection from `detectPromptMode()` in `Extremis/LLMProviders/PromptBuilder.swift`
- [x] T008 [US1] Remove `.autocomplete` case from `buildPrompt()` switch in `Extremis/LLMProviders/PromptBuilder.swift`

### Hotkey System Cleanup

- [x] T009 [US1] Rename `.autocomplete` to `.magicMode` in `HotkeyIdentifier` enum in `Extremis/Core/Services/HotkeyManager.swift`

### Extractor Protocol Cleanup

- [x] T010 [US2] Remove `captureTextAroundCursor()` method from protocol extension in `Extremis/Core/Protocols/ContextExtractor.swift`
- [x] T011 [US2] Remove any ClipboardCapture imports/references in `Extremis/Core/Protocols/ContextExtractor.swift`

---

## Phase 3: User Story 1 - Remove Autocomplete & Auto-generation (Priority: P1) ✅

**Goal**: Remove all autocomplete functionality from AppDelegate and hotkey system

**Independent Test**: Press Option+Tab without text selection → nothing happens

### Implementation for User Story 1

- [x] T012 [US1] Update hotkey registration to use `.magicMode` in `Extremis/App/AppDelegate.swift`
- [x] T013 [US1] Remove `handleAutocompleteActivation()` method in `Extremis/App/AppDelegate.swift`
- [x] T014 [US1] Remove `performDirectAutocomplete()` method in `Extremis/App/AppDelegate.swift`
- [x] T015 [US1] Remove `showAutocompleteError()` method in `Extremis/App/AppDelegate.swift`
- [x] T016 [US1] Refactor `handleMagicModeActivation()` to no-op when no selection in `Extremis/App/AppDelegate.swift`

---

## Phase 4: User Story 2 - Remove Preceding/Succeeding Text Capture (Priority: P1) ✅

**Goal**: Remove clipboard marker-based text capture from all extractors

**Independent Test**: Trigger Extremis → Context shows only AX metadata + selected text (no preceding/succeeding)

### Implementation for User Story 2

- [x] T017 [P] [US2] Remove `captureTextAroundCursor()` call and preceding/succeeding text handling in `Extremis/Extractors/GenericExtractor.swift`
- [x] T018 [P] [US2] Remove `captureTextAroundCursor()` call and preceding/succeeding text handling in `Extremis/Extractors/BrowserExtractor.swift`
- [x] T019 [P] [US2] Remove `captureTextAroundCursor()` call and preceding/succeeding text handling in `Extremis/Extractors/SlackExtractor.swift`
- [x] T020 [US2] Refactor `captureContextAndShowPrompt()` to remove clipboard capture calls in `Extremis/App/AppDelegate.swift`

---

## Phase 5: User Story 3 - Selection-Based Mode Routing (Priority: P1) ✅

**Goal**: Ensure Cmd+Shift+Space opens Quick Mode (with selection) or Chat Mode (without selection)

**Independent Test**:
- With selection: Cmd+Shift+Space → Quick Mode opens
- Without selection: Cmd+Shift+Space → Chat Mode opens

### Implementation for User Story 3

- [x] T021 [US3] Verify/update mode routing logic in `captureContextAndShowPrompt()` in `Extremis/App/AppDelegate.swift`
- [x] T022 [US3] Ensure Quick Mode opens when selection exists (may already be correct)
- [x] T023 [US3] Ensure Chat Mode opens when no selection (may already be correct)

---

## Phase 6: Test Suite Cleanup ✅

**Purpose**: Remove autocomplete-related tests and update test runner

- [x] T024 [P] Remove `testDetectPromptMode_Autocomplete()` from `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T025 [P] Remove `testDetectPromptMode_AutocompleteWithWhitespace()` from `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T026 [P] Remove `testBuildPrompt_AutocompleteContainsRequiredSections()` from `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T027 [P] Update `testBuildPrompt_NilSelectedText()` to test instruction mode instead in `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T028 [P] Update `testBuildPrompt_AllTextFieldsNil()` to test instruction mode instead in `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T029 Update `runAllTests()` to remove calls to deleted test methods in `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`
- [x] T030 Remove ClipboardCaptureTests from `Extremis/scripts/run-tests.sh`

---

## Phase 7: UI Cleanup ✅

**Purpose**: Remove autocomplete references from UI

- [x] T031 [P] Remove "Empty = autocomplete" text/label from `Extremis/UI/PromptWindow/PromptView.swift`
- [x] T032 [P] Remove autocomplete-related comments from `Extremis/UI/PromptWindow/PromptView.swift`
- [x] T033 [P] Update placeholder text that references autocomplete in `Extremis/UI/PromptWindow/PromptView.swift`

---

## Phase 8: Documentation & Verification ✅

**Purpose**: Update documentation and verify complete removal

- [x] T034 [P] Update CLAUDE.md to remove autocomplete references and update hotkey documentation
- [x] T035 [P] Update README.md if it mentions autocomplete (not present - no changes needed)
- [x] T036 Run `swift build` and verify no errors or warnings
- [x] T037 Run `./scripts/run-tests.sh` and verify all tests pass (379 tests pass)
- [x] T038 Run grep verification commands from research.md to confirm no residual references
- [ ] T039 Manual QA: Option+Tab with NO selection → verify no-op (USER TO VERIFY)
- [ ] T040 Manual QA: Option+Tab WITH selection → verify summarization works (USER TO VERIFY)
- [ ] T041 Manual QA: Cmd+Shift+Space WITH selection → verify Quick Mode works (USER TO VERIFY)
- [ ] T042 Manual QA: Cmd+Shift+Space without selection → verify Chat Mode works (USER TO VERIFY)

---

## ✅ PHASE 1 COMPLETE - Summary

**Date Completed**: 2026-01-10

**What was removed**:
1. Autocomplete feature (Option+Tab without selection now does nothing)
2. Auto-generation code paths
3. Clipboard marker-based preceding/succeeding text capture
4. All autocomplete-related tests and UI references

**Files deleted**:
- `Extremis/Resources/PromptTemplates/autocomplete.hbs`
- `Extremis/Utilities/ClipboardCapture.swift`
- `Extremis/Tests/Utilities/ClipboardCaptureTests.swift`

**Mode behavior after Phase 1**:
- **Option+Tab with selection**: Magic Mode - summarizes selected text
- **Option+Tab without selection**: No-op (does nothing silently)
- **Cmd+Shift+Space with selection**: Quick Mode opens
- **Cmd+Shift+Space without selection**: Chat Mode opens

**Build Status**: ✅ Compiles with no errors
**Test Status**: ✅ All 379 tests pass

---

## ⛔ Phase 2 Placeholder: Prompt Improvements (REQUIRES USER APPROVAL)

**⚠️ DO NOT PROCEED WITH THESE TASKS UNTIL USER EXPLICITLY APPROVES**

Phase 2 will cover User Stories 4-7:
- US4: Improved Quick Mode Prompting (P1) - FR-012 to FR-014
- US5: Improved Chat Mode Prompting (P1) - FR-015 to FR-016
- US6: Improved Magic Mode Prompting (P2) - FR-017 to FR-018
- US7: Enhanced Memory/Session Prompting (P2) - FR-019 to FR-020

**Templates to update**:
- `instruction.hbs` - Quick Mode
- `chat_system.hbs` - Chat Mode
- `summarization.hbs` - Magic Mode
- `session_summarization.hbs` - Memory/Session

**Detailed tasks will be generated after Phase 1 completion and user approval.**

---

## Notes

- Total tasks in Phase 1: 42 (38 automated, 4 manual QA by user)
- User Stories covered: US1, US2, US3 (Feature Removal)
- Phase 2 (US4-US7: Prompt Improvements) blocked until user approval
