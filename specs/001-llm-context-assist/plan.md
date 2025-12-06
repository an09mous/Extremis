# Implementation Plan: Extremis - Context-Aware LLM Writing Assistant

**Branch**: `001-llm-context-assist` | **Date**: 2025-12-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-llm-context-assist/spec.md`

## Summary

Extremis is a macOS menu bar application that provides context-aware LLM writing assistance anywhere on the system. Users activate via a global hotkey, and the app captures context from the active application (Slack, Gmail, GitHub) using **Accessibility APIs and DOM inspection** (not screenshots), sends context + user instruction to an LLM (Gemini/Claude/ChatGPT), and inserts the generated text at the original cursor position.

**Key Technical Approach**:
- Native Swift/SwiftUI for macOS menu bar app with minimal footprint
- Accessibility APIs (AXUIElement) for context extraction from native apps
- AppleScript/JavaScript for browser DOM extraction (Safari/Chrome)
- Plugin architecture for extensible app-specific context extractors
- Protocol-based LLM provider abstraction for multi-provider support

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency (async/await)
**Primary Dependencies**: SwiftUI, AppKit, ApplicationServices (Accessibility), Carbon (Hotkeys)
**Storage**: UserDefaults for preferences, Keychain for API keys (no persistence for conversations - Phase 2)
**Testing**: XCTest for unit tests, XCUITest for UI automation
**Target Platform**: macOS 13.0 (Ventura) and later
**Project Type**: Single native macOS application
**Performance Goals**: <200ms hotkey-to-window, <50MB idle memory, <2s startup
**Constraints**: No Dock icon, minimal system resource usage, graceful permission handling
**Scale/Scope**: Single-user desktop app, 3 supported apps initially (Slack, Gmail, GitHub), extensible plugin architecture

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| **I. Modularity First** | Single Responsibility | ✅ PASS | Each module has clear purpose: ContextExtractor, LLMProvider, HotkeyManager, PromptWindow |
| | Loose Coupling | ✅ PASS | Protocol-based abstractions for extractors and LLM providers |
| | Dependency Injection | ✅ PASS | All services injected via protocols, enabling testing |
| | Plugin Architecture | ✅ PASS | App-specific extractors are pluggable modules |
| | No Circular Dependencies | ✅ PASS | Clear DAG: App → Services → Protocols |
| **II. Code Quality** | Type Safety | ✅ PASS | Swift's strong typing, no force unwraps |
| | Error Handling | ✅ PASS | Result types and typed errors throughout |
| | Testing | ✅ PASS | Unit tests for services, UI tests for flows |
| **III. UX Primacy** | Smooth Flows | ✅ PASS | Single hotkey → prompt → insert flow |
| | Performance | ✅ PASS | <200ms activation target |
| | Error Recovery | ✅ PASS | Clear error messages, retry options |

## Project Structure

### Documentation (this feature)

```text
specs/001-llm-context-assist/
├── plan.md              # This file
├── research.md          # Phase 0: Technology research
├── data-model.md        # Phase 1: Data structures
├── quickstart.md        # Phase 1: Developer setup guide
├── contracts/           # Phase 1: Protocol definitions
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```text
Extremis/
├── App/
│   ├── ExtremisApp.swift           # App entry point, menu bar setup
│   └── AppDelegate.swift           # App lifecycle, permissions
│
├── Core/
│   ├── Models/
│   │   ├── Context.swift           # Captured context data model
│   │   ├── Instruction.swift       # User instruction model
│   │   ├── Generation.swift        # LLM response model
│   │   └── Preferences.swift       # User preferences model
│   │
│   ├── Protocols/
│   │   ├── ContextExtractor.swift  # Protocol for app-specific extractors
│   │   ├── LLMProvider.swift       # Protocol for LLM services
│   │   └── TextInserter.swift      # Protocol for text insertion
│   │
│   └── Services/
│       ├── HotkeyManager.swift     # Global hotkey registration
│       ├── PermissionManager.swift # Accessibility/permissions handling
│       ├── PreferencesManager.swift# UserDefaults + Keychain
│       └── ContextOrchestrator.swift# Coordinates extraction flow
│
├── Extractors/                     # Plugin architecture for context
│   ├── ExtractorRegistry.swift     # Registry of available extractors
│   ├── GenericExtractor.swift      # Fallback: selected text via AX
│   ├── SlackExtractor.swift        # Slack-specific (AX + DOM)
│   ├── GmailExtractor.swift        # Gmail-specific (DOM)
│   └── GitHubExtractor.swift       # GitHub-specific (DOM)
│
├── LLMProviders/                   # Plugin architecture for LLMs
│   ├── ProviderRegistry.swift      # Registry of available providers
│   ├── OpenAIProvider.swift        # ChatGPT integration
│   ├── AnthropicProvider.swift     # Claude integration
│   └── GeminiProvider.swift        # Google Gemini integration
│
├── UI/
│   ├── PromptWindow/
│   │   ├── PromptWindowController.swift
│   │   ├── PromptView.swift        # Main SwiftUI view
│   │   └── ResponseView.swift      # AI response display
│   │
│   ├── Preferences/
│   │   ├── PreferencesWindow.swift
│   │   ├── GeneralTab.swift        # Hotkey, launch settings
│   │   ├── ProvidersTab.swift      # API key configuration
│   │   └── AppearanceTab.swift     # Theme settings
│   │
│   └── Components/
│       ├── LoadingIndicator.swift
│       └── KeyboardShortcutField.swift
│
├── Utilities/
│   ├── AccessibilityHelpers.swift  # AXUIElement wrappers
│   ├── BrowserBridge.swift         # AppleScript/JS execution
│   ├── ClipboardManager.swift      # Preserve/restore clipboard
│   └── KeychainHelper.swift        # Secure API key storage
│
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings

Tests/
├── ExtremisTests/
│   ├── Core/
│   │   ├── ContextOrchestratorTests.swift
│   │   └── PreferencesManagerTests.swift
│   │
│   ├── Extractors/
│   │   ├── GenericExtractorTests.swift
│   │   └── MockExtractorTests.swift
│   │
│   └── LLMProviders/
│       └── ProviderRegistryTests.swift
│
└── ExtremisUITests/
    ├── PromptWindowTests.swift
    └── PreferencesTests.swift
```

