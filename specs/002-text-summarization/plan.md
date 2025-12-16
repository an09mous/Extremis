# Implementation Plan: Text Summarization

**Branch**: `002-text-summarization` | **Date**: 2025-12-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification + user refinement for selection-aware behavior
**Last Updated**: 2025-12-16 (UX refinement)

## Summary

Add intelligent text summarization to Extremis that detects user intent based on text selection state:

1. **Prompt Mode (⌘+⇧+Space)**: Add a "Summarize" button to the prompt window that summarizes selected content without requiring user to type an instruction
2. **Magic Mode (⌥+Tab, formerly Autocomplete)**: Smart behavior based on selection state:
   - **Text Selected** → Provide summary directly (user intent = "summarize this")
   - **No Selection** → Proceed with existing autocomplete (user intent = "complete this")

**Key Optimization**: If `selectedText` is detected (via Accessibility API), skip the expensive marker-based clipboard capture entirely - we already have what we need.

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency (async/await)
**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices (Accessibility), Carbon (Hotkeys)
**Storage**: UserDefaults for preferences (existing infrastructure)
**Testing**: Manual testing, XCTest for unit tests
**Target Platform**: macOS 13.0+ (Ventura and later)
**Project Type**: Single macOS menu bar application
**Performance Goals**: Panel appears <500ms, first token <2s, smooth 60fps animations
**Constraints**: <10MB additional memory, minimal CPU when idle
**Scale/Scope**: Single user, local execution, cloud LLM APIs

## Constitution Check

*GATE: Must pass before implementation. Checked against `.specify/memory/constitution.md`*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity First | ✅ | SummarizationService as independent module, selection detection at extractor layer |
| II. Code Quality Excellence | ✅ | Follows existing patterns, SOLID principles, strong typing |
| III. User Experience Primacy | ✅ | Intuitive - selection = summarize, no selection = autocomplete |
| IV. Documentation Synchronization | ✅ | README, flow-diagram.md, and docs to be updated |

## UX Design: Selection-Aware Intent Detection

### Core Insight: Selection = User Intent

When a user selects text before pressing a hotkey, they're signaling intent:
- "I want to do something with THIS text"
- The most natural action is to understand/summarize it

When no text is selected, cursor is in a writing context:
- "I want help continuing/completing what I'm writing"
- The most natural action is autocomplete

### Mode Behavior Matrix

| Hotkey | Text Selected? | Behavior | User Experience |
|--------|---------------|----------|-----------------|
| ⌘+⇧+Space | No | Show Prompt Window (current behavior) | User types instruction |
| ⌘+⇧+Space | Yes | Show Prompt Window + **Summarize button** visible | User can click "Summarize" OR type custom instruction |
| ⌥+Tab | No | Autocomplete (current behavior) | AI continues writing |
| ⌥+Tab | Yes | **Direct Summary** - shows result inline/panel | Instant summary of selection |

### Selection Detection - Skip Clipboard Capture Optimization

**Current Flow (Slow)**:
```
Hotkey → Get selectedText (Accessibility) → Capture preceding (Clipboard) → Capture succeeding (Clipboard) → Build Context
```

**Optimized Flow (Fast for Summarization)**:
```
Hotkey → Get selectedText (Accessibility) → IF selectedText exists → SKIP clipboard capture → Summarize directly
```

This saves ~400-600ms by avoiding marker-based clipboard operations when user already has text selected.

## Project Structure

### Documentation (this feature)

```text
specs/002-text-summarization/
├── spec.md              # Feature specification
├── plan.md              # This file
└── tasks.md             # Implementation tasks (to be created)
```

### Source Code (extends existing structure)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   └── Summary.swift              # NEW: SummaryRequest, SummaryResult, SummaryFormat, SummaryLength
│   ├── Protocols/
│   │   └── Summarizer.swift           # NEW: Summarizer protocol for abstraction
│   └── Services/
│       └── SummarizationService.swift # NEW: Orchestrates summarization workflow
│
├── UI/
│   └── SummaryPanel/                  # NEW: Summary panel UI
│       ├── SummaryPanelController.swift
│       ├── SummaryView.swift
│       └── SummaryViewModel.swift
│
├── LLMProviders/
│   └── PromptBuilder.swift            # MODIFY: Add summarization prompt templates
│
└── App/
    └── AppDelegate.swift              # MODIFY: Register summarization hotkey
