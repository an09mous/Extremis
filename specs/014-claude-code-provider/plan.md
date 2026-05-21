# Implementation Plan: Claude Code CLI Provider

**Branch**: `014-claude-code-provider` | **Date**: 2026-05-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-claude-code-provider/spec.md`

## Summary

Add Claude Code as a new LLM provider in Extremis that communicates with a persistent `claude` CLI process using bidirectional stream-json I/O (`--input-format stream-json --output-format stream-json`), the same approach used by VS Code's Claude Code extension. The process starts when the provider is activated and stays warm — eliminating ~5.5s per-message CLI startup overhead. No API key required — leverages the user's existing Claude Code subscription auth. Tool execution is display-only (CLI handles tools, Extremis renders events). Users can configure allowed tools for auto-approval via Preferences.

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency
**Primary Dependencies**: Foundation (Process, Pipe), SwiftUI + AppKit hybrid, existing LLMProvider protocol
**Storage**: UserDefaults (model selection, binary path, allowed tools)
**Testing**: Standalone Swift test files with TestRunner pattern (per project convention)
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single Swift Package Manager project
**Performance Goals**: Streaming latency indistinguishable from API providers; UI remains responsive during generation
**Constraints**: One persistent Process per provider activation; bidirectional stdin/stdout pipes; no external dependencies
**Scale/Scope**: 3 new Swift files (provider + parser + process manager), 2 test files, 3 modified files (enum, registry, UI)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modularity & Separation of Concerns | PASS | New provider is self-contained. CLIStreamParser is a separate reusable module. No modifications to unrelated code paths. |
| II. Code Quality & Best Practices | PASS | Follows existing provider patterns (OllamaProvider). Swift Concurrency for async operations. Descriptive naming. |
| III. Extensibility & Testability | PASS | Implements existing LLMProvider protocol. Stream parser is independently testable. Business logic separated from I/O. |
| IV. User Experience Excellence | PASS | Streaming matches API providers. Clear status indicators. Limitation notice for tool constraints. |
| V. Documentation Synchronization | PASS | README, CLAUDE.md, and docs will be updated with new provider info. |
| VI. Testing Discipline | PASS | Unit tests for stream parser (deterministic, no external deps). Provider tests for model/config logic. |
| VII. Regression Prevention | PASS | Additive change — new enum case, new provider class, new UI row. No modifications to existing provider logic. |

**Post-Phase 1 Re-check**: All gates remain PASS. Design is additive with no modifications to existing provider implementations.

## Project Structure

### Documentation (this feature)

```text
specs/014-claude-code-provider/
├── spec.md
├── plan.md              # This file
├── research.md          # CLI flags, streaming format, best practices
├── data-model.md        # Entity definitions and state transitions
├── quickstart.md        # Setup and verification guide
├── contracts/
│   └── cli-interface.md # CLI invocation and output format contract
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Extremis/
├── LLMProviders/
│   ├── ClaudeCodeProvider.swift    # NEW: Main provider implementation
│   ├── ClaudeCodeProcessManager.swift # NEW: Persistent process lifecycle manager
│   └── CLIStreamParser.swift       # NEW: JSONL stream event parser
├── Core/Models/
│   └── Generation.swift            # MODIFY: Add .claudeCode to LLMProviderType
├── Resources/
│   └── models.json                 # MODIFY: Add "claudecode" provider entry
├── UI/Preferences/
│   └── ProvidersTab.swift          # MODIFY: Add Claude Code provider row
└── Tests/LLMProviders/
    ├── ClaudeCodeProviderTests.swift  # NEW: Provider unit tests
    └── CLIStreamParserTests.swift     # NEW: Stream parser tests
