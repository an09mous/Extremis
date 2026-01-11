# Research: Autocomplete & Auto-generation Code Inventory

**Feature**: 008-prompting-improvements
**Date**: 2026-01-10
**Purpose**: Complete inventory of all code to be removed/modified in Phase 1

## Decision Summary

| Item | Decision | Rationale |
|------|----------|-----------|
| Autocomplete feature | REMOVE entirely | No product-market fit |
| Auto-generation | REMOVE entirely | Privacy concerns |
| Preceding/succeeding text capture | REMOVE entirely | Privacy concerns |
| ClipboardCapture utility | DELETE file | Only used for removed features |
| Option+Tab without selection | No-op | Cleaner UX than error message |

## Code Inventory

### FILES TO DELETE

#### 1. `Extremis/Resources/PromptTemplates/autocomplete.hbs`
- **Lines**: 28
- **Purpose**: Template for autocomplete mode prompts
- **Dependencies**: Referenced by PromptBuilder.swift, PromptTemplateLoader.swift
- **Action**: DELETE entire file

#### 2. `Extremis/Utilities/ClipboardCapture.swift`
- **Lines**: ~250
- **Purpose**: Marker-based clipboard capture for preceding/succeeding text
- **Key Methods**:
  - `captureVisibleContent()` - Captures text before cursor
  - `captureSucceedingContent()` - Captures text after cursor
  - Uses simulated keyboard events (Cmd+Shift+Up/Down, Cmd+C)
- **Dependencies**: Referenced by ContextExtractor protocol extension
- **Action**: DELETE entire file

#### 3. `Extremis/Tests/Utilities/ClipboardCaptureTests.swift`
- **Lines**: ~200
- **Purpose**: Tests for ClipboardCapture functionality
- **Test Count**: 30 tests
- **Action**: DELETE entire file, update run-tests.sh

---

### FILES TO MODIFY

#### 4. `Extremis/App/AppDelegate.swift`

**Methods to REMOVE**:
| Method | Lines | Purpose |
|--------|-------|---------|
| `performDirectAutocomplete()` | 456-507 | Main autocomplete execution |
| `showAutocompleteError()` | 510-523 | Error notification for autocomplete |
| `handleAutocompleteActivation()` | 427-430 | Legacy alias |
| Hotkey registration block | 342-356 | Option+Tab for autocomplete |

**Methods to REFACTOR**:
| Method | Change |
|--------|--------|
| `handleMagicModeActivation()` | Remove autocomplete branch, keep summarization |
| `captureContextAndShowPrompt()` | Remove clipboard capture, simplify to AX + selection |

#### 5. `Extremis/Core/Services/HotkeyManager.swift`

**Remove from enum**:
```swift
enum HotkeyIdentifier: UInt32, CaseIterable {
    case prompt = 1
    case autocomplete = 2  // ← REMOVE this case
}
```

#### 6. `Extremis/LLMProviders/PromptBuilder.swift`

**Properties to REMOVE**:
- `autocompleteTemplate` (line ~44-47)

**Enum cases to REMOVE**:
```swift
enum PromptMode: String {
    case autocomplete = "AUTOCOMPLETE"  // ← REMOVE
    // ... keep others
}
```

**Methods to REFACTOR**:
- `detectPromptMode()` - Remove autocomplete detection
- `buildPrompt()` - Remove `.autocomplete` case from switch

#### 7. `Extremis/LLMProviders/PromptTemplateLoader.swift`

**Enum cases to REMOVE**:
```swift
enum PromptTemplate: String {
    case autocomplete = "autocomplete"  // ← REMOVE
    // ... keep others
}
```

#### 8. `Extremis/Core/Protocols/ContextExtractor.swift`

**Methods to REMOVE**:
- `captureTextAroundCursor()` protocol extension method (~line 57-80)

**Imports to REMOVE** (if present):
- Any reference to ClipboardCapture

#### 9. `Extremis/Extractors/GenericExtractor.swift`

**Code to REMOVE**:
- Call to `captureTextAroundCursor()`
- Setting `precedingText` and `succeedingText` in Context

**Code to KEEP**:
- AX metadata extraction
- Selection detection (via SelectionDetector)

#### 10. `Extremis/Extractors/BrowserExtractor.swift`

**Code to REMOVE**:
- Call to `captureTextAroundCursor()` (~line 60)
- Setting `precedingText` and `succeedingText`

#### 11. `Extremis/Extractors/SlackExtractor.swift`

**Code to REMOVE**:
- Call to `captureTextAroundCursor()` (if present)
- Setting `precedingText` and `succeedingText`

#### 12. `Extremis/UI/PromptWindow/PromptView.swift`

**UI Text to REMOVE**:
- Line 40: Comment `// Empty instruction = autocomplete mode`
- Line 68: `Text("Empty = autocomplete")`
- Line 123: Placeholder text `return "Autocomplete"`

#### 13. `Extremis/Tests/LLMProviders/PromptBuilderTests.swift`

**Tests to REMOVE**:
| Test Method | Lines |
|-------------|-------|
| `testDetectPromptMode_Autocomplete()` | 86-98 |
| `testDetectPromptMode_AutocompleteWithWhitespace()` | 101-113 |
| `testBuildPrompt_AutocompleteContainsRequiredSections()` | 195-210 |
| `testBuildPrompt_NilSelectedText()` | 233-248 |
| `testBuildPrompt_AllTextFieldsNil()` | 375-391 |

**Update `runAllTests()`** to remove calls to deleted tests.

#### 14. `Extremis/scripts/run-tests.sh`

**Remove**:
- ClipboardCaptureTests compilation and execution

---

### FILES TO KEEP (No Changes)

#### `Extremis/Utilities/SelectionDetector.swift`
- Still needed for Magic Mode (summarization) selection detection
- Still needed for mode routing (Quick Mode vs Chat Mode)
- No autocomplete-specific code

#### `Extremis/Core/Models/Context.swift`
- Keep `precedingText` and `succeedingText` properties for now
- They will be `nil` but removing requires broader changes
- Future cleanup can remove them entirely

---

### DOCUMENTATION TO UPDATE

#### `CLAUDE.md`
- Remove references to autocomplete
- Remove Option+Tab autocomplete description
- Update hotkey documentation

#### `README.md`
- Remove autocomplete feature description (if present)
- Update feature list

---

## Grep Verification Commands

After Phase 1, run these to verify complete removal:

```bash
# Should return NO results (except historical specs):
grep -r "autocomplete" Extremis/ --include="*.swift"
grep -r "AutoComplete" Extremis/ --include="*.swift"
grep -r "ClipboardCapture" Extremis/ --include="*.swift"
grep -r "captureTextAroundCursor" Extremis/ --include="*.swift"
grep -r "captureVisibleContent" Extremis/ --include="*.swift"
grep -r "captureSucceedingContent" Extremis/ --include="*.swift"
grep -r "precedingText" Extremis/ --include="*.swift"  # Will still exist in Context.swift, but unused
grep -r "succeedingText" Extremis/ --include="*.swift"  # Will still exist in Context.swift, but unused
```

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Deprecate autocomplete (keep code) | Dead code violates code quality principles |
| Show error on Option+Tab without selection | Jarring UX, silent no-op is cleaner |
| Keep ClipboardCapture for future use | Privacy concern is fundamental, no planned future use |
| Remove `precedingText`/`succeedingText` from Context | Higher risk, requires broader changes, can be done later |
