# Implementation Tasks: View Context Button

**Branch**: `006-view-context` | **Date**: 2025-12-28
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Task Legend

- `[ ]` Not started
- `[/]` In progress
- `[x]` Complete
- `[-]` Cancelled/Skipped

---

## Phase 1: Setup

- [x] T001 Verify branch `006-view-context` is checked out and up to date

---

## Phase 2: User Story 1 - View Full Context (P1 MVP) 🎯

**Goal**: User can click View button to see complete captured context
**Independent Test**: Activate Extremis → See View button → Click → See full context in sheet

- [x] T002 [US1] Create ContextViewerSheet view in `Extremis/UI/PromptWindow/ContextViewerSheet.swift`
- [x] T003 [US1] Implement header section with title "Captured Context" and close button
- [x] T004 [US1] Implement source section displaying app name, bundle ID, window title, URL
- [x] T005 [US1] Implement selected text section with label and scrollable text display
- [x] T006 [US1] Implement preceding text section with label and scrollable text display
- [x] T007 [US1] Implement succeeding text section with label and scrollable text display
- [x] T008 [US1] Implement metadata section for Slack (channel, messages), Gmail (subject, recipients), GitHub (PR number), Generic
- [x] T009 [US1] Add ScrollView container and style consistent with existing UI in `Extremis/UI/PromptWindow/ContextViewerSheet.swift`
- [x] T010 [US1] Add `onViewContext: (() -> Void)?` parameter to ContextBanner in `Extremis/UI/PromptWindow/PromptView.swift`
- [x] T011 [US1] Add eye icon View button to ContextBanner that calls onViewContext callback
- [x] T012 [US1] Add `onViewContext: (() -> Void)?` parameter to PromptInputView in `Extremis/UI/PromptWindow/PromptView.swift`
- [x] T013 [US1] Pass onViewContext callback from PromptInputView to ContextBanner
- [x] T014 [US1] Add `@State private var showContextViewer = false` to PromptContainerView in `Extremis/UI/PromptWindow/PromptWindowController.swift`
- [x] T015 [US1] Add `.sheet(isPresented: $showContextViewer)` modifier to PromptContainerView
- [x] T016 [US1] Pass onViewContext callback through PromptContainerView to PromptInputView
- [x] T017 [US1] Update PromptInputView_Previews to include onViewContext parameter

---

## Phase 3: User Story 2 - Copy Context (P2)

**Goal**: User can copy all or parts of the captured context
**Independent Test**: Open context viewer → Click Copy All → Paste in another app → Verify content

- [x] T018 [US2] Add "Copy All" button in ContextViewerSheet footer in `Extremis/UI/PromptWindow/ContextViewerSheet.swift`
- [x] T019 [US2] Implement formatContextForClipboard() method to format complete context as readable text
- [x] T020 [US2] Wire Copy All button to copy formatted context to NSPasteboard.general
- [x] T021 [US2] Add `@State private var copiedSection: String?` for copy feedback state
- [x] T022 [US2] Add "Copied!" feedback overlay that auto-dismisses after 1.5 seconds
- [x] T023 [US2] Add `.textSelection(.enabled)` to all text displays in ContextViewerSheet

---

## Phase 4: Polish & Edge Cases

- [x] T024 Only show View button in ContextBanner when context has content (selectedText OR precedingText OR succeedingText)
- [x] T025 Hide empty sections in ContextViewerSheet (don't show section if content is nil/empty)
- [x] T026 Add SwiftUI Preview for ContextViewerSheet with full sample context in `Extremis/UI/PromptWindow/ContextViewerSheet.swift`
- [x] T027 Add SwiftUI Preview for ContextViewerSheet with minimal context (only source info)
- [x] T028 Add SwiftUI Preview for ContextBanner with View button
- [-] T029 Test performance with 50,000+ character text content (deferred to manual testing)
- [x] T030 Update aiaudit.csv with all modified/created files

---

## Dependencies

```
T001 (Setup)
  │
  ▼
T002-T009 (Create ContextViewerSheet) ─┐
                                       │
T010-T013 (Modify ContextBanner/       ├──► T017 (Integration)
           PromptInputView)  ──────────┘
                                       │
T014-T016 (Add sheet to                │
           PromptContainerView) ───────┘
  │
  ▼
T018-T023 (Copy functionality - US2)
  │
  ▼
T024-T030 (Polish)
```

## Parallel Execution Opportunities

**Within Phase 2 (US1)**:
- T002-T009 (ContextViewerSheet) can be done in parallel with T010-T013 (ContextBanner modifications)
- T014-T016 (PromptContainerView) depends on both being complete

**Within Phase 3 (US2)**:
- T018-T020 (Copy All) can be done in parallel with T023 (text selection)
- T021-T022 (feedback) depends on T018-T020

---

## Summary

| Phase | Tasks | User Story | Estimated Time |
|-------|-------|------------|----------------|
| Phase 1: Setup | T001 | - | 5 min |
| Phase 2: View Context | T002-T017 | US1 (P1 MVP) | 2 hours |
| Phase 3: Copy | T018-T023 | US2 (P2) | 1 hour |
| Phase 4: Polish | T024-T030 | - | 45 min |
| **Total** | **30 tasks** | **2 stories** | **~4 hours** |

## MVP Scope

**Minimum Viable Product**: Complete Phase 1 + Phase 2 (T001-T017)
- User can see View button in context banner
- Clicking View opens sheet with complete context
- Sheet is dismissible via close button or Escape

Copy functionality (Phase 3) and polish (Phase 4) can be delivered incrementally after MVP.

