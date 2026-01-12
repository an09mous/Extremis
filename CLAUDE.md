# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build
cd Extremis && swift build

# Run the app
swift run Extremis
# OR after building:
.build/debug/Extremis

# Build release
swift build -c release

# Clean build
rm -rf .build && swift build
```

## Testing

All tests are standalone Swift files that can be compiled and run independently. The canonical way to run all tests is via the test script:

```bash
# Run all tests (preferred method)
cd Extremis && ./scripts/run-tests.sh
```

**Important**: All new tests MUST be added to `Extremis/scripts/run-tests.sh` so they run as part of the test suite.

Test files are located in `Extremis/Tests/` and organized by module:
- `Tests/Core/` - Core model and service tests (ChatConversation, SessionManager, etc.)
- `Tests/LLMProviders/` - Provider and prompt builder tests
- `Tests/Utilities/` - Utility class tests (Keychain, Clipboard, etc.)

To run a single test file manually:
```bash
swiftc -parse-as-library Extremis/Tests/Core/SessionManagerTests.swift -o /tmp/test && /tmp/test
```

## Project Overview

Extremis is a macOS menu bar app that provides context-aware LLM text generation via global hotkeys:
- **Option+Space**: Opens Quick Mode (with selection) or Chat Mode (without selection)
- **Option+Tab**: Magic Mode - summarizes selected text (no-op without selection)

Context is captured via AX metadata (app name, window title) and selected text when present.

**Tech Stack**: Swift 5.9+, SwiftUI + AppKit hybrid, macOS 13.0+ (Ventura)
**Build System**: Swift Package Manager (no external dependencies)
**Linked Frameworks**: Carbon (global hotkeys), ApplicationServices (Accessibility APIs)

## UI/UX Guidelines

**Strictly follow [Apple Human Interface Guidelines (HIG)](https://developer.apple.com/design/human-interface-guidelines/)** for all UI decisions.

## Architecture

### Directory Structure (under Extremis/)
- `App/` - Entry point (`ExtremisApp.swift`, `AppDelegate.swift`)
- `Core/Models/` - Data structures (ChatMessage, Context, Generation, Preferences)
- `Core/Services/` - Business logic (ContextOrchestrator, HotkeyManager, PermissionManager)
- `Core/Protocols/` - Interfaces (LLMProvider, ContextExtractor, TextInserter)
- `Extractors/` - App-specific context extractors (Browser, Slack, Generic)
- `LLMProviders/` - Provider implementations (OpenAI, Anthropic, Gemini, Ollama)
- `UI/PromptWindow/` - Main floating panel UI
- `UI/Preferences/` - Settings UI
- `Utilities/` - Helpers (KeychainHelper, ClipboardManager, AccessibilityHelpers)
- `Resources/` - Prompt templates, models.json, assets

### Key Patterns

**Singleton Services**: Access shared instances via `.shared`:
- `HotkeyManager.shared` - Global hotkey registration
- `ContextOrchestrator.shared` - Context extraction coordination
- `LLMProviderRegistry.shared` - Provider lifecycle management
- `TextInserterService.shared` - Text insertion into apps

**Extractor Pattern**: `ContextExtractorRegistry` maps bundle IDs to extractors:
- `GenericExtractor` - Fallback for all apps
- `BrowserExtractor` - Safari, Chrome, Firefox
- `SlackExtractor` - Slack desktop & web

**LLM Provider Pattern**: Factory pattern in `LLMProviderRegistry`:
- All providers implement `LLMProvider` protocol
- Streaming responses via `AsyncThrowingStream`
- API keys stored in Keychain

### AppKit + SwiftUI Hybrid

- **NSApplication**: Menu bar app (LSUIElement = true, no dock icon)
- **NSPanel**: Non-activating floating window for prompts
- **NSHostingView**: SwiftUI views embedded in AppKit windows
- **Carbon/HIToolbox**: Global hotkey registration

### Context Capture Pipeline

```
Hotkey triggered → SelectionDetector → ContextOrchestrator.captureContext()
→ ContextExtractorRegistry.extractor(for: source) → Appropriate Extractor
→ PromptWindowController.showPrompt(with: context)
```

### Conversation Model

- `ChatMessage` - Single message with role (user/assistant/system), content, timestamp
- `ChatConversation` - Observable collection with trimming logic
- `PersistedConversation` - Codable struct for disk storage (see `specs/007-memory-persistence/data-model.md`)

## Feature Specifications

Feature specs are in `specs/` directory, each containing:
- `spec.md` - User stories and acceptance criteria
- `plan.md` - Technical implementation plan
- `tasks.md` - Task breakdown
- `data-model.md` - Data model schemas (when applicable)

Latest completed feature: `specs/008-prompting-improvements/` (Prompting Improvements & Mode Simplification) ✅

## Key Files

- `Extremis/App/AppDelegate.swift` - Core app lifecycle, menu bar, hotkey handling
- `Extremis/Core/Services/ContextOrchestrator.swift` - Context extraction coordination
- `Extremis/UI/PromptWindow/PromptWindowController.swift` - Main UI controller
- `Extremis/LLMProviders/LLMProviderRegistry.swift` - Provider management
- `Extremis/Core/Models/ChatMessage.swift` - Chat data models

## Configuration & Storage

- **UserDefaults**: App preferences (active provider, hotkey config, appearance)
- **Keychain**: API keys stored as single JSON entry via `KeychainHelper`
- **Application Support**: `~/Library/Application Support/Extremis/` for session persistence
- **models.json**: LLM model configurations in Resources/

## Prompt Templates

**Important**: All LLM prompts MUST be stored as `.hbs` template files in `Extremis/Resources/PromptTemplates/`. Do NOT hardcode prompts in Swift code - always create a template file and load it via `PromptTemplateLoader`.

| Template | Purpose | Placeholders |
|----------|---------|--------------|
| `system.hbs` | Unified system prompt with capabilities, guidelines, security | None |
| `intent_instruct.hbs` | Quick Mode - selection transforms | `{{CONTENT}}` |
| `intent_chat.hbs` | Chat Mode - conversational messages | `{{CONTENT}}` |
| `intent_summarize.hbs` | Magic Mode - summarization | `{{CONTENT}}` |
| `session_summarization_initial.hbs` | First-time session summary | `{{CONTENT}}` |
| `session_summarization_update.hbs` | Hierarchical summary updates | `{{CONTENT}}` |

**Architecture**: Intent-based prompt injection - templates are selected based on `MessageIntent` enum and injected into user messages. Context is embedded inline with each user message, not in the system prompt.

**Adding a new prompt template**:
1. Create `my_template.hbs` in `Extremis/Resources/PromptTemplates/`
2. Add case to `PromptTemplate` enum in `LLMProviders/PromptTemplateLoader.swift`
3. Load via `PromptTemplateLoader.shared.load(.myTemplate)`
4. Use `String.replacingOccurrences(of:with:)` to substitute placeholders

## Development Guidelines

- **Documentation**: Always update `README.md` and `Extremis/docs/` when adding new features or modifying existing functionality. Keep documentation in sync with code changes.
- **Prompt Templates**: Never hardcode LLM prompts in Swift - always use `.hbs` template files in `Resources/PromptTemplates/`
- **Testing**: All new tests MUST be added to `Extremis/scripts/run-tests.sh`

## Tech Stack
- Swift 5.9+ with Swift Concurrency
- SwiftUI + AppKit hybrid (NSPanel, NSHostingView)
- Carbon (global hotkeys), ApplicationServices (Accessibility APIs)
- UserDefaults (preferences), Keychain (API keys), Application Support (sessions)
