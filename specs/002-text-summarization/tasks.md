# Tasks: Text Summarization (Selection-Aware)

**Input**: Design documents from `/specs/002-text-summarization/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)
**Last Updated**: 2025-12-16 (Revised for selection-aware UX)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
- Include exact file paths in descriptions

---

## Phase 1: Selection Detection Infrastructure

**Purpose**: Fast selection detection to enable smart mode switching

- [ ] T001 [P] Create SelectionDetector utility in Extremis/Utilities/SelectionDetector.swift
  - Fast Accessibility API check for `kAXSelectedTextAttribute`
  - Returns `(hasSelection: Bool, selectedText: String?, source: ContextSource?)`
- [ ] T002 [P] Create SummaryFormat and SummaryLength enums in Extremis/Core/Models/Summary.swift
- [ ] T003 [P] Create SummaryRequest and SummaryResult structs in Extremis/Core/Models/Summary.swift

**Checkpoint**: ✅ Can quickly detect if user has text selected

---

## Phase 2: Context Capture Optimization

**Purpose**: Skip expensive clipboard capture when selection exists

- [ ] T004 Add `captureContextFast(selectionOnly: Bool)` to ContextOrchestrator
  - When `selectionOnly=true`: Only get selectedText + source (skip preceding/succeeding)
  - When `selectionOnly=false`: Full capture (existing behavior)
- [ ] T005 Modify GenericExtractor to support fast mode (selection only)
- [ ] T006 Modify BrowserExtractor to support fast mode (selection only)

**Checkpoint**: ✅ Context capture is 400-600ms faster when only selection needed

---

## Phase 3: Summarization Service

**Purpose**: LLM integration for summarization

- [ ] T007 Add summarization prompt template to Extremis/LLMProviders/PromptBuilder.swift
- [ ] T008 Add `buildSummarizePrompt(text:format:length:)` method to PromptBuilder
- [ ] T009 Create SummarizationService in Extremis/Core/Services/SummarizationService.swift
- [ ] T010 Implement `summarizeStream()` in SummarizationService using LLMProvider

**Checkpoint**: ✅ Can generate summaries programmatically

---

## Phase 4: Magic Mode (⌥+Tab) - Selection-Aware 🎯 MVP Part 1

**Goal**: ⌥+Tab behaves differently based on selection state

**Test Cases**:
- Select text → Press ⌥+Tab → Toast + PromptWindow opens with summary streaming
- No selection → Press ⌥+Tab → Toast + Autocomplete (existing behavior)

- [ ] T011 Rename `handleAutocompleteActivation()` to `handleMagicModeActivation()` in AppDelegate
- [ ] T012 Add selection detection at start of Magic Mode handler using SelectionDetector
- [ ] T013 Implement branching logic: if selection → summarize path, else → autocomplete path
- [ ] T014 Add visual feedback: "📝 Summarizing..." toast when summarizing
- [ ] T015 Add visual feedback: "✨ Completing..." toast when autocompleting
- [ ] T016 When selection exists: Open PromptWindow and auto-trigger summarization
- [ ] T017 Pass `autoSummarize: true` flag to PromptWindowController when triggered from Magic Mode

**Checkpoint**: ✅ Magic Mode intelligently switches between summarize/autocomplete

---

## Phase 5: Prompt Mode (⌘+⇧+Space) - Summarize Button 🎯 MVP Part 2

**Goal**: Add secondary "Summarize" button to prompt window when text is selected

**Test Cases**:
- Select text → Press ⌘+⇧+Space → See "Summarize" button (secondary) → Click → Get summary
- No selection → Press ⌘+⇧+Space → No "Summarize" button (existing behavior)

- [ ] T018 Modify `handleHotkeyActivation()` to pass selection state to PromptWindow
- [ ] T019 Add `hasSelection` and `selectedText` properties to PromptViewModel
- [ ] T020 Add secondary "Summarize" button to PromptView (visible only when hasSelection=true)
- [ ] T021 Implement Summarize button action → calls SummarizationService → shows in ResponseView
- [ ] T022 Support `autoSummarize` mode for Magic Mode integration (auto-trigger on window open)
- [ ] T023 Skip clipboard capture in Prompt Mode when selection exists (optimization)

**Checkpoint**: ✅ Users can one-click summarize in Prompt Window

---

## Phase 6: Enhanced PromptWindow for Summaries

**Goal**: Ensure PromptWindow ResponseView works well for summaries

- [ ] T024 Ensure ResponseView handles summary formatting well (paragraphs, bullets, etc.)
- [ ] T025 Verify Copy button copies summary correctly
- [ ] T026 Verify Insert button replaces original selection with summary
- [ ] T027 Add summary-specific response header (e.g., "Summary" vs "Response")
- [ ] T028 Test streaming display for summary responses

**Checkpoint**: ✅ PromptWindow fully supports summary display and actions

---

## Phase 7: Summary Customization (P2)

**Goal**: Adjust summary length and format

- [ ] T029 Add Shorter/Longer buttons to ResponseView when showing summary
- [ ] T030 Implement length adjustment (regenerate with new length parameter)
- [ ] T031 Add format selector (Paragraph, Bullets, Key Points, Actions)
- [ ] T032 Save default format preference to UserDefaults
- [ ] T033 Implement ⌘+Z to undo insertion (restore original selection)

**Checkpoint**: ✅ Full summary customization available

---

## Phase 8: Documentation & Polish

**Purpose**: User guidance and documentation sync

- [ ] T034 [P] Update Extremis/docs/flow-diagram.md with selection-aware flows
- [ ] T035 [P] Update README.md with Magic Mode explanation
- [ ] T036 Add menu bar items reflecting new behavior ("Magic Mode" instead of "Autocomplete")
- [ ] T037 Add preferences for default summary format (optional)

**Checkpoint**: ✅ Feature complete with documentation

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Selection Detection)
    │
    ├── Phase 2 (Context Optimization) ←─ depends on selection detection
    │       │
    │       └── Phase 3 (Summarization Service) ←─ can start in parallel with Phase 2
    │               │
    │               ├── Phase 4 (Magic Mode MVP) ←─ BLOCKS on Phase 3
    │               │
    │               └── Phase 5 (Prompt Mode MVP) ←─ can run parallel to Phase 4
    │
    └── Phase 6 (Summary Panel) ←─ can start after Phase 3
            │
            └── Phase 7 (Customization) ←─ depends on Phase 6
                    │
                    └── Phase 8 (Documentation) ←─ final polish
```