```

## Architecture Design

### Component Interaction Flow - Magic Mode (⌥+Tab)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MAGIC MODE (⌥+Tab) - Selection Aware          │
└─────────────────────────────────────────────────────────────────┘

     ⌥+Tab
       │
       ▼
┌──────────────────┐
│  HotkeyManager   │  ← Existing autocomplete hotkey
└────────┬─────────┘
         │
         ▼
┌────────────────────────────┐
│ handleMagicModeActivation  │  ← RENAMED from handleAutocompleteActivation
└────────────┬───────────────┘
             │
             ▼
┌────────────────────────────┐
│ SelectionDetector          │  ← Fast check via Accessibility API (~10ms)
│   .detectSelection()       │
└────────────┬───────────────┘
             │
      ┌──────┴──────┐
      │             │
      ▼             ▼
┌──────────┐   ┌─────────────────┐
│ Selected │   │ No Selection    │
│ Text?    │   │                 │
└────┬─────┘   └────────┬────────┘
     │                  │
     ▼                  ▼
┌────────────────────┐  ┌────────────────────────┐
│ Toast: "📝..."     │  │ Toast: "✨ Completing" │
│ Skip clipboard     │  │ Full context capture   │
│ Open PromptWindow  │  │ (existing flow)        │
│ Auto-trigger       │  │                        │
│ summarization      │  │                        │
└───────┬────────────┘  └───────────┬────────────┘
        │                           │
        ▼                           ▼
┌────────────────────┐  ┌────────────────────────┐
│ PromptWindow       │  │ Generate & Insert      │
│ shows with summary │  │ (existing autocomplete)│
│ streaming in       │  │                        │
│ ResponseView       │  │                        │
└────────────────────┘  └────────────────────────┘
```

### Component Interaction Flow - Prompt Mode (⌘+⇧+Space)

```
┌─────────────────────────────────────────────────────────────────┐
│                    PROMPT MODE (⌘+⇧+Space) - With Summarize      │
└─────────────────────────────────────────────────────────────────┘

     ⌘+⇧+Space
       │
       ▼
┌──────────────────┐
│  HotkeyManager   │  ← Existing prompt hotkey
└────────┬─────────┘
         │
         ▼
┌────────────────────────────┐
│ handleHotkeyActivation     │  ← Existing, slight modification
└────────────┬───────────────┘
             │
             ▼
┌────────────────────────────┐
│ SelectionDetector          │  ← Check for selection FIRST
│   .detectSelection()       │
└────────────┬───────────────┘
             │
      ┌──────┴──────┐
      │             │
      ▼             ▼
┌──────────┐   ┌─────────────────┐
│ Selected │   │ No Selection    │
│ Text?    │   │                 │
└────┬─────┘   └────────┬────────┘
     │                  │
     ▼                  ▼
┌────────────────────┐  ┌────────────────────────┐
│ Skip clipboard     │  │ Full context capture   │
│ Show PromptWindow  │  │ (existing flow)        │
│ WITH Summarize btn │  │                        │
└───────┬────────────┘  └───────────┬────────────┘
        │                           │
        ▼                           ▼
┌────────────────────────────────────────────────┐
│ PromptView                                      │
│   [Summarize] button visible when selection     │
│   [Text input] for custom instruction           │
│   [Enter] to execute                            │
└────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Selection Detection First**: Check for `selectedText` via Accessibility BEFORE clipboard capture
2. **Skip Clipboard When Selection Exists**: Major UX improvement - 400-600ms faster
3. **Enhance Existing Hotkeys**: No new hotkeys - reuse ⌥+Tab and ⌘+⇧+Space with smart behavior
4. **Summarize Button in Prompt**: Low-friction way to summarize without typing
5. **Magic Mode Naming**: Rename "Autocomplete" to "Magic" to reflect dual behavior

## API Contracts

### Summary Models (Core/Models/Summary.swift)

```swift
/// Supported summary output formats
enum SummaryFormat: String, CaseIterable, Codable {
    case paragraph = "paragraph"
    case bullets = "bullets"
    case keyPoints = "keyPoints"
    case actionItems = "actionItems"
}

