# Implementation Plan: Prompting Improvements & Mode Simplification

**Branch**: `008-prompting-improvements` | **Date**: 2026-01-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-prompting-improvements/spec.md`

## Summary

This feature removes autocomplete, auto-generation, and preceding/succeeding text capture for privacy reasons. It simplifies mode routing: Cmd+Shift+Space opens Quick Mode (with selection) or Chat Mode (without selection). Option+Tab becomes summarization-only (no-op without selection). Phase 2 will improve prompt templates.

**Implementation Phases**:
- **Phase 1**: Feature removal (autocomplete, auto-generation, clipboard marker capture) - MUST complete first
- **Phase 2**: Prompt improvements (Quick Mode, Chat Mode, Magic Mode, Memory prompting) - REQUIRES USER APPROVAL

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: SwiftUI, AppKit, Carbon (hotkeys), ApplicationServices (Accessibility APIs)
**Storage**: UserDefaults (preferences), Keychain (API keys), Application Support (sessions)
**Testing**: Standalone Swift test files compiled with swiftc, run via `./scripts/run-tests.sh`
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS menu bar application
**Performance Goals**: UI interactions <100ms, no memory leaks
**Constraints**: Must maintain backward compatibility for existing users, no regressions to Quick Mode, Chat Mode, or Magic Mode summarization
**Scale/Scope**: Single-user desktop app

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity & Separation of Concerns | ✅ PASS | Removing features reduces complexity, no new modules needed |
| II. Code Quality & Best Practices | ✅ PASS | Removing dead code improves quality |
| III. Extensibility & Testability | ✅ PASS | Simplified codebase easier to test |
| IV. User Experience Excellence | ✅ PASS | Clearer mental model, privacy-respecting |
| V. Documentation Synchronization | ⚠️ REQUIRED | Must update CLAUDE.md, README.md after changes |
| VI. Testing Discipline | ✅ PASS | Must remove obsolete tests, verify no regressions |
| VII. Regression Prevention | ⚠️ CRITICAL | Must verify Quick Mode, Chat Mode, Magic Mode work correctly |

**Quality Gates for Phase 1**:
- [ ] Build succeeds without warnings
- [ ] All remaining tests pass
- [ ] Manual QA: Option+Tab with no selection = no-op
- [ ] Manual QA: Option+Tab with selection = summarizes correctly
- [ ] Manual QA: Cmd+Shift+Space with selection = Quick Mode works
- [ ] Manual QA: Cmd+Shift+Space without selection = Chat Mode works
- [ ] No dead code remains (autocomplete, clipboard marker capture)
- [ ] Documentation updated

## Project Structure

### Documentation (this feature)

```text
specs/008-prompting-improvements/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output (code inventory)
├── checklists/          # Quality checklists
│   └── requirements.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Extremis/
├── App/
│   └── AppDelegate.swift              # MODIFY: Remove autocomplete hotkey, refactor mode routing
├── Core/
│   ├── Models/
│   │   └── Context.swift              # MODIFY: Remove precedingText/succeedingText usage
│   ├── Protocols/
│   │   └── ContextExtractor.swift     # MODIFY: Remove captureTextAroundCursor()
│   └── Services/
│       └── HotkeyManager.swift        # MODIFY: Remove .autocomplete identifier
├── Extractors/
│   ├── GenericExtractor.swift         # MODIFY: Remove preceding/succeeding capture
│   ├── BrowserExtractor.swift         # MODIFY: Remove preceding/succeeding capture
│   └── SlackExtractor.swift           # MODIFY: Remove preceding/succeeding capture
├── LLMProviders/
│   ├── PromptBuilder.swift            # MODIFY: Remove autocomplete mode
│   └── PromptTemplateLoader.swift     # MODIFY: Remove .autocomplete case
├── UI/PromptWindow/
│   └── PromptView.swift               # MODIFY: Remove autocomplete UI text
├── Utilities/
│   ├── ClipboardCapture.swift         # DELETE: Entire file (marker-based capture)
│   └── SelectionDetector.swift        # KEEP: Still needed for selection detection
├── Resources/PromptTemplates/
│   └── autocomplete.hbs               # DELETE: Template file
└── Tests/
    ├── LLMProviders/
    │   └── PromptBuilderTests.swift   # MODIFY: Remove autocomplete tests
    └── Utilities/
        └── ClipboardCaptureTests.swift # DELETE: Entire test file