### Parallel Opportunities

Within Phase 1:
- T001, T002, T003 can run in parallel (different files)

Within Phase 6:
- T023, T024 can run in parallel (ViewModel and View are separate files)

Across Phases:
- Phase 4 and Phase 5 can run in parallel (different entry points)
- Phase 3 and Phase 2 can overlap (summarization doesn't need context optimization)

---

## Implementation Strategy

### MVP Definition

**MVP = Phase 1-5** (Selection-aware Magic Mode + Summarize Button)

Deliverables:
1. ⌥+Tab with selection → Shows summary (inline/toast)
2. ⌥+Tab without selection → Autocomplete (existing)
3. ⌘+⇧+Space with selection → Shows "Summarize" button
4. Click "Summarize" → Shows summary in response view

### Recommended Order

1. **Phase 1**: Selection Detection (~30 min)
2. **Phase 3**: Summarization Service (~1 hour) - can parallelize with Phase 2
3. **Phase 2**: Context Optimization (~30 min)
4. **Phase 4**: Magic Mode (~1.5 hours) 🎯 **First testable milestone**
5. **Phase 5**: Prompt Mode (~1 hour) 🎯 **Full MVP**
6. **STOP and VALIDATE**: Test both modes end-to-end
7. **Phase 6-8**: Enhancements based on feedback

---

## Key Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `Utilities/SelectionDetector.swift` | NEW | Fast selection detection utility |
| `Core/Models/Summary.swift` | NEW | Summary types and models |
| `Core/Services/SummarizationService.swift` | NEW | Summarization orchestration |
| `Core/Services/ContextOrchestrator.swift` | MODIFY | Add fast-path for selection-only capture |
| `LLMProviders/PromptBuilder.swift` | MODIFY | Add summarization prompt template |
| `App/AppDelegate.swift` | MODIFY | Rename autocomplete handler, add branching, toasts |
| `UI/PromptWindow/PromptView.swift` | MODIFY | Add secondary "Summarize" button |
| `UI/PromptWindow/PromptViewModel.swift` | MODIFY | Add hasSelection, autoSummarize support |
| `UI/PromptWindow/PromptWindowController.swift` | MODIFY | Support autoSummarize mode |
| `Extractors/GenericExtractor.swift` | MODIFY | Support fast mode (selection only) |
| `Extractors/BrowserExtractor.swift` | MODIFY | Support fast mode (selection only) |

---

## Notes

- **No new hotkeys** - reuse existing ⌥+Tab and ⌘+⇧+Space
- **No new SummaryPanel** - reuse existing PromptWindow + ResponseView
- Selection detection uses Accessibility API (fast, ~10ms)
- Clipboard capture takes ~400-600ms (skip when selection exists)
- Toast feedback makes behavior transparent to user
- Summarize button is secondary - can promote to primary based on usage

