# Extremis Code Flow Diagram

This document describes the complete flow for **Magic Mode**, **Quick Mode**, **Chat Mode**, and **Summarization** in Extremis.


================================================================================
                              MAGIC MODE (Option+Tab)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    CONTEXT-AWARE SMART ACTION                           │
  │         Text Selected → Summarize | No Selection → No-op (silent)       │
  └─────────────────────────────────────────────────────────────────────────┘

       Option+Tab
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
  │ SelectionDetector          │
  │   .detectSelection()       │  ← Silent mode (verbose: false)
  └────────────┬───────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
  ┌────────┐      ┌────────────┐
  │  YES   │      │    NO      │
  │Selected│      │ No Select  │
  └───┬────┘      └─────┬──────┘
      │                 │
      ▼                 ▼
  ┌────────────┐  ┌────────────────┐
  │ SUMMARIZE  │  │    NO-OP       │
  │ Selection  │  │ (silent exit)  │
  └─────┬──────┘  └────────────────┘
        │
        ▼
  ┌────────────────────────────┐
  │ performSummarization()     │
  │   - Show loading toast     │
  │   - Build context          │
  │   - Open PromptWindow      │
  │   - Auto-trigger summarize │
  └────────────────────────────┘


================================================================================
                         PROMPT MODE (Cmd+Shift+Space)
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                         INTERACTIVE PROMPT UI                           │
  │      With Selection → Quick Mode | Without Selection → Chat Mode        │
  └─────────────────────────────────────────────────────────────────────────┘

       Cmd+Shift+Space
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
  │ captureContextAndShowPrompt│
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ SelectionDetector          │
  │   .detectSelection()       │
  └────────────┬───────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
  ┌────────────┐  ┌────────────────┐
  │   YES      │  │      NO        │
  │  Selected  │  │  No Selection  │
  └─────┬──────┘  └───────┬────────┘
        │                 │
        ▼                 ▼
  ┌────────────┐  ┌────────────────┐
  │ QUICK MODE │  │   CHAT MODE    │
  │ Instruction│  │  Conversational│
  │   Input    │  │    Interface   │
  └─────┬──────┘  └───────┬────────┘
        │                 │
        └────────┬────────┘
                 │
                 ▼
  ┌────────────────────────────┐
  │ PromptWindowController     │
  │   .showPrompt(context)     │
  └────────────────────────────┘


================================================================================
                              QUICK MODE FLOW
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  User has text selected - instruction-based transformation              │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌────────────────────────────┐
  │ PromptInputView shows:     │
  │  - Context info bar        │
  │  - Instruction text field  │
  │  - Summarize button        │  ← Shows when hasContext=true
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
  │Summarize   │  │ Transform       │
  │            │  │ Selection       │
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
                              CHAT MODE FLOW
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  No selection - conversational interface with session history           │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌────────────────────────────┐
  │ ResponseView (ChatView)    │
  │  - Session history         │  ← Shows previous messages
  │  - Chat input field        │  ← "Ask a follow-up question..."
  │  - Context info bar        │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ User types message         │
  │   + Press Enter            │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ sendChatMessage()          │
  │   - Add to session         │
  │   - Generate response      │
  │   - Stream to UI           │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Response added to session  │
  │   - Can continue chatting  │
  │   - Session persisted      │
  └────────────────────────────┘


================================================================================
                              CONTEXT CAPTURE
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    Used by all modes                                    │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌────────────────────────────┐
  │ SelectionDetector          │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Get Frontmost App          │
  │   (NSWorkspace)            │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────────────────────┐
  │ Try AX API first (fast path)               │
  │   - AXUIElementCreateApplication           │
  │   - kAXFocusedUIElementAttribute           │
  │   - kAXSelectedTextAttribute               │
  └────────────┬───────────────────────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
  ┌─────────┐     ┌───────────────┐
  │  Found  │     │   Not Found   │
  │Selection│     │   (AX fail)   │
  └────┬────┘     └───────┬───────┘
       │                  │
       │                  ▼
       │          ┌───────────────────────────┐
       │          │ Fallback: Clipboard-based │
       │          │   - Save clipboard        │
       │          │   - Cmd+C to copy         │
       │          │   - Check clipboard       │
       │          │   - Restore clipboard     │
       │          └───────────┬───────────────┘
       │                      │
       └──────────┬───────────┘
                  │
                  ▼
  ┌────────────────────────────────────────────┐
  │ Build Context Object                       │
  │   - source (app name, bundle ID, window)   │
  │   - selectedText (if any)                  │
  │   - metadata (generic/slack/browser)       │
  └────────────────────────────────────────────┘


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
  │ 3. Cmd+V (paste)           │
  │ 4. Restore clipboard       │
  └────────────────────────────┘


================================================================================
                              SUMMARIZATION FLOW
================================================================================

  ┌─────────────────────────────────────────────────────────────────────────┐
  │                    Summarize selected text                              │
  └─────────────────────────────────────────────────────────────────────────┘

  Triggered via:
  - Click "Summarize" button in Quick Mode
  - Option+Tab (Magic Mode) when text is selected

  ┌────────────────────────────┐
  │ PromptViewModel            │
  │   .summarize()             │
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ Build SummaryRequest       │
  │  - text (selected)         │
  │  - source (app info)       │
  │  - format (paragraph)      │
  │  - length (normal)         │
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