```

**Structure Decision**: Single macOS application. Changes are primarily subtractive (removing code) with minimal refactoring of existing flows.

## Phase 1: Feature Removal (Autocomplete, Auto-generation, Clipboard Capture)

**CRITICAL**: This phase removes features and dead code. No prompt improvements yet.

### 1.1 Files to DELETE Entirely

| File | Reason |
|------|--------|
| `Extremis/Resources/PromptTemplates/autocomplete.hbs` | Autocomplete template no longer needed |
| `Extremis/Utilities/ClipboardCapture.swift` | Marker-based capture removed for privacy |
| `Extremis/Tests/Utilities/ClipboardCaptureTests.swift` | Tests for removed functionality |

### 1.2 Files to MODIFY

#### AppDelegate.swift - Hotkey & Mode Routing

**Remove**:
- `performDirectAutocomplete()` method entirely
- `showAutocompleteError()` method entirely
- `handleAutocompleteActivation()` method entirely
- Autocomplete hotkey registration in `setupHotkey()` (lines 342-356)

**Refactor** `handleMagicModeActivation()`:
```swift
// BEFORE: If no selection → autocomplete
// AFTER: If no selection → no-op (silent)
func handleMagicModeActivation() {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000)
        let selectionResult = SelectionDetector.detectSelection()

        if selectionResult.hasSelection,
           let selectedText = selectionResult.selectedText,
           let source = selectionResult.source {
            // Selection exists → Summarize (unchanged)
            await performSummarization(text: selectedText, source: source)
        }
        // No selection → do nothing (no-op)
    }
}
```

**Refactor** `captureContextAndShowPrompt()`:
- Remove clipboard marker capture calls
- Only capture AX metadata + selected text (if any)
- Route to Quick Mode (selection) or Chat Mode (no selection)

#### HotkeyManager.swift

**Remove** from `HotkeyIdentifier` enum:
```swift
// Remove this case:
case autocomplete = 2
```

#### PromptBuilder.swift

**Remove**:
- `autocompleteTemplate` property
- `.autocomplete` case from `PromptMode` enum
- Autocomplete handling in `detectPromptMode()`
- Autocomplete case in `buildPrompt()` switch

#### PromptTemplateLoader.swift

**Remove** from `PromptTemplate` enum:
```swift
// Remove this case:
case autocomplete = "autocomplete"
```

#### Context.swift

**Keep** `precedingText` and `succeedingText` properties (for backward compatibility) but:
- They will always be `nil` after this change
- Can be fully removed in a future cleanup if desired

#### ContextExtractor.swift (Protocol)

**Remove**:
- `captureTextAroundCursor()` method from protocol extension
- Any references to ClipboardCapture

#### All Extractors (GenericExtractor, BrowserExtractor, SlackExtractor)

**Remove**:
- Calls to `captureTextAroundCursor()`
- Setting `precedingText` and `succeedingText` in Context initialization

**Keep**:
- AX metadata capture (app name, window title, bundle ID)
- Selected text capture via SelectionDetector

#### PromptView.swift

**Remove**:
- Text "Empty = autocomplete" label
- Any placeholder text referencing autocomplete
- Comments mentioning autocomplete

#### PromptBuilderTests.swift

**Remove** these test methods:
- `testDetectPromptMode_Autocomplete()`
- `testDetectPromptMode_AutocompleteWithWhitespace()`
- `testBuildPrompt_AutocompleteContainsRequiredSections()`
- `testBuildPrompt_NilSelectedText()` (if autocomplete-specific)
- `testBuildPrompt_AllTextFieldsNil()` (if autocomplete-specific)
- Any other tests referencing autocomplete mode

**Update** `runAllTests()` to not call removed tests.

### 1.3 Mode Routing Logic (Post-Refactor)

```
Cmd+Shift+Space triggered
    │
    ▼
SelectionDetector.detectSelection()
    │
    ├── Selection EXISTS
    │   │
    │   ▼
    │   Quick Mode opens
    │   (Context = AX metadata + selected text)
    │
    └── NO Selection
        │
        ▼
        Chat Mode opens
        (Context = AX metadata only)

Option+Tab triggered
    │
    ▼
SelectionDetector.detectSelection()
    │
    ├── Selection EXISTS
    │   │
    │   ▼
    │   Magic Mode (Summarization)
    │   (unchanged behavior)
    │
    └── NO Selection
        │
        ▼
        No-op (silent, do nothing)
```

### 1.4 Verification Checklist

After Phase 1 implementation:

- [ ] `swift build` succeeds with no errors
- [ ] `./scripts/run-tests.sh` passes (remaining tests)
- [ ] Option+Tab with NO selection → nothing happens
- [ ] Option+Tab WITH selection → summarization works
- [ ] Cmd+Shift+Space WITH selection → Quick Mode opens with selection as context
- [ ] Cmd+Shift+Space with NO selection → Chat Mode opens
- [ ] No references to "autocomplete" in codebase (except maybe historical specs)
- [ ] No references to ClipboardCapture in codebase
- [ ] autocomplete.hbs file deleted
- [ ] ClipboardCapture.swift file deleted
- [ ] ClipboardCaptureTests.swift file deleted
- [ ] CLAUDE.md updated to remove autocomplete references
- [ ] README.md updated if it mentions autocomplete

---

## Phase 2: Prompt Improvements (PENDING USER APPROVAL)

**⚠️ DO NOT START PHASE 2 UNTIL USER EXPLICITLY APPROVES**

Phase 2 will cover:
- FR-012 to FR-014: Quick Mode prompting improvements
- FR-015 to FR-016: Chat Mode prompting improvements
- FR-017 to FR-018: Magic Mode prompting improvements
- FR-019 to FR-020: Memory/Session prompting improvements

This phase will:
1. Update `instruction.hbs` template for better Quick Mode responses
2. Update `chat_system.hbs` template for better Chat Mode context awareness
3. Update `summarization.hbs` template for improved summaries
4. Update `session_summarization.hbs` for better memory context injection

**Detailed Phase 2 planning will occur after Phase 1 completion and user approval.**

---

## Complexity Tracking

| Decision | Why Needed | Simpler Alternative Rejected Because |
|----------|------------|-------------------------------------|
| Keep `precedingText`/`succeedingText` properties in Context | Backward compatibility, avoid breaking changes | Full removal requires updating all Context usages, higher risk |
| Delete ClipboardCapture entirely vs deprecate | Privacy requirement is absolute, no future use case | Deprecation leaves dead code |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking Quick Mode | Low | High | Manual QA verification, existing tests |
| Breaking Chat Mode | Low | High | Manual QA verification |
| Breaking Magic Mode summarization | Low | High | Focused testing of Option+Tab with selection |
| Missing dead code references | Medium | Low | Grep for "autocomplete", "ClipboardCapture", etc. |
| Test failures from removed code | Medium | Low | Update test suite systematically |