```

**Structure Decision**: Follows existing single-project SPM structure. New files placed in existing directories matching their module (LLMProviders for provider code, Tests/LLMProviders for tests). No new directories needed.

## Design Decisions

### D1: Persistent Process with Bidirectional Stream-JSON I/O

**Decision**: Launch one long-lived `claude` process per provider activation using `--input-format stream-json --output-format stream-json`. Send messages via stdin, read responses from stdout.

**Rationale**: Benchmarking showed ~5.5s CLI startup overhead per process spawn (binary init + auth + config loading + tool discovery). Spawning per message would mean ~8s TTFT per chat turn — unacceptable for a chat UX. VS Code's Claude Code extension uses this exact pattern. With a warm process, per-message TTFT drops to ~2-3s (API latency only).

**Lifecycle**:
- Process starts when user selects Claude Code as active provider
- Process stays alive across all messages and sessions
- Process terminates when user switches to another provider or quits Extremis
- Lazy restart on crash (next message attempt triggers restart, not immediate)

**Process Safety (CRITICAL)**:

1. **No dangling processes**: Every code path that can terminate the app or switch providers MUST call `stop()`. Register cleanup in:
   - `NSApplication.willTerminateNotification`
   - `AppDelegate.applicationWillTerminate()`
   - Provider deactivation in `LLMProviderRegistry.setActive()`

2. **Lazy restart on crash**: When the process dies unexpectedly, do NOT immediately respawn. Instead:
   - Set `processState = .stopped`
   - On next `sendMessage()` call, detect stopped state and call `start()` transparently
   - This avoids restart loops if the CLI has a persistent failure (e.g., auth expired)

3. **Process reference tracking**: `ClaudeCodeProcessManager` MUST hold the sole strong reference to the `Process` instance. No leaked references from closures or notification handlers.

4. **Pipe cleanup**: Close all three pipes (stdin, stdout, stderr) before releasing the Process. Unclosed pipes can leak file descriptors.

5. **Termination timeout**: After calling `process.terminate()`, wait up to 3 seconds for exit. If still alive, call `process.terminate()` again (escalate to SIGKILL is not needed — `terminate()` sends SIGTERM which claude handles).

6. **Guard against double-start**: `start()` must be a no-op if process is already in `.ready` or `.starting` state. Prevent race conditions from rapid provider toggling.

### D1.1: Additive Code Changes — No Regressions

**Decision**: All changes MUST be purely additive. No modifications to existing provider logic, protocol definitions, or shared services beyond the minimum required (enum case, registry registration, UI row).

**Rules**:
- Do NOT modify `LLMProvider` protocol
- Do NOT modify existing provider implementations (OpenAI, Anthropic, Gemini, Ollama)
- Do NOT modify `ToolEnabledChatService` or `ToolExecutor`
- Only touch `Generation.swift` to add the new enum case + properties
- Only touch `LLMProviderRegistry.swift` to add one `providers.append()` line
- Only touch `ProvidersTab.swift` to add one new provider row
- All new logic lives in new files: `ClaudeCodeProvider.swift`, `ClaudeCodeProcessManager.swift`, `CLIStreamParser.swift`
- Run full test suite before and after to verify zero regressions

### D2: Stream Parser as Separate Module

**Decision**: Extract JSONL parsing into `CLIStreamParser.swift` rather than embedding in provider.

**Rationale**: Constitution Principle I (Modularity). The parser handles JSON deserialization and event classification independently of Process management. This makes it unit-testable with hardcoded JSONL strings — no subprocess needed.

### D3: No `--bare` Mode

**Decision**: Do NOT use `--bare` flag when invoking the CLI.

**Rationale**: `--bare` requires explicit API key auth and skips OAuth. The core value proposition is using the existing Claude Code subscription without managing API keys. Standard mode picks up the user's OAuth session automatically.

### D4: CLI Manages Conversation History

**Decision**: The persistent CLI process manages its own conversation context. Extremis sends individual `user_message` events via stdin.

**Rationale**: Since the process stays warm, the CLI maintains full conversation state internally. This is simpler than serializing/reconstructing conversation history per turn and avoids the 10MB stdin limit for long conversations.

### D5: Tool Support Boundary

**Decision**: `supportsTools` returns `false` from `LLMModel.capabilities`. Provider does NOT participate in Extremis's tool execution loop.

**Rationale**: CLI handles its own tool execution internally. Extremis renders tool events from the stream as display-only indicators in the chat UI. The bidirectional stream-json I/O carries tool_use and tool_result events that we parse and display.

### D6: Vision Support

**Decision**: `supportsVision` returns `false`. Images are not passed to the CLI.

**Rationale**: The stream-json input format does not support image data. If image attachments are present, the provider will process text content only.

### D7: System Prompt Injection

**Decision**: Use `--append-system-prompt` flag at process launch to inject Extremis's system prompt.

**Rationale**: This appends to the CLI's default system prompt rather than replacing it, preserving the CLI's built-in capabilities while adding Extremis's context-aware instructions. Set once at process startup.

## Complexity Tracking

> No constitution violations. All gates pass. No complexity justification needed.

## Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| Research | [research.md](research.md) | Complete |
| Data Model | [data-model.md](data-model.md) | Complete |
| CLI Contract | [contracts/cli-interface.md](contracts/cli-interface.md) | Complete |
| Quickstart | [quickstart.md](quickstart.md) | Complete |
| Tasks | tasks.md | Pending (`/speckit.tasks`) |
