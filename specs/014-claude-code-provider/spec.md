# Feature Specification: Claude Code CLI Provider

**Feature Branch**: `014-claude-code-provider`
**Created**: 2026-05-21
**Status**: Draft
**Input**: User description: "Build claude code as a provider in extremis. It's not API based but CLI based"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Select and Use Claude Code as Provider (Priority: P1)

A user who has the Claude Code CLI (`claude`) installed on their machine wants to use it as their LLM provider in Extremis. They navigate to Preferences, select "Claude Code" from the provider list, and start generating text using Claude Code as the backend. No API key is required — the CLI manages its own authentication.

**Why this priority**: This is the core value of the feature. Without the ability to select and use Claude Code as a provider, nothing else matters.

**Independent Test**: Can be fully tested by selecting Claude Code in Preferences, typing a prompt, and receiving a streamed response in the prompt window.

**Acceptance Scenarios**:

1. **Given** Claude Code CLI is installed on the system, **When** the user opens Preferences and selects "Claude Code" as the active provider, **Then** the provider is activated and ready for use without requiring an API key.
2. **Given** Claude Code is the active provider, **When** the user triggers a hotkey and enters a prompt, **Then** the response streams back to the prompt window in real-time.
3. **Given** Claude Code CLI is not installed, **When** the user tries to select Claude Code as a provider, **Then** the system shows a clear message that the CLI is not found and provides guidance on how to install it.

---

### User Story 2 - Streaming Chat Conversations via CLI (Priority: P1)

A user wants to have multi-turn chat conversations through Claude Code CLI, with context from previous messages maintained across turns, just like other providers in Extremis.

**Why this priority**: Chat mode is a core Extremis interaction pattern. The provider must support full conversation history to be a viable option.

**Independent Test**: Can be tested by starting a chat session, sending multiple messages, and verifying the assistant responses are contextually aware of previous turns.

**Acceptance Scenarios**:

1. **Given** an active chat session with Claude Code provider, **When** the user sends a follow-up message, **Then** the response reflects awareness of the full conversation history.
2. **Given** a long conversation, **When** the user sends a new message, **Then** the system passes the conversation context to the CLI and streams the response back.

---

### User Story 3 - Quick Mode and Magic Mode Support (Priority: P2)

A user selects text in any application and triggers Quick Mode (Option+Space) or Magic Mode (Option+Tab). The Claude Code provider processes the selected text with the appropriate intent (transform or summarize) and returns results.

**Why this priority**: These are secondary interaction modes that build on the core provider capability.

**Independent Test**: Can be tested by selecting text in any app, triggering the hotkey, and verifying the response is generated using Claude Code.

**Acceptance Scenarios**:

1. **Given** text is selected and Claude Code is the active provider, **When** the user triggers Quick Mode, **Then** the selected text is processed and the response streams back.
2. **Given** text is selected and Claude Code is the active provider, **When** the user triggers Magic Mode, **Then** the selected text is summarized and inserted.

---

### User Story 4 - Display-Only Tool Activity Rendering (Priority: P3)

When Claude Code CLI executes its own tools during generation, the user sees tool use and tool result events rendered in the Extremis chat UI. Extremis does not execute tools itself — it parses and displays what the CLI did. A limitation notice is shown when selecting Claude Code provider indicating that Extremis MCP connectors are not available with this provider.

**Why this priority**: Tool visibility is a nice-to-have. Core chat and generation must work first. This is display-only — no execution logic needed in Extremis.

**Independent Test**: Can be tested by sending a prompt that triggers CLI tool use and verifying tool_use/tool_result events appear in the chat UI.

**Acceptance Scenarios**:

1. **Given** Claude Code is the active provider and the CLI uses a tool during generation, **When** tool_use and tool_result events appear in the stream, **Then** Extremis renders them visually in the chat message (showing tool name, arguments, and result).
2. **Given** Claude Code is selected as the active provider, **When** the user views the provider selection UI, **Then** a limitation notice is displayed: "Tool execution is managed by Claude Code CLI. Extremis connectors are not available with this provider."
3. **Given** Claude Code is the active provider, **When** tool events are not present in the stream, **Then** the chat UI behaves identically to a normal text-only response.

---

### User Story 5 - Configure Allowed Tools for Auto-Approval (Priority: P3)

When configuring the Claude Code provider in Extremis Preferences, the user sees a list of tools available in their Claude Code CLI installation. The user can check/uncheck which tools are auto-approved. Only checked tools are passed via `--allowedTools` to the CLI subprocess, controlling what the CLI can execute without interactive approval.

**Why this priority**: Depends on tool rendering (Story 4) and is a configuration refinement. Core generation must work first.

**Independent Test**: Can be tested by opening Claude Code provider settings, toggling tool approvals, sending a prompt, and verifying only approved tools are executed by the CLI.

**Acceptance Scenarios**:

1. **Given** Claude Code CLI is installed, **When** the user opens Claude Code provider configuration, **Then** the system queries the CLI for available tools and displays them as a checklist.
2. **Given** the user has checked specific tools as auto-approved, **When** a generation is triggered, **Then** Extremis passes only those tools via `--allowedTools` to the CLI subprocess.
3. **Given** no tools are checked, **When** a generation is triggered, **Then** the CLI runs with no allowed tools (text-only generation).

---

### Edge Cases