**Structure Decision**: Single native macOS app structure with clear separation:
- **Core/**: Framework-agnostic business logic and protocols
- **Extractors/**: Pluggable context extraction modules (one per supported app)
- **LLMProviders/**: Pluggable LLM integrations (one per provider)
- **UI/**: SwiftUI views and window controllers
- **Utilities/**: Shared helpers for system interactions

## Context Extraction Strategy

**Priority Order** (per user requirement - screenshot is LAST resort):

| Priority | Method | Use Case | Privacy Impact |
|----------|--------|----------|----------------|
| 1️⃣ | **Accessibility APIs (AX)** | Native apps, Electron apps | Low - only focused element |
| 2️⃣ | **DOM via AppleScript/JS** | Web apps in Safari/Chrome | Low - only page content |
| 3️⃣ | **Selected Text (AX)** | Fallback for any app | Minimal - user-selected only |
| 4️⃣ | **Screenshot + OCR** | Last resort if all else fails | Higher - captures visible screen |

### Extractor Flow

```
Hotkey Pressed
     │
     ▼
┌─────────────────┐
│ Get Active App  │ (via NSWorkspace)
│ Bundle ID       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│ ExtractorRegistry│────▶│ Matching Extractor│
│ lookup(bundleID)│     │ (or Generic)      │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐
│ Extractor       │
│ .extract()      │
│                 │
│ 1. Try AX APIs  │
│ 2. Try DOM/JS   │
│ 3. Fallback     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Context Object  │
│ ready for LLM   │
└─────────────────┘
```

## Complexity Tracking

> No constitution violations requiring justification.

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Multi-provider LLM | Protocol abstraction | Satisfies requirement, maintains modularity |
| Plugin extractors | Registry pattern | Extensible without modifying core code |
| No conversation persistence | In-memory only (Phase 2) | Per user requirement, interface ready for extension |
