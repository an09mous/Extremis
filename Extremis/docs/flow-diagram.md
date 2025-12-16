# Extremis Code Flow Diagram

This document describes the complete flow for **Magic Mode**, **Prompt Mode**, and **Summarization** in Extremis.


================================================================================
                              MAGIC MODE (⌥+Tab)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    CONTEXT-AWARE SMART ACTION                           │
  │         Text Selected → Summarize | No Selection → Autocomplete         │
  └─────────────────────────────────────────────────────────────────────────┘

       ⌥+Tab
         │
         ▼
  ┌──────────────────┐
  │  HotkeyManager   │
  │  (Carbon Events) │
  └────────┬─────────┘
           │
           ▼
  ┌────────────────────────────┐
  │ handleMagicModeActivation  │  ← AppDelegate.swift
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ ContextOrchestrator        │
  │   .captureContext()        │──────────────────┐
  └────────────┬───────────────┘                  │
               │                                   │
               ▼                                   ▼
  ┌────────────────────────────┐      ┌─────────────────────────┐
  │ Check: Has Selected Text?  │      │   CONTEXT CAPTURE       │
  └────────────┬───────────────┘      │   (See below)           │
               │                      └─────────────────────────┘
      ┌────────┴────────┐
      ▼                 ▼
  ┌────────┐      ┌────────────┐
  │  YES   │      │    NO      │
  │Selected│      │ No Select  │
  └───┬────┘      └─────┬──────┘
      │                 │
      ▼                 ▼
  ┌────────────┐  ┌────────────────┐
  │ SUMMARIZE  │  │ AUTOCOMPLETE   │
  │ Selection  │  │ at cursor      │
  └─────┬──────┘  └───────┬────────┘
        │                 │
        ▼                 ▼
  ┌────────────┐  ┌────────────────┐
  │Summarize   │  │generateStream( │
  │Service     │  │ instruction:"" │
  │.summarize()│  │ context        │
  └─────┬──────┘  └───────┬────────┘
        │                 │
        └────────┬────────┘
                 │
                 ▼
  ┌────────────────────────────┐
  │ TextInserterService        │
  │   .insert(text, source)    │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ ✅ Text Inserted at Cursor │
  └────────────────────────────┘


================================================================================
                              PROMPT MODE (⌘+⇧+Space)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         INTERACTIVE PROMPT UI                           │
  │         Summarize, Transform, or Autocomplete with instructions         │
  └─────────────────────────────────────────────────────────────────────────┘

       ⌘+⇧+Space
         │
         ▼
  ┌──────────────────┐
  │  HotkeyManager   │
  │  (Carbon Events) │
  └────────┬─────────┘
           │
           ▼
  ┌────────────────────────────┐
  │ handleHotkeyActivation     │  ← AppDelegate.swift
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ ContextOrchestrator        │
  │   .captureContext()        │──────────────────┐
  └────────────┬───────────────┘                  │
               │                                   │
               ▼                                   ▼
  ┌────────────────────────────┐      ┌─────────────────────────┐
  │ PromptWindowController     │      │   CONTEXT CAPTURE       │
  │   .showPrompt(context)     │      │   (See below)           │
  └────────────┬───────────────┘      └─────────────────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ PromptView shows:          │
  │  - Context info bar        │
  │  - Instruction text field  │
  │  - Summarize button        │  ← Shows when hasContext=true
  │    (if text/context avail) │
  └────────────┬───────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
  ┌────────────┐  ┌─────────────────┐
  │ Click      │  │ Type instruction│
  │ Summarize  │  │ + Press Enter   │
  └─────┬──────┘  └───────┬─────────┘
        │                 │
        ▼                 ▼
  ┌────────────┐  ┌─────────────────┐
  │Summarize   │  │ Transform/      │
  │Service     │  │ Autocomplete    │
  └─────┬──────┘  └───────┬─────────┘
        │                 │
        └────────┬────────┘
                 │
                 ▼
  ┌────────────────────────────┐
  │ ResponseView               │
  │   [Shows AI response]      │
  └────────────┬───────────────┘
               │
      ┌────────┼────────┐
      ▼        ▼        ▼
   ┌─────┐  ┌─────┐  ┌─────┐
   │⌘+↵  │  │⌘+C  │  │ Esc │
   │Insert│  │Copy │  │Cancel│
   └──┬──┘  └──┬──┘  └──┬──┘
      │        │        │
      ▼        ▼        ▼
  ┌────────┐  ┌────┐  ┌────────┐
  │TextIns-│  │Clip│  │Window  │
  │erter   │  │board│  │Closes  │
  └────────┘  └────┘  └────────┘


================================================================================
                              CONTEXT CAPTURE (Shared)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    Used by both Autocomplete and Prompt modes           │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌────────────────────────────┐
  │ ContextOrchestrator        │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Get Frontmost App          │
  │   (NSWorkspace)            │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ ExtractorRegistry          │
  │   .extractor(for: source)  │
  └────────────┬───────────────┘
               │
      ┌────────┴────────┬───────────────┐
      ▼                 ▼               ▼
  ┌─────────┐    ┌───────────┐    ┌───────────┐
  │ Generic │    │  Browser  │    │   Slack   │
  │Extractor│    │ Extractor │    │ Extractor │
  └────┬────┘    └─────┬─────┘    └─────┬─────┘
       │               │                │
       └───────────────┼────────────────┘
                       │
                       ▼
          ┌────────────────────────┐
          │ captureTextAroundCursor│  ← Protocol extension
          └────────────┬───────────┘
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
  ┌──────────────────┐    ┌──────────────────┐
  │captureVisibleCont│    │captureSucceeding │
  │ent (Preceding)   │    │Content (After)   │
  └────────┬─────────┘    └────────┬─────────┘
           │                       │
           └───────────┬───────────┘
                       │
                       ▼
          ┌────────────────────────┐
          │ Build Context Object   │
          │  - source              │
          │  - precedingText       │
          │  - succeedingText      │
          │  - selectedText        │
          │  - metadata            │
          └────────────────────────┘


================================================================================
                         MARKER-BASED CAPTURE (ClipboardCapture)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Why Marker? Accessibility APIs don't work in Electron apps (VS Code)   │
  └─────────────────────────────────────────────────────────────────────────┘

  PRECEDING TEXT (captureVisibleContent)
  ──────────────────────────────────────

  Cursor: "Hello World|"  (| = cursor position)

  Step 1: Save clipboard
  Step 2: Release modifiers (important for ⌘+⇧+Space hotkey)
  Step 3: Type space marker     →  "Hello World |"
  Step 4: ⌘+⇧+↑ (select up)     →  "█████████████"  (all selected)
  Step 5: ⌘+C (copy)            →  Clipboard: "Hello World "
  Step 6: → (right arrow)       →  Deselect, cursor at end
  Step 7: ⌫ (backspace)         →  "Hello World|"  (marker deleted)
  Step 8: Strip last char       →  Result: "Hello World"
  Step 9: Restore clipboard


  SUCCEEDING TEXT (captureSucceedingContent)
  ──────────────────────────────────────────

  Cursor: "|Hello World"  (| = cursor position)

  Step 1: Save clipboard
  Step 2: Release modifiers
  Step 3: Type space marker     →  " |Hello World"
  Step 4: ← (left arrow)        →  "| Hello World"  (cursor before marker)
  Step 5: ⌘+⇧+↓ (select down)   →  "█████████████"  (all selected)
  Step 6: ⌘+C (copy)            →  Clipboard: " Hello World"
  Step 7: ← (left arrow)        →  Deselect, cursor at start
  Step 8: ⌦ (delete forward)    →  "|Hello World"  (marker deleted)
  Step 9: Strip first char      →  Result: "Hello World"
  Step 10: Restore clipboard


================================================================================
                              TEXT INSERTION
================================================================================

  ┌────────────────────────────┐
  │ TextInserterService        │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Find target app            │
  │   (by bundleIdentifier)    │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Activate app               │
  │   .activate(options:)      │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ insertViaClipboard()       │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ 1. Save original clipboard │
  │ 2. Set text to clipboard   │
  │ 3. ⌘+V (paste)             │
  │ 4. Restore clipboard       │
  └────────────────────────────┘


================================================================================
                              SUMMARIZATION FLOW
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    Summarize selected text or context                   │
  └─────────────────────────────────────────────────────────────────────────┘

  Triggered via:
  - Click "Summarize" button in Prompt Mode
  - ⌥+Tab (Magic Mode) when text is selected

  ┌────────────────────────────┐
  │ PromptViewModel            │
  │   .summarizeSelection()    │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Determine text to summarize│
  │  - selectedText (priority) │
  │  - OR preceding+succeeding │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Build SummaryRequest       │
  │  - text                    │
  │  - source (app info)       │
  │  - surroundingContext      │
  │  - format (paragraph)      │
  │  - length (normal)         │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ SummarizationService       │
  │   .summarizeStream()       │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ PromptBuilder              │
  │   .buildSummarizationPrompt│
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────────────────────────────┐
  │ Summarization Prompt includes:                     │
  │  - System prompt                                   │
  │  - Text to summarize                               │
  │  - [Source Information]                            │
  │      • Application name                            │
  │      • Window title                                │
  │      • URL (for browsers)                          │
  │  - [App Metadata] (Slack/Gmail/GitHub context)     │
  │  - Format & length instructions                    │
  │                                                    │
  │  NOTE: No preceding/succeeding text               │
  │        (avoids duplicating summarized content)     │
  └────────────────────────────────────────────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ provider.generateRawStream │  ← Uses raw prompt (no re-wrapping)
  │   (prompt: builtPrompt)    │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Stream response to UI      │
  └────────────────────────────┘