- What happens when the persistent `claude` CLI process crashes or is killed unexpectedly?
- What happens when the CLI produces unexpected output format or non-parseable output?
- What happens when the user's Claude Code CLI version is outdated and doesn't support required flags?
- How does the system handle very long conversations that may exceed the CLI's context limits?
- What happens if a new message is sent while the previous generation is still in progress?
- What happens when the CLI is installed but not authenticated (no active session/subscription)?
- What happens if the CLI binary path contains spaces or special characters?
- What happens when the CLI's available tools list changes between sessions (tools added/removed)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST register Claude Code as a selectable LLM provider in the provider list alongside existing providers (OpenAI, Anthropic, Gemini, Ollama).
- **FR-002**: System MUST detect whether the `claude` CLI is installed and accessible on the user's PATH.
- **FR-003**: System MUST NOT require an API key for Claude Code provider; the CLI manages its own authentication.
- **FR-004**: System MUST launch a persistent `claude` CLI process using bidirectional stream-json I/O (`--input-format stream-json --output-format stream-json`) when the Claude Code provider is activated.
- **FR-005**: System MUST stream responses from the persistent CLI process in real-time to the prompt window, matching the streaming behavior of other providers.
- **FR-006**: System MUST send each user message to the persistent CLI process via stdin as a stream-json event; the CLI manages conversation history internally.
- **FR-007**: System MUST support all Extremis interaction modes (Quick Mode, Chat Mode, Magic Mode, Command Mode) through the Claude Code provider.
- **FR-008**: System MUST keep the CLI process alive for the lifetime of the provider selection — starting when Claude Code is activated and terminating when another provider is selected or Extremis quits. The process MUST be automatically restarted if it crashes.
- **FR-009**: System MUST display a clear status indicator when Claude Code CLI is not installed or not authenticated.
- **FR-010**: System MUST support cancellation of in-progress generations by sending an appropriate cancel signal to the persistent CLI process (without killing the process).
- **FR-011**: System MUST parse and display tool_use and tool_result events from the CLI stream output in the chat UI (display-only; Extremis does not execute tools for this provider).
- **FR-013**: System MUST display a limitation notice when Claude Code is selected, informing the user that Extremis MCP connectors are not available with this provider.
- **FR-012**: System MUST allow the user to configure a custom path to the `claude` CLI binary if it is not on the standard PATH.
- **FR-014**: System MUST query the Claude Code CLI for its available tools and display them in the provider configuration UI.
- **FR-015**: System MUST allow the user to select which CLI tools are auto-approved, and pass these as `--allowedTools` flags to the CLI subprocess during generation.
- **FR-016**: System MUST persist the user's tool approval selections across app restarts.

### Key Entities

- **Claude Code Provider**: The LLM provider implementation that wraps the `claude` CLI, managing subprocess lifecycle, I/O parsing, and streaming.
- **CLI Process**: A persistent subprocess of the `claude` binary using bidirectional stream-json I/O, kept alive for the lifetime of the provider selection.
- **CLI Configuration**: User-facing settings for the provider including custom binary path and CLI availability/authentication status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can select Claude Code as a provider and generate their first response within 30 seconds of configuration.
- **SC-002**: After initial process startup (~5s), per-message streaming latency is comparable to API-based providers (~2-3s TTFT).
- **SC-003**: All four interaction modes (Quick, Chat, Magic, Command) work with Claude Code provider with the same user experience as API-based providers.
- **SC-004**: The system correctly detects CLI availability and authentication status on every app launch.
- **SC-005**: In-progress generations can be cancelled within 1 second of the user pressing cancel.
- **SC-006**: The persistent CLI process starts within 6 seconds of provider activation and remains responsive for the session lifetime.

## Clarifications

### Session 2026-05-21

- Q: Should tool calling integrate with Extremis MCP connectors, or be display-only from CLI? → A: Display-only — Extremis parses and renders tool_use/tool_result events from the CLI stream but does not execute tools itself. Limitation notice shown in provider selection UI.
- Q: How should CLI tool approval be handled (CLI manages its own approval in non-interactive mode)? → A: Extremis queries available CLI tools and lets the user configure which are auto-approved via a checklist in Preferences. Approved tools are passed via `--allowedTools` to the subprocess.
- Q: How should multi-turn conversation history be managed? → A: Persistent process with bidirectional stream-json I/O (like VS Code). CLI process stays warm, messages sent via stdin. CLI manages conversation history internally. Eliminates ~5.5s per-message process spawn overhead.
- Q: What is the per-message latency? → A: Benchmarked on local machine: ~8s total per message with process-per-message approach (5.5s CLI overhead + 2.5s API). With persistent process, only ~2-3s TTFT (API latency only). Process startup is ~5s one-time cost when provider is activated.

## Assumptions

- The `claude` CLI supports bidirectional stream-json I/O (`--input-format stream-json --output-format stream-json`) for persistent process communication, as used by VS Code's Claude Code extension.
- The CLI supports streaming output that can be read incrementally (line-by-line JSONL).
- The CLI handles its own authentication (OAuth, API key, or subscription), so Extremis does not need to manage Claude credentials.
- The CLI manages conversation history internally when running as a persistent process. Extremis sends individual messages via stdin.
- Tool execution is handled entirely by the CLI. Extremis only renders tool activity from the stream (display-only). Extremis MCP connectors are not available when using Claude Code provider.
- The model selection is handled by the CLI's own configuration or can be specified via CLI flags.
