# Tasks: Claude Code CLI Provider

**Input**: Design documents from `/specs/014-claude-code-provider/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli-interface.md, quickstart.md

**Tests**: Included per user request ("Add unit tests wherever possible").

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Project root**: `Extremis/`
- **Source**: `Extremis/LLMProviders/`, `Extremis/Core/Models/`, `Extremis/UI/Preferences/`
- **Tests**: `Extremis/Tests/LLMProviders/`
- **Resources**: `Extremis/Resources/`

---

## Phase 1: Setup

**Purpose**: Register Claude Code as a provider type, add model definitions, and prepare shared infrastructure.

- [X] T001 Add `.claudeCode` case to `LLMProviderType` enum and implement `displayName`, `requiresAPIKey`, `availableModels`, `defaultModel` properties in `Extremis/Core/Models/Generation.swift`
- [X] T002 [P] Add `"Claude Code"` provider entry with sonnet/opus/haiku models to `Extremis/Resources/models.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the JSONL stream parser and persistent process manager that ALL user stories depend on.

**CRITICAL**: No user story work can begin until this phase is complete.

### Tests for Foundational Phase

- [X] T003 [P] Create CLIStreamParser unit tests covering all event types (system/init, text_delta, thinking_delta, tool_use_start, input_json_delta, content_block_stop, message_stop, result/success, result/error, malformed JSON, empty lines) in `Extremis/Tests/LLMProviders/CLIStreamParserTests.swift`
- [X] T004 [P] Create ClaudeCodeProcessManager unit tests covering process state transitions (stopped→starting→ready→generating→ready, crash→stopped, double-start guard, stop idempotency) in `Extremis/Tests/LLMProviders/ClaudeCodeProcessManagerTests.swift`

### Implementation for Foundational Phase

- [X] T005 Implement `CLIStreamParser` — JSONL line parser with `parseLine(_ line: String) -> ParsedCLIEvent?` method, supporting all event types from contracts/cli-interface.md in `Extremis/LLMProviders/CLIStreamParser.swift`
- [X] T006 Implement `ClaudeCodeProcessManager` — persistent process lifecycle manager with `ProcessState` enum, `start()`, `sendMessage()`, `stop()`, `forceCleanup()` with all 6 process safety rules in `Extremis/LLMProviders/ClaudeCodeProcessManager.swift`
- [X] T007 Add new test files to `Extremis/scripts/run-tests.sh` and verify all foundational tests pass

**Checkpoint**: COMPLETE — 32 parser tests + 29 process manager tests pass.

---

## Phase 3: User Story 1 — Select and Use Claude Code as Provider (Priority: P1) MVP

### Tests for User Story 1

- [X] T008 [P] [US1] Create ClaudeCodeProvider unit tests covering: CLIToolInfo model, tool approval filtering, tool discovery merge, persistence, model aliases in `Extremis/Tests/LLMProviders/ClaudeCodeProviderTests.swift`

### Implementation for User Story 1

- [X] T009 [US1] Implement `ClaudeCodeProvider` class conforming to `LLMProvider` protocol in `Extremis/LLMProviders/ClaudeCodeProvider.swift`
- [X] T010 [US1] Register `ClaudeCodeProvider` in `LLMProviderRegistry.registerDefaultProviders()` with process activation/deactivation on provider switch in `Extremis/LLMProviders/LLMProviderRegistry.swift`
- [X] T011 [US1] Add Claude Code provider row (`ClaudeCodeProviderRow`) in `Extremis/UI/Preferences/ProvidersTab.swift`
- [X] T012 [US1] Register process cleanup in `AppDelegate.applicationWillTerminate()` and add startup check in `Extremis/App/AppDelegate.swift`
- [X] T013 [US1] Add US1 test file to `Extremis/scripts/run-tests.sh` — 39 tests pass

**Checkpoint**: COMPLETE — Provider registered, UI row added, process lifecycle managed.

---

## Phase 4: User Story 2 — Streaming Chat Conversations (Priority: P1)

- [X] T014 [US2] Multi-turn message sending implemented — `generateChatStream()` sends last user message via stdin; CLI manages conversation history internally
- [X] T015 [US2] Conversation reset implemented via `resetConversation()` which restarts the persistent process

**Checkpoint**: COMPLETE — CLI manages history, restart clears state.

---

## Phase 5: User Story 3 — Quick Mode and Magic Mode Support (Priority: P2)

- [X] T016 [US3] All `MessageIntent` types supported — `generateChatStream()` uses `PromptBuilder.shared.formatUserMessageWithContext()` which applies intent templates
- [X] T017 [US3] Vision handled — `supportsVision = false` in model capabilities; provider processes text content only

**Checkpoint**: COMPLETE — All interaction modes work.

---

## Phase 6: User Story 4 — Display-Only Tool Activity Rendering (Priority: P3)

- [X] T018 [P] [US4] Tool event parsing tests included in CLIStreamParser tests (tool_use_start, input_json_delta, tool_result)
- [X] T019 [US4] CLIStreamParser parses all tool events (toolUseStart, toolInputDelta, toolResult)
- [X] T020 [US4] `generateChatWithToolsStream()` streams text and emits `.complete(toolCalls: [])` — CLI handles tools internally
- [X] T021 [US4] Limitation notice displayed in `ClaudeCodeProviderRow`

**Checkpoint**: COMPLETE — Tool events parsed and displayed, limitation notice shown.

---

## Phase 7: User Story 5 — Configure Allowed Tools for Auto-Approval (Priority: P3)

- [X] T022 [US5] `CLIToolInfo` struct and `allowedTools` property defined with UserDefaults persistence
- [X] T023 [US5] `--allowedTools` flag passed at process launch with approved tool names
- [X] T024 [US5] Tool approval logic implemented in provider (UI checklist deferred to refinement)

**Checkpoint**: COMPLETE — Tool approvals persisted and passed to CLI.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T025 [P] Thinking delta support — `thinkingDelta` events parsed by CLIStreamParser
- [X] T026 [P] Rate limit events — `rateLimit` events parsed by CLIStreamParser
- [X] T027 Full test suite passes: 37 suites, 2025 tests, 0 failures
- [ ] T028 Run quickstart.md manual verification steps (requires running app with CLI installed)
- [X] T029 Update `CLAUDE.md` with new provider info, new files, and new key files entries

---

## Summary

| Metric | Count |
|--------|-------|
| **Total tasks** | 29 |
| **Completed** | 28 |
| **Remaining** | 1 (manual verification) |
| **New source files** | 3 (CLIStreamParser, ClaudeCodeProcessManager, ClaudeCodeProvider) |
| **New test files** | 3 (CLIStreamParserTests, ClaudeCodeProcessManagerTests, ClaudeCodeProviderTests) |
| **Modified files** | 5 (Generation.swift, models.json, LLMProviderRegistry.swift, ProvidersTab.swift, AppDelegate.swift) |
| **Test results** | 37 suites, 2025 tests, 0 failures |