/// Summary length preference
enum SummaryLength: String, CaseIterable, Codable {
    case short = "short"      // ~25% of original
    case medium = "medium"    // ~50% of original
    case long = "long"        // ~75% of original
}

/// Request for summarization
struct SummaryRequest {
    let selectedText: String
    let source: ContextSource
    let format: SummaryFormat
    let length: SummaryLength
}

/// Result of summarization
struct SummaryResult {
    let summary: String
    let format: SummaryFormat
    let wordCount: Int
    let originalWordCount: Int
    let generationTime: TimeInterval
}
```

### Summarizer Protocol (Core/Protocols/Summarizer.swift)

```swift
/// Protocol for summarization implementations
protocol Summarizer {
    /// Generate a summary from text
    func summarize(request: SummaryRequest) async throws -> SummaryResult

    /// Stream summary generation
    func summarizeStream(request: SummaryRequest) -> AsyncThrowingStream<String, Error>
}
```

### SummarizationService (Core/Services/SummarizationService.swift)

```swift
/// Orchestrates the summarization workflow
final class SummarizationService: Summarizer {
    static let shared = SummarizationService()

    /// Capture currently selected text from active application
    func captureSelectedText() async throws -> (text: String, source: ContextSource)

    /// Summarize with streaming response
    func summarizeStream(request: SummaryRequest) -> AsyncThrowingStream<String, Error>
}
```

## Prompt Templates

Add to PromptBuilder.swift:

```swift
private let summarizeTemplate = """
{{SYSTEM_PROMPT}}

## SUMMARIZATION MODE

You are summarizing the following text. Provide a {{FORMAT}} summary that is {{LENGTH}}.

Original Text:
\"\"\"
{{SELECTED_TEXT}}
\"\"\"

Rules:
- Preserve key information and main points
- Maintain factual accuracy - do not add information not in the original
- Match the requested format exactly
- Be concise but complete
- Output ONLY the summary, no explanations or metadata
"""
```

## Integration Points

1. **SelectionDetector**: NEW utility to quickly check for selected text via Accessibility API
2. **ContextOrchestrator**: MODIFY to support fast-path when selection exists (skip clipboard capture)
3. **AppDelegate**: MODIFY `handleAutocompleteActivation()` → `handleMagicModeActivation()` with branching
4. **PromptView**: MODIFY to add "Summarize" button when selection exists
5. **PromptBuilder**: ADD `buildSummarizePrompt()` method

## Complexity Tracking

| Decision | Rationale | Alternative Rejected |
|----------|-----------|---------------------|
| Enhance existing hotkeys | No new hotkeys to learn, intuitive | Separate ⌥+S hotkey adds cognitive load |
| Selection = summarize intent | Natural mental model | Always ask what to do (slower) |
| Skip clipboard when selected | 400-600ms performance gain | Always do full capture (wasteful) |
| Summarize button in Prompt | One-click action, no typing needed | Only support typed "summarize" command |

## UX Decisions (Finalized)

### Decision 1: Magic Mode Result Display
**Choice**: Open Prompt Window with summarization already triggered

**Rationale**: Reuses existing UI infrastructure (PromptWindow + ResponseView), provides familiar interface, allows user to copy/insert/refine the summary.

### Decision 2: Visual Feedback
**Choice**: Yes - show toasts for transparency

- When ⌥+Tab with selection → Toast: "📝 Summarizing..."
- When ⌥+Tab without selection → Toast: "✨ Completing..."

### Decision 3: Selection = Always Summarize
**Choice**: Selection always triggers summarize (no edge cases)

**Rationale**: Simpler mental model. Users who want autocomplete simply deselect first.

### Decision 4: Summarize Button Priority
**Choice**: Secondary button (not primary)

**Rationale**: Users can experiment with it. Primary action remains typing custom instruction. Can promote to primary based on usage data.

## Documentation Updates Required

Per Constitution Section IV (Documentation Synchronization):

1. **README.md**: Update feature descriptions, explain Magic Mode behavior
2. **Extremis/docs/flow-diagram.md**: Add selection-aware flow diagrams
3. **Preferences documentation**: Document behavior customization options
