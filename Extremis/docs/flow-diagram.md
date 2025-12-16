# Extremis Code Flow Diagram

This document describes the complete flow for both **Autocomplete Mode** and **Prompt Mode** in Extremis.


================================================================================
                              AUTOCOMPLETE MODE (⌥+Tab)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         INSTANT AUTO-COMPLETION                         │
  │                    No UI - Direct text insertion                        │
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
  │ handleAutocompleteActivation│  ← AppDelegate.swift
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ performDirectAutocomplete  │
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
  │ Get Active LLM Provider    │      │   CONTEXT CAPTURE       │
  │ (OpenAI/Anthropic/Gemini)  │      │   (See below)           │
  └────────────┬───────────────┘      └─────────────────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ generateStream(            │
  │   instruction: "",         │  ← Empty instruction = autocomplete
  │   context: context         │
  │ )                          │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ TextInserterService        │
  │   .insert(text, source)    │──────────────────┐
  └────────────┬───────────────┘                  │
               │                                   │
               ▼                                   ▼
  ┌────────────────────────────┐      ┌─────────────────────────┐
  │ ✅ Text Inserted at Cursor │      │   TEXT INSERTION        │
  └────────────────────────────┘      │   (See below)           │
                                      └─────────────────────────┘


================================================================================
                              PROMPT MODE (⌘+⇧+Space)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         INTERACTIVE PROMPT UI                           │
  │              User provides instruction before generation                │
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
  │ hidePrompt()               │  ← Clean state first
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ captureContextAndShowPrompt│
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
  │ PromptView                 │
  │   [User types instruction] │
  │   [Press Enter]            │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ PromptViewModel.generate() │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ provider.generate(         │
  │   instruction: userText,   │
  │   context: context         │
  │ )                          │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ ResponseView               │
  │   [Shows AI response]      │
  └────────────┬───────────────┘
               │
               ▼
        ┌──────┴──────┐
        │ User Action │
        └──────┬──────┘
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



