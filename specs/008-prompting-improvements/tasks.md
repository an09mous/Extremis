# Tasks: Prompting Improvements & Mode Simplification

**Input**: Design documents from `/specs/008-prompting-improvements/`
**Prerequisites**: plan.md, spec.md, research.md

**Implementation Phases**:
- **Phase 1**: Feature removal - autocomplete, auto-generation, clipboard capture ✅ COMPLETE
- **Phase 2**: Prompt improvements - Rearchitected prompting framework ✅ COMPLETE

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

## ✅ PHASE 2 COMPLETE - Prompt Improvements

**Date Completed**: 2026-01-12

**Rearchitected Prompting Framework**:

The prompting system was completely rearchitected with an intent-based design:

### New Template Structure (6 templates)

| Template | Purpose | User Story |
|----------|---------|------------|
| `system.hbs` | Unified system prompt with capabilities, guidelines, security | US5 |
| `intent_instruct.hbs` | Quick Mode - selection transforms | US4 |
| `intent_chat.hbs` | Chat Mode - conversational messages | US5 |
| `intent_summarize.hbs` | Magic Mode - summarization | US6 |
| `session_summarization_initial.hbs` | First-time session summary | US7 |
| `session_summarization_update.hbs` | Hierarchical summary updates | US7 |

### Key Architecture Changes

1. **Intent-based prompt injection**: Templates injected based on `MessageIntent` enum
2. **Per-message context**: Context embedded inline with each user message, not in system prompt
3. **Rich metadata formatting**: Slack, Gmail, GitHub, Generic metadata all formatted appropriately
4. **Security hardening**: System prompt includes anti-jailbreak instructions
5. **Direct responses**: "No preambles" rule enforced across all templates

### Requirements Fulfilled

- [x] FR-012: Enhanced instruction prompt template with context-type awareness
- [x] FR-013: Context hints to LLM (application type, content format indicators)
- [x] FR-014: Direct, actionable responses without unnecessary preambles
- [x] FR-015: Enhanced chat prompt template leveraging AX metadata
- [x] FR-016: Output style/tone matching to detected application context
- [x] FR-017: Enhanced summarization prompt prioritizing key information
- [x] FR-018: Different content type handling (technical, conversational, narrative)
- [x] FR-019: Session summaries formatted for natural conversation continuation
- [x] FR-020: LLM instructed to treat summarized context as established facts

**Build Status**: ✅ Compiles with no errors
**Test Status**: ✅ All 466 tests pass

---

## ✅ FEATURE COMPLETE

**All phases completed**: 2026-01-12

**Summary**:
- Phase 1: Removed autocomplete, auto-generation, clipboard capture
- Phase 2: Rearchitected prompting framework with intent-based design

**Total User Stories Implemented**: US1-US7 (all 7 user stories)
